//
//  ResumeExportCoordinator.swift
//  Sprung
//

import Foundation
import Observation

@MainActor
@Observable
final class ResumeExportCoordinator {
    private let exportService: ResumeExportService
    private var pendingWorkItems: [UUID: DispatchWorkItem] = [:]
    private let debounceInterval: TimeInterval

    init(
        exportService: ResumeExportService,
        debounceInterval: TimeInterval = 0.5
    ) {
        self.exportService = exportService
        self.debounceInterval = debounceInterval
    }

    /// Debounced export used for live editing flows.
    func debounceExport(
        resume: Resume,
        onStart: (() -> Void)? = nil,
        onFinish: (() -> Void)? = nil
    ) {
        cancelPendingExport(for: resume)
        resume.isExporting = true
        onStart?()

        let workItem = DispatchWorkItem { [weak self, weak resume] in
            guard let self, let resume else { return }

            Task { @MainActor in
                defer {
                    resume.isExporting = false
                    onFinish?()
                }

                do {
                    try await self.exportService.export(for: resume)
                } catch {
                    Logger.error("Debounced export failed: \(error)")
                }
            }
        }

        pendingWorkItems[resume.id] = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + debounceInterval,
            execute: workItem
        )
    }

    /// Cancels any pending debounced export for a resume.
    func cancelPendingExport(for resume: Resume) {
        guard let item = pendingWorkItems.removeValue(forKey: resume.id) else { return }
        item.cancel()
    }

    /// Performs an immediate export and waits for completion.
    func ensureFreshRenderedText(for resume: Resume) async throws {
        cancelPendingExport(for: resume)

        resume.isExporting = true
        defer { resume.isExporting = false }

        do {
            try await exportService.export(for: resume)
        } catch {
            Logger.error("Immediate export failed: \(error)")
            throw error
        }
    }
}
