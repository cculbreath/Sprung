import Foundation

@MainActor
final class OnboardingUploadRegistry {
    private var uploadsById: [String: OnboardingUploadedItem] = [:]

    var items: [OnboardingUploadedItem] {
        uploadsById
            .values
            .sorted { $0.createdAt < $1.createdAt }
    }

    func registerResume(from fileURL: URL) throws -> OnboardingUploadedItem {
        let data = try Data(contentsOf: fileURL)
        let item = OnboardingUploadedItem(
            id: UUID().uuidString,
            name: fileURL.lastPathComponent,
            kind: .resume,
            data: data,
            url: nil,
            createdAt: Date()
        )
        return store(item)
    }

    func registerLinkedInProfile(url: URL) -> OnboardingUploadedItem {
        let item = OnboardingUploadedItem(
            id: UUID().uuidString,
            name: url.absoluteString,
            kind: .linkedInProfile,
            data: nil,
            url: url,
            createdAt: Date()
        )
        return store(item)
    }

    func registerArtifact(data: Data, suggestedName: String, kind: OnboardingUploadedItem.Kind = .artifact) -> OnboardingUploadedItem {
        let item = OnboardingUploadedItem(
            id: UUID().uuidString,
            name: suggestedName,
            kind: kind,
            data: data,
            url: nil,
            createdAt: Date()
        )
        return store(item)
    }

    func registerWritingSample(data: Data, suggestedName: String) -> OnboardingUploadedItem {
        let item = OnboardingUploadedItem(
            id: UUID().uuidString,
            name: suggestedName,
            kind: .writingSample,
            data: data,
            url: nil,
            createdAt: Date()
        )
        return store(item)
    }

    func upload(withId id: String) -> OnboardingUploadedItem? {
        uploadsById[id]
    }

    func data(for id: String) -> Data? {
        uploadsById[id]?.data
    }

    func url(for id: String) -> URL? {
        uploadsById[id]?.url
    }

    func reset() {
        uploadsById.removeAll()
    }

    private func store(_ item: OnboardingUploadedItem) -> OnboardingUploadedItem {
        uploadsById[item.id] = item
        return item
    }
}

struct OnboardingUploadedItem: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case resume
        case linkedInProfile
        case artifact
        case writingSample
        case generic
    }

    let id: String
    let name: String
    let kind: Kind
    let data: Data?
    let url: URL?
    let createdAt: Date
}
