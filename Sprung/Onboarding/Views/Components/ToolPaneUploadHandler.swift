import AppKit
import UniformTypeIdentifiers

struct ToolPaneUploadHandler {

    static func uploadRequests(
        for step: OnboardingWizardStep,
        pending: [OnboardingUploadRequest]
    ) -> [OnboardingUploadRequest] {
        var filtered: [OnboardingUploadRequest]
        switch step {
        case .voice:
            // Phase 1: Resume, LinkedIn, profile photo ONLY
            // IMPORTANT: Do NOT include writing samples here - the sidebar has a dedicated Phase1WritingSampleView
            filtered = pending.filter {
                [.resume, .linkedIn].contains($0.kind) ||
                    ($0.kind == .generic && $0.metadata.targetKey == "basics.image")
            }
            // For voice phase, also add any generic requests that aren't writing samples
            // but EXCLUDE writing samples since Phase1WritingSampleView handles those
            for request in pending
            where !filtered.contains(where: { $0.id == request.id })
                && request.kind != .writingSample {
                filtered.append(request)
            }
        case .story:
            // Phase 2: Additional artifacts
            filtered = pending.filter { [.artifact, .generic].contains($0.kind) }
            // Include other non-writing sample requests not captured by filtering
            for request in pending
            where !filtered.contains(where: { $0.id == request.id })
                && request.kind != .writingSample {
                filtered.append(request)
            }
        case .evidence:
            // Phase 3: Evidence documents (artifacts, generic uploads, resumes)
            // Excludes writing samples since those are Phase 1 only
            filtered = pending.filter { $0.kind != .writingSample }
        case .strategy:
            // Phase 4: All remaining uploads
            filtered = pending
        }
        if !filtered.isEmpty {
            let kinds = filtered.map { $0.kind.rawValue }.joined(separator: ",")
            Logger.debug("\u{1f4e4} Pending upload requests surfaced in tool pane (step: \(step.rawValue), kinds: \(kinds))", category: .ai)
        }
        return filtered
    }

    static func openWritingSamplePanel(
        onComplete: @escaping ([URL]) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType.pdf,
            UTType(filenameExtension: "docx"),
            UTType.plainText,
            UTType(filenameExtension: "md")
        ].compactMap { $0 }
        panel.begin { result in
            guard result == .OK, !panel.urls.isEmpty else { return }
            onComplete(panel.urls)
        }
    }

    static func openDirectUploadPanel(
        onComplete: @escaping ([URL]) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType.pdf,
            UTType(filenameExtension: "docx"),
            UTType.plainText,
            UTType.png,
            UTType.jpeg,
            UTType(filenameExtension: "md"),
            UTType.json
        ].compactMap { $0 }
        panel.begin { result in
            guard result == .OK, !panel.urls.isEmpty else { return }
            onComplete(panel.urls)
        }
    }

    static func openPanel(
        for request: OnboardingUploadRequest,
        onComplete: @escaping ([URL]) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = request.metadata.allowMultiple
        panel.canChooseDirectories = false
        if let allowed = allowedContentTypes(for: request) {
            panel.allowedContentTypes = allowed
        }
        panel.begin { result in
            guard result == .OK else { return }
            let urls: [URL]
            if request.metadata.allowMultiple {
                urls = panel.urls
            } else {
                urls = Array(panel.urls.prefix(1))
            }
            onComplete(urls)
        }
    }

    static func allowedContentTypes(
        for request: OnboardingUploadRequest
    ) -> [UTType]? {
        var candidates = request.metadata.accepts.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        if candidates.isEmpty {
            switch request.kind {
            case .resume, .coverletter:
                candidates = ["pdf", "docx", "txt", "json"]
            case .artifact, .portfolio, .generic:
                candidates = ["pdf", "docx", "txt", "json"]
            case .writingSample:
                candidates = ["pdf", "docx", "txt", "md"]
            case .transcript, .certificate:
                candidates = ["pdf", "png", "jpg"]
            case .linkedIn:
                return nil
            }
        }
        let mapped = candidates.compactMap { UTType(filenameExtension: $0) }
        return mapped.isEmpty ? nil : mapped
    }
}
