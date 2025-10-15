import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class TemplateStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
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

    func defaultTemplate() -> Template? {
        let descriptor = FetchDescriptor<Template>(
            predicate: #Predicate { $0.isDefault == true },
            sortBy: [SortDescriptor(\Template.updatedAt, order: .reverse)]
        )
        if let match = try? context.fetch(descriptor).first {
            return match
        }
        let fallbackDescriptor = FetchDescriptor<Template>(
            sortBy: [SortDescriptor(\Template.createdAt, order: .forward)]
        )
        return try? context.fetch(fallbackDescriptor).first
    }

    @discardableResult
    func upsertTemplate(
        slug: String,
        name: String,
        htmlContent: String? = nil,
        textContent: String? = nil,
        cssContent: String? = nil,
        isCustom: Bool,
        markAsDefault: Bool = false
    ) -> Template {
        let normalized = slug.lowercased()
        let now = Date()
        if let existing = template(slug: normalized) {
            existing.name = name  // Fix: Update the name field
            if let htmlContent { existing.htmlContent = htmlContent }
            if let textContent { existing.textContent = textContent }
            if let cssContent { existing.cssContent = cssContent }
            existing.updatedAt = now
            existing.isCustom = isCustom
            if markAsDefault {
                setDefault(existing)
            }
            try? context.save()
            return existing
        } else {
            let hadTemplates = !templates().isEmpty
            let template = Template(
                name: name,
                slug: normalized,
                htmlContent: htmlContent,
                textContent: textContent,
                cssContent: cssContent,
                isCustom: isCustom,
                isDefault: false,
                createdAt: now,
                updatedAt: now
            )
            context.insert(template)
            if markAsDefault || !hadTemplates {
                setDefault(template)
            }
            try? context.save()
            return template
        }
    }

    func setDefault(_ template: Template) {
        guard template.isDefault == false else { return }
        let descriptor = FetchDescriptor<Template>(predicate: #Predicate { $0.isDefault == true })
        if let currentDefaults = try? context.fetch(descriptor) {
            currentDefaults.forEach { $0.isDefault = false }
        }
        template.isDefault = true
        template.updatedAt = Date()
        try? context.save()
    }

    func updateManifest(slug: String, manifestData: Data?) throws {
        guard let template = template(slug: slug) else {
            throw TemplateStoreError.templateNotFound(slug)
        }
        template.manifestData = manifestData
        template.updatedAt = Date()
        try context.save()
    }

    func saveContext() {
        try? context.save()
    }

    func deleteTemplate(slug: String) {
        guard let template = template(slug: slug) else { return }
        let wasDefault = template.isDefault
        context.delete(template)
        try? context.save()
        if wasDefault {
            if let fallback = defaultTemplate() {
                setDefault(fallback)
            }
        }
    }
}

enum TemplateStoreError: Error {
    case templateNotFound(String)
}
