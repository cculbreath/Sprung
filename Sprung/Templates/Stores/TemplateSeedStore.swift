import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class TemplateSeedStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func seed(for template: Template) -> TemplateSeed? {
        if !template.seeds.isEmpty {
            return template.seeds.sorted(by: { $0.updatedAt > $1.updatedAt }).first
        }
        return seed(forSlug: template.slug)
    }

    func seed(forSlug slug: String) -> TemplateSeed? {
        let normalized = slug.lowercased()
        let descriptor = FetchDescriptor<TemplateSeed>(
            predicate: #Predicate { $0.slug == normalized },
            sortBy: [SortDescriptor(\TemplateSeed.updatedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor))?.first
    }

    @discardableResult
    func upsertSeed(
        slug: String,
        jsonString: String,
        attachTo template: Template? = nil
    ) -> TemplateSeed {
        let normalized = slug.lowercased()
        let data = jsonString.data(using: .utf8) ?? Data()
        let now = Date()

        if let existing = seed(forSlug: normalized) {
            existing.seedData = data
            existing.updatedAt = now
            if let template {
                existing.template = template
            }
            try? context.save()
            return existing
        }

        let seed = TemplateSeed(
            slug: normalized,
            seedData: data,
            createdAt: now,
            updatedAt: now,
            template: template
        )
        context.insert(seed)
        try? context.save()
        return seed
    }

    func deleteSeed(_ seed: TemplateSeed) {
        seed.template = nil
        context.delete(seed)
        try? context.save()
    }

    func deleteSeed(forSlug slug: String) {
        if let existing = seed(forSlug: slug) {
            deleteSeed(existing)
        }
    }
}
