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
    /// Observable set of resume IDs currently being exported.
    /// Views should check this instead of Resume.isExporting (@Transient
    /// properties on SwiftData models don't reliably trigger SwiftUI observation).
    private(set) var exportingResumeIDs: Set<UUID> = []
    /// Convenience check for a specific resume.
    func isExporting(_ resume: Resume) -> Bool {
        exportingResumeIDs.contains(resume.id)
    }
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
        exportingResumeIDs.insert(resume.id)
        onStart?()
        let workItem = DispatchWorkItem { [weak self, weak resume] in
            guard let self, let resume else { return }
            Task { @MainActor in
                defer {
                    self.exportingResumeIDs.remove(resume.id)
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
        exportingResumeIDs.remove(resume.id)
    }
    /// Performs an immediate export and waits for completion.
    /// Skips the expensive PDF+text render if the resume already has rendered text
    /// and no edits are pending, avoiding redundant work during batch operations.
    func ensureFreshRenderedText(for resume: Resume) async throws {
        let hasPendingChanges = pendingWorkItems[resume.id] != nil

        // Skip if text is already rendered and no edits are pending
        if !hasPendingChanges && !resume.textResume.isEmpty {
            return
        }

        cancelPendingExport(for: resume)
        exportingResumeIDs.insert(resume.id)
        defer { exportingResumeIDs.remove(resume.id) }
        do {
            try await exportService.export(for: resume)
        } catch {
            Logger.error("Immediate export failed: \(error)")
            throw error
        }
    }
}
