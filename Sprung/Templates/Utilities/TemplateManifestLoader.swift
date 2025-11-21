import Foundation
enum TemplateManifestLoader {
    static func manifest(for template: Template) -> TemplateManifest? {
        TemplateManifestDefaults.manifest(for: template)
    }
}
