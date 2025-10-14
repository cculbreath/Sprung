import Foundation
import WebKit
import Mustache

@MainActor
class NativePDFGenerator: NSObject, ObservableObject {
    private let templateStore: TemplateStore
    private let profileProvider: ApplicantProfileProviding
    private var webView: WKWebView?
    private var currentCompletion: ((Result<Data, Error>) -> Void)?
    
    init(templateStore: TemplateStore, profileProvider: ApplicantProfileProviding) {
        self.templateStore = templateStore
        self.profileProvider = profileProvider
        super.init()
        setupWebView()
    }
    
    private func setupWebView() {
        let configuration = WKWebViewConfiguration()

        // Full letter size - margins will be handled in CSS
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        webView = WKWebView(frame: pageRect, configuration: configuration)

        webView?.navigationDelegate = self
    }
    
    func generatePDF(for resume: Resume, template: String, format: String = "html") async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                do {
                    let htmlContent = try renderTemplate(for: resume, template: template, format: format)
                    
                    currentCompletion = { result in
                        continuation.resume(with: result)
                    }
                    
                    webView?.loadHTMLString(htmlContent, baseURL: nil)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    @MainActor
    // Text generation has been moved to TextResumeGenerator
    
    func generatePDFFromCustomTemplate(
        for resume: Resume,
        customHTML: String,
        processedContext overrideContext: [String: Any]? = nil
    ) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                do {
                    let context = try overrideContext ?? renderingContext(for: resume)
                    let finalContent = preprocessTemplateForGRMustache(fixFontReferences(customHTML))
                    let mustacheTemplate = try Mustache.Template(string: finalContent)
                    TemplateFilters.register(on: mustacheTemplate)
                    let htmlContent = try mustacheTemplate.render(context)

                    // Mirror standard export path: persist debug HTML when enabled so preview output is inspectable.
                    if let templateSlug = resume.template?.slug ?? resume.template?.name {
                        saveDebugHTML(htmlContent, template: templateSlug, format: "html")
                    } else {
                        saveDebugHTML(htmlContent, template: "custom-preview", format: "html")
                    }

                    currentCompletion = { result in
                        continuation.resume(with: result)
                    }

                    webView?.loadHTMLString(htmlContent, baseURL: nil)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    @MainActor
    func renderingContext(for resume: Resume) throws -> [String: Any] {
        let rawContext = try createTemplateContext(from: resume)
        let processed = preprocessContextForTemplate(rawContext, from: resume)
#if DEBUG
        Logger.debug("NativePDFGenerator: context keys => \(processed.keys.sorted())")
#endif
        return processed
    }
    
    // Custom text template generation has been moved to TextResumeGenerator
    
    @MainActor
    private func renderTemplate(for resume: Resume, template: String, format: String) throws -> String {
        let normalizedTemplate = template.lowercased()
        let resourceName = "\(normalizedTemplate)-template"

        var templateContent: String?

        if format == "html", let stored = templateStore.htmlTemplateContent(slug: normalizedTemplate) {
            templateContent = stored
        } else if format == "txt", let stored = templateStore.textTemplateContent(slug: normalizedTemplate) {
            templateContent = stored
        }

        if templateContent == nil,
           let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let userTemplatePath = documentsPath
                .appendingPathComponent("Sprung")
                .appendingPathComponent("Templates")
                .appendingPathComponent(template)
                .appendingPathComponent("\(resourceName).\(format)")
            if let content = try? String(contentsOf: userTemplatePath, encoding: .utf8) {
                templateContent = content
                Logger.debug("Using user-modified template from: \(userTemplatePath.path)")
            }
        }

        guard let content = templateContent else {
            throw PDFGeneratorError.templateNotFound("\(resourceName).\(format)")
        }
        
        // Convert Resume to template context
        let rawContext = try createTemplateContext(from: resume)
        let processedContext = preprocessContextForTemplate(rawContext, from: resume)
        
        // Fix font URLs for macOS system fonts and preprocess helpers
        var finalContent = preprocessTemplateForGRMustache(fixFontReferences(content))
        if format == "html", let css = templateStore.cssTemplateContent(slug: normalizedTemplate), !css.isEmpty {
            finalContent = "<style>\n\(css)\n</style>\n" + finalContent
        }
        
        // Use GRMustache to render the template
        let mustacheTemplate = try Mustache.Template(string: finalContent)
        TemplateFilters.register(on: mustacheTemplate)
        let renderedContent = try mustacheTemplate.render(processedContext)
        
        // For HTML format, save debug output
        if format == "html" {
            saveDebugHTML(renderedContent, template: template, format: format)
        }
        
        return renderedContent
    }
    
    @MainActor
    private func createTemplateContext(from resume: Resume) throws -> [String: Any] {
        try ResumeTemplateDataBuilder.buildContext(from: resume)
    }

    private func preprocessContextForTemplate(_ context: [String: Any], from resume: Resume) -> [String: Any] {
        // Merge ApplicantProfile data back into context
        guard let template = resume.template,
              let manifest = TemplateManifestLoader.manifest(for: template) else {
            return context
        }

        let profile = profileProvider.currentProfile()
        let profileContext = buildApplicantProfileContext(
            profile: profile,
            manifest: manifest
        )

        // Merge profile context into the template context
        var merged = context
        for (key, value) in profileContext {
            if var existingDict = merged[key] as? [String: Any],
               let newDict = value as? [String: Any] {
                // Merge dictionaries
                for (subKey, subValue) in newDict {
                    existingDict[subKey] = subValue
                }
                merged[key] = existingDict
            } else {
                merged[key] = value
            }
        }

        return merged
    }

    private func buildApplicantProfileContext(
        profile: ApplicantProfile,
        manifest: TemplateManifest
    ) -> [String: Any] {
        var payload: [String: Any] = [:]
        let bindings = manifest.applicantProfileBindings()

        for binding in bindings {
            guard let value = applicantProfileValue(for: binding.binding.path, profile: profile),
                  !isEmptyValue(value) else { continue }

            let updatedSection = setProfileValue(
                value,
                for: binding.path,
                existing: payload[binding.section]
            )
            payload[binding.section] = updatedSection
        }

        return payload
    }

    private func applicantProfileValue(for path: [String], profile: ApplicantProfile) -> Any? {
        guard let first = path.first else { return nil }
        switch first {
        case "name":
            return profile.name.isEmpty ? nil : profile.name
        case "email":
            return profile.email.isEmpty ? nil : profile.email
        case "phone":
            return profile.phone.isEmpty ? nil : profile.phone
        case "url", "website":
            return profile.websites.isEmpty ? nil : profile.websites
        case "address":
            return profile.address.isEmpty ? nil : profile.address
        case "city":
            return profile.city.isEmpty ? nil : profile.city
        case "region", "state":
            return profile.state.isEmpty ? nil : profile.state
        case "postalCode", "zip", "code":
            return profile.zip.isEmpty ? nil : profile.zip
        case "countryCode":
            return profile.countryCode.isEmpty ? nil : profile.countryCode
        case "location":
            let remainder = Array(path.dropFirst())
            return remainder.isEmpty ? nil : applicantProfileValue(for: remainder, profile: profile)
        default:
            return nil
        }
    }

    private func isEmptyValue(_ value: Any) -> Bool {
        if let string = value as? String {
            return string.isEmpty
        }
        if let dict = value as? [String: Any] {
            return dict.isEmpty
        }
        return false
    }

    private func setProfileValue(
        _ value: Any,
        for path: [String],
        existing: Any?
    ) -> Any {
        guard let first = path.first else { return value }
        var dictionary = dictionaryValue(from: existing) ?? [:]
        let remainder = Array(path.dropFirst())
        if remainder.isEmpty {
            dictionary[first] = value
        } else {
            let current = dictionary[first]
            dictionary[first] = setProfileValue(value, for: remainder, existing: current)
        }
        return dictionary
    }

    private func dictionaryValue(from value: Any?) -> [String: Any]? {
        guard let value else { return nil }
        if let dict = value as? [String: Any] {
            return dict
        }
        return nil
    }

    private func preprocessTemplateForGRMustache(_ template: String) -> String {
        var processed = template
        
        // Convert simple cases that don't need complex helpers
        processed = processed.replacingOccurrences(of: "{{^@last}}&nbsp;&middot;&nbsp;{{/@last}}", with: "")
        
        // For now, remove complex helper calls and use simpler alternatives
        processed = processed.replacingOccurrences(of: "{{yearOnly this.start}}", with: "{{this.start}}")
        processed = processed.replacingOccurrences(of: "{{yearOnly end}}", with: "{{this.end}}")
        
        return processed
    }
    
    private func fixFontReferences(_ template: String) -> String {
        var fixedTemplate = template
        
        // Remove file:// URLs for fonts since we're using system-installed fonts
        // This regex matches font-face src declarations with local file URLs
        fixedTemplate = fixedTemplate.replacingOccurrences(
            of: #"src: url\("file://[^"]+"\) format\("[^"]+"\);"#,
            with: "/* Font file removed - using system fonts */",
            options: .regularExpression
        )
        
        // Also remove any remaining font-face declarations that reference files
        fixedTemplate = fixedTemplate.replacingOccurrences(
            of: #"@font-face \{[^}]*url\("file://[^}]*\}"#,
            with: "/* Font-face removed - using system fonts */",
            options: .regularExpression
        )
        
        return fixedTemplate
    }
    
    private func saveDebugHTML(_ html: String, template: String, format: String) {
        // Check if debug file saving is enabled in user settings
        let saveDebugFiles = UserDefaults.standard.bool(forKey: "saveDebugPrompts")
        guard saveDebugFiles else {
            Logger.debug("Debug file saving disabled - skipping HTML export")
            return
        }
        
        let timestamp = Date().timeIntervalSince1970
        let filename = "debug_resume_\(template)_\(format)_\(timestamp).html"
        
        if let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            let fileURL = downloadsURL.appendingPathComponent(filename)
            do {
                try html.write(to: fileURL, atomically: true, encoding: .utf8)
                Logger.debug("Saved debug HTML to: \(fileURL.path)")
            } catch {
                Logger.debug("Failed to save debug HTML: \(error)")
            }
        }
    }
    
