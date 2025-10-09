import Foundation
import SwiftData

enum TemplateImporter {
    static func ensureInitialTemplates(context: ModelContext) throws {
        var descriptor = FetchDescriptor<Template>()
        descriptor.fetchLimit = 1
        let needsBootstrap = (try context.fetch(descriptor)).isEmpty

        let importer = Worker(context: context)
        if needsBootstrap {
            importer.importBundleTemplates()
            importer.importUserTemplates()
            try context.save()
        }

        try backfillManifests(context: context, using: importer)
    }

    private final class Worker {
        private let context: ModelContext
        private var importedSlugs: Set<String> = []
        let bundleTemplatesURL: URL?

        init(context: ModelContext) {
            self.context = context
            bundleTemplatesURL = Bundle.main.resourceURL?.appendingPathComponent("Templates", isDirectory: true)
        }

        func importBundleTemplates() {
            guard let templatesURL = bundleTemplatesURL else {
                return
            }
            importTemplates(at: templatesURL, isCustom: false)
        }

        func importUserTemplates() {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            let userTemplatesURL = documents?
                .appendingPathComponent("PhysCloudResume", isDirectory: true)
                .appendingPathComponent("Templates", isDirectory: true)
            if let url = userTemplatesURL {
                importTemplates(at: url, isCustom: true)
            }
        }

        private func importTemplates(at baseURL: URL, isCustom: Bool) {
            guard let contents = try? FileManager.default.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
                return
            }

            for item in contents {
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    let slug = item.lastPathComponent
                    importTemplate(slug: slug, directory: item, isCustom: isCustom)
                }
            }
        }

        private func importTemplate(slug: String, directory: URL, isCustom: Bool) {
            let normalizedSlug = slug.lowercased()
            guard importedSlugs.contains(normalizedSlug) == false else { return }

            let resourceName = "\(normalizedSlug)-template"
            let htmlURL = search(for: resourceName, withExtension: "html", in: directory)
            let textURL = search(for: resourceName, withExtension: "txt", in: directory)
            let cssURL = searchForCSS(in: directory, slug: normalizedSlug)
            let manifestURL = search(for: "\(normalizedSlug)-manifest", withExtension: "json", in: directory)

            guard htmlURL != nil || textURL != nil else {
                return
            }

            let template = Template(
                name: normalizedSlug.capitalized,
                slug: normalizedSlug,
                htmlContent: htmlURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) },
                textContent: textURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) },
                cssContent: cssURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) },
                manifestData: manifestURL.flatMap { try? Data(contentsOf: $0) },
                isCustom: isCustom
            )

            context.insert(template)
            importedSlugs.insert(normalizedSlug)
        }

        private func search(for resource: String, withExtension ext: String, in directory: URL) -> URL? {
            let direct = directory.appendingPathComponent("\(resource).\(ext)")
            if FileManager.default.fileExists(atPath: direct.path) {
                return direct
            }

            let alternative = directory.appendingPathComponent(resource.replacingOccurrences(of: "-template", with: ""))
                .appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: alternative.path) {
                return alternative
            }

            return nil
        }

        private func searchForCSS(in directory: URL, slug: String) -> URL? {
            let preferred = directory.appendingPathComponent("\(slug)-template.css")
            if FileManager.default.fileExists(atPath: preferred.path) {
                return preferred
            }

            let styleCSS = directory.appendingPathComponent("style.css")
            if FileManager.default.fileExists(atPath: styleCSS.path) {
                return styleCSS
            }

            let slugCSS = directory.appendingPathComponent("\(slug).css")
            if FileManager.default.fileExists(atPath: slugCSS.path) {
                return slugCSS
            }

            return nil
        }
    }

    private static func backfillManifests(context: ModelContext, using importer: Worker) throws {
        let templates = try context.fetch(FetchDescriptor<Template>())
        guard !templates.isEmpty else { return }

        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("PhysCloudResume", isDirectory: true)
            .appendingPathComponent("Templates", isDirectory: true)

        var didUpdate = false
        for template in templates where template.manifestData == nil {
            if let data = manifestData(for: template.slug, bundleBaseURL: importer.bundleTemplatesURL, documentsBaseURL: documents) {
                template.manifestData = data
                didUpdate = true
            } else {
                Logger.warning("TemplateImporter: No manifest found for template slug \(template.slug)")
            }
        }

        if didUpdate {
            try context.save()
        }
    }

    private static func manifestData(for slug: String, bundleBaseURL: URL?, documentsBaseURL: URL?) -> Data? {
        let normalized = slug.lowercased()
        let manifestName = "\(normalized)-manifest.json"

        if let docsURL = documentsBaseURL?.appendingPathComponent(normalized, isDirectory: true)
            .appendingPathComponent(manifestName),
           FileManager.default.fileExists(atPath: docsURL.path),
           let data = try? Data(contentsOf: docsURL) {
            return data
        }

        if let bundleURL = bundleBaseURL?
            .appendingPathComponent(normalized, isDirectory: true)
            .appendingPathComponent(manifestName),
           FileManager.default.fileExists(atPath: bundleURL.path),
           let data = try? Data(contentsOf: bundleURL) {
            return data
        }

        return nil
    }
}
