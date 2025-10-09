import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class TemplateStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        do {
            try TemplateImporter.ensureInitialTemplates(context: context)
        } catch {
            Logger.warning("⚠️ Failed to initialize template library: \(error)")
        }
    }

    func templates() -> [Template] {
        let descriptor = FetchDescriptor<Template>(sortBy: [SortDescriptor(\Template.name, order: .forward)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func template(slug: String) -> Template? {
        let normalized = slug.lowercased()
        let descriptor = FetchDescriptor<Template>(predicate: #Predicate { $0.slug == normalized })
        return try? context.fetch(descriptor).first
    }

    func htmlTemplateContent(slug: String) -> String? {
        template(slug: slug)?.htmlContent
    }

    func textTemplateContent(slug: String) -> String? {
        template(slug: slug)?.textContent
    }

    func cssTemplateContent(slug: String) -> String? {
        template(slug: slug)?.cssContent
    }

    func upsertTemplate(
        slug: String,
        name: String,
        htmlContent: String? = nil,
        textContent: String? = nil,
        isCustom: Bool
    ) {
        let normalized = slug.lowercased()
        let now = Date()
        if let existing = template(slug: normalized) {
            if let htmlContent { existing.htmlContent = htmlContent }
            if let textContent { existing.textContent = textContent }
            existing.updatedAt = now
            existing.isCustom = isCustom
        } else {
            let template = Template(
                name: name,
                slug: normalized,
                htmlContent: htmlContent,
                textContent: textContent,
                isCustom: isCustom,
                createdAt: now,
                updatedAt: now
            )
            context.insert(template)
        }
        try? context.save()
    }
}
