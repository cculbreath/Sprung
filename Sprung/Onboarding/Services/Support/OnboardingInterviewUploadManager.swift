import Foundation

@MainActor
final class OnboardingInterviewUploadManager {
    private let uploadRegistry: OnboardingUploadRegistry
    private let onItemsUpdated: ([OnboardingUploadedItem]) -> Void
    private let onMessage: (String) -> Void

    init(
        uploadRegistry: OnboardingUploadRegistry,
        onItemsUpdated: @escaping ([OnboardingUploadedItem]) -> Void,
        onMessage: @escaping (String) -> Void
    ) {
        self.uploadRegistry = uploadRegistry
        self.onItemsUpdated = onItemsUpdated
        self.onMessage = onMessage
        publish()
    }

    func reset() {
        uploadRegistry.reset()
        publish()
    }

    @discardableResult
    func registerResume(from fileURL: URL) throws -> OnboardingUploadedItem {
        let item = try uploadRegistry.registerResume(from: fileURL)
        publish()
        onMessage("Uploaded resume ‘\(item.name)’. Tool: parse_resume with fileId \(item.id)")
        return item
    }

    @discardableResult
    func registerLinkedInProfile(url: URL) -> OnboardingUploadedItem {
        let item = uploadRegistry.registerLinkedInProfile(url: url)
        publish()
        onMessage("LinkedIn URL registered. Tool: parse_linkedin with url \(url.absoluteString)")
        return item
    }

    @discardableResult
    func registerArtifact(data: Data, suggestedName: String, kind: OnboardingUploadedItem.Kind) -> OnboardingUploadedItem {
        let item = uploadRegistry.registerArtifact(data: data, suggestedName: suggestedName, kind: kind)
        publish()
        onMessage("Artifact ‘\(item.name)’ available. Tool: summarize_artifact with fileId \(item.id)")
        return item
    }

    @discardableResult
    func registerWritingSample(data: Data, suggestedName: String) -> OnboardingUploadedItem {
        let item = uploadRegistry.registerWritingSample(data: data, suggestedName: suggestedName)
        publish()
        onMessage("Writing sample ‘\(item.name)’ ready. Tool: summarize_writing or persist_style_profile will reference fileId \(item.id)")
        return item
    }

    var items: [OnboardingUploadedItem] {
        uploadRegistry.items
    }

    var registry: OnboardingUploadRegistry {
        uploadRegistry
    }

    private func publish() {
        onItemsUpdated(uploadRegistry.items)
    }
}
