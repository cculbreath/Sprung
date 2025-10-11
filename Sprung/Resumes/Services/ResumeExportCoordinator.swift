//
//  ResumeExportCoordinator.swift
//  Sprung
//
//  Created by Codex Agent on 10/23/25.
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

            guard self.saveJSON(for: resume) != nil else {
                resume.isExporting = false
                onFinish?()
                return
            }

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

        guard saveJSON(for: resume) != nil else {
            throw NSError(
                domain: "ResumeExportCoordinator",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to persist resume JSON prior to export."]
            )
        }

        resume.isExporting = true
        defer { resume.isExporting = false }

        do {
            try await exportService.export(for: resume)
        } catch {
            Logger.error("Immediate export failed: \(error)")
            throw error
        }
    }

    // MARK: - Helpers

    private func saveJSON(for resume: Resume) -> URL? {
        let jsonString = resume.jsonTxt
        guard let url = FileHandler.saveJSONToFile(jsonString: jsonString) else {
            Logger.error("Failed to write resume JSON to disk for export.")
            return nil
        }
        return url
    }
}