    private func generatePDFFromWebView() async throws -> Data {
        guard let webView = webView else {
            throw PDFGeneratorError.webViewNotInitialized
        }
        
        // Use the modern WKWebView PDF generation API
        let configuration = WKPDFConfiguration()
        // Set to full letter size - margins will be handled by CSS @page rule
        configuration.rect = CGRect(x: 0, y: 0, width: 612, height: 792) // Letter size in points
        
        do {
            let pdfData = try await webView.pdf(configuration: configuration)
            return pdfData
        } catch {
            throw PDFGeneratorError.pdfGenerationFailed
        }
    }
}

extension NativePDFGenerator: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Wait a bit for any dynamic content to load
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            Task { @MainActor in
                guard let strongSelf = self else { return }
                do {
                    let pdfData = try await strongSelf.generatePDFFromWebView()
                    strongSelf.currentCompletion?(.success(pdfData))
                } catch {
                    strongSelf.currentCompletion?(.failure(error))
                }
                strongSelf.currentCompletion = nil
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        currentCompletion?(.failure(error))
        currentCompletion = nil
    }
}

enum PDFGeneratorError: Error, LocalizedError {
    case templateNotFound(String)
    case webViewNotInitialized
    case pdfGenerationFailed
    case invalidResumeData
    
    var errorDescription: String? {
        switch self {
        case .templateNotFound(let template):
            return "Template '\(template)' not found in bundle"
        case .webViewNotInitialized:
            return "WebView not properly initialized"
        case .pdfGenerationFailed:
            return "Failed to generate PDF from WebView"
        case .invalidResumeData:
            return "Invalid resume data format"
        }
    }
}
