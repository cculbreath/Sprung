import Foundation
import AppKit
import Mustache

@MainActor
@Observable
class NativePDFGenerator {
    private let templateStore: TemplateStore
    private let profileProvider: ApplicantProfileProviding

    init(templateStore: TemplateStore, profileProvider: ApplicantProfileProviding) {
        self.templateStore = templateStore
        self.profileProvider = profileProvider
    }

    /// Check if Chrome/Chromium is available (bundled first, then system)
    private func findChrome() -> String? {
        // First check for bundled Chromium in app Resources
        if let bundledURL = Bundle.main.url(forResource: "Chromium", withExtension: "app", subdirectory: nil) {
            let chromiumPath = bundledURL.appendingPathComponent("Contents/MacOS/Chromium").path
            if FileManager.default.isExecutableFile(atPath: chromiumPath) {
                Logger.debug("NativePDFGenerator: Using bundled Chromium")
                return chromiumPath
            }
        }
        // Also check Resources/chromium-headless-shell for minimal headless build
        if let shellURL = Bundle.main.url(forResource: "chrome-headless-shell", withExtension: nil, subdirectory: "chromium-headless-shell") {
            if FileManager.default.isExecutableFile(atPath: shellURL.path) {
                Logger.debug("NativePDFGenerator: Using bundled chrome-headless-shell")
                return shellURL.path
            }
        }

        // Use NSWorkspace to find system-installed Chrome/Chromium apps
        let bundleIdentifiers = [
            "com.google.Chrome",
            "org.chromium.Chromium",
            "com.google.Chrome.canary"
        ]

        for identifier in bundleIdentifiers {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                // Extract executable path from app bundle
                let executableName = appURL.deletingPathExtension().lastPathComponent
                let chromePath = appURL.appendingPathComponent("Contents/MacOS/\(executableName)").path
                if FileManager.default.isExecutableFile(atPath: chromePath) {
                    Logger.debug("NativePDFGenerator: Using system Chrome at \(chromePath) (bundle: \(identifier))")
                    return chromePath
                }
            }
        }

        // Fallback: check common binary paths (Homebrew, etc.)
        let binaryPaths = [
            "/opt/homebrew/bin/chromium",
            "/usr/local/bin/chromium",
            "/opt/homebrew/bin/chrome",
            "/usr/local/bin/chrome"
        ]
        for path in binaryPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                Logger.debug("NativePDFGenerator: Using Chrome binary at \(path)")
                return path
            }
        }

        return nil
    }

    /// Rewrite any paged.polyfill.js reference to a local file:// URL and copy the bundled script into tempDir.
    private func rewriteHTMLForLocalPagedJS(_ html: String, tempDir: URL) -> String {
        // Match src with paged.polyfill.js (relative or CDN)
        let pattern = #"<script[^>]*src=['\"]([^\"']*paged\.polyfill\.js)[\"'][^>]*>\s*</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return html
        }
        let nsrange = NSRange(location: 0, length: (html as NSString).length)
        guard regex.firstMatch(in: html, options: [], range: nsrange) != nil else {
            return html
        }

        // Try to find paged.polyfill.js from bundle
        var sourceURL: URL?
        Logger.info("NativePDFGenerator: Searching for paged.polyfill.js...")
        Logger.info("NativePDFGenerator: Bundle.main.resourceURL = \(Bundle.main.resourceURL?.path ?? "nil")")

        if let bundledURL = Bundle.main.url(forResource: "paged.polyfill", withExtension: "js") {
            sourceURL = bundledURL
            Logger.info("NativePDFGenerator: Found paged.polyfill.js via Bundle.main.url at \(bundledURL.path)")
        } else if let bundledURL = Bundle.main.url(forResource: "paged.polyfill", withExtension: "js", subdirectory: "Resources") {
            sourceURL = bundledURL
            Logger.info("NativePDFGenerator: Found paged.polyfill.js in Resources subdirectory at \(bundledURL.path)")
        } else if let resourcesURL = Bundle.main.resourceURL {
            // Search for the file in the bundle
            let possiblePaths = [
                resourcesURL.appendingPathComponent("paged.polyfill.js"),
                resourcesURL.appendingPathComponent("Resources/paged.polyfill.js")
            ]
            for path in possiblePaths {
                Logger.info("NativePDFGenerator: Checking path: \(path.path)")
                if FileManager.default.fileExists(atPath: path.path) {
                    sourceURL = path
                    Logger.info("NativePDFGenerator: Found paged.polyfill.js at \(path.path)")
                    break
                }
            }
        }

        guard let pagedJSURL = sourceURL else {
            Logger.error("NativePDFGenerator: paged.polyfill.js not found in bundle; PDF may render incorrectly")
            return html
        }

        // Copy to tempDir so relative paths work
        let destination = tempDir.appendingPathComponent("paged.polyfill.js")
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: pagedJSURL, to: destination)
        } catch {
            Logger.warning("NativePDFGenerator: Failed to copy paged.polyfill.js: \(error)")
            return html
        }

        let fileURLString = "file://\(destination.path)"
        let rewritten = regex.stringByReplacingMatches(
            in: html,
            options: [],
            range: nsrange,
            withTemplate: "<script src=\"\(fileURLString)\"></script>"
        )
        Logger.info("NativePDFGenerator: Rewrote paged.polyfill.js to local file URL")
        return rewritten
    }

    /// Generate PDF using headless Chrome for proper CSS/font support
    private func generatePDFWithChrome(html: String) async throws -> Data {
        guard let chromePath = findChrome() else {
            Logger.error("NativePDFGenerator: Chrome not found")
            throw PDFGeneratorError.chromeNotFound
        }

        // Create temp files for input HTML and output PDF
        let tempDir = FileManager.default.temporaryDirectory
        let htmlFile = tempDir.appendingPathComponent(UUID().uuidString + ".html")
        let pdfFile = tempDir.appendingPathComponent(UUID().uuidString + ".pdf")

        defer {
            try? FileManager.default.removeItem(at: htmlFile)
            try? FileManager.default.removeItem(at: pdfFile)
        }

        // Inline external fonts (Google Fonts, etc.) for offline rendering
        let htmlWithInlinedFonts = await inlineExternalFonts(in: html)

        // Rewrite Paged.js references to bundled copy (for offline/headless rendering)
        let htmlWithLocalPaged = rewriteHTMLForLocalPagedJS(htmlWithInlinedFonts, tempDir: tempDir)
        try htmlWithLocalPaged.write(to: htmlFile, atomically: true, encoding: .utf8)

        // Run headless Chrome
        let process = Process()
        process.executableURL = URL(fileURLWithPath: chromePath)

        // Set library path for bundled chrome-headless-shell
        let chromeDir = URL(fileURLWithPath: chromePath).deletingLastPathComponent()
        let libDir = chromeDir.appendingPathComponent("lib").path
        var environment = ProcessInfo.processInfo.environment
        environment["DYLD_LIBRARY_PATH"] = libDir
        process.environment = environment
        process.currentDirectoryURL = chromeDir  // Run from chrome's directory

        process.arguments = [
            "--headless=new",
            "--disable-gpu",
            "--no-sandbox",
            "--disable-software-rasterizer",
            "--run-all-compositor-stages-before-draw",
            "--print-to-pdf=\(pdfFile.path)",
            "--no-pdf-header-footer",
            "--print-to-pdf-no-header",
            // Wait for Paged.js to complete DOM transformation
            "--virtual-time-budget=10000",
            "file://\(htmlFile.path)"
        ]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        Logger.info("NativePDFGenerator: Running headless Chrome...")

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { _ in
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? ""

                // Log stderr (Chrome outputs info there)
                if !errorMessage.isEmpty {
                    Logger.debug("NativePDFGenerator: Chrome stderr: \(errorMessage)")
                }

                if process.terminationStatus == 0 {
                    do {
                        let pdfData = try Data(contentsOf: pdfFile)
                        Logger.info("NativePDFGenerator: Chrome generated PDF (\(pdfData.count) bytes)")
                        continuation.resume(returning: pdfData)
                    } catch {
                        Logger.error("NativePDFGenerator: Failed to read PDF output: \(error)")
                        continuation.resume(throwing: PDFGeneratorError.pdfGenerationFailed)
                    }
                } else {
                    Logger.error("NativePDFGenerator: Chrome failed (exit \(process.terminationStatus)): \(errorMessage)")
                    continuation.resume(throwing: PDFGeneratorError.pdfGenerationFailed)
                }
            }

            do {
                try process.run()
            } catch {
                Logger.error("NativePDFGenerator: Failed to launch Chrome: \(error)")
                continuation.resume(throwing: PDFGeneratorError.pdfGenerationFailed)
            }
        }
    }
    func generatePDF(for resume: Resume, template: String, format: String = "html") async throws -> Data {
        let htmlContent = try await MainActor.run {
            try renderTemplate(for: resume, template: template, format: format)
        }
        return try await generatePDFWithChrome(html: htmlContent)
    }
    // MARK: - Custom Template Rendering
    @MainActor
    func generatePDFFromCustomTemplate(
        for resume: Resume,
        customHTML: String,
        processedContext overrideContext: [String: Any]? = nil
    ) async throws -> Data {
        let context = try overrideContext ?? renderingContext(for: resume)
        let fontsFixed = HTMLUtility.fixFontReferences(customHTML)
        let translation = HandlebarsTranslator.translate(fontsFixed)
        logTranslationWarnings(translation.warnings, slug: resume.template?.slug ?? "custom")
        let finalContent = preprocessTemplateForGRMustache(translation.template)
        let mustacheTemplate = try Mustache.Template(string: finalContent)
        TemplateFilters.register(on: mustacheTemplate)
        let htmlContent = try mustacheTemplate.render(context)

        // Save debug HTML if enabled
        if let templateSlug = resume.template?.slug ?? resume.template?.name {
            saveDebugHTML(htmlContent, template: templateSlug, format: "html")
        } else {
            saveDebugHTML(htmlContent, template: "custom-preview", format: "html")
        }

        return try await generatePDFWithChrome(html: htmlContent)
    }
    @MainActor
    func renderingContext(for resume: Resume) throws -> [String: Any] {
        let profile = profileProvider.currentProfile()
        let context = try ResumeContextBuilder.buildContext(for: resume, profile: profile)
#if DEBUG
        Logger.debug("NativePDFGenerator: context keys => \(context.keys.sorted())")
#endif
        return context
    }
    /// Legacy helper retained for text exports. Text generation duties moved to
    /// `TextResumeGenerator`, but PDF rendering still relies on this pipeline.
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
        guard let content = templateContent else {
            throw PDFGeneratorError.templateNotFound("\(resourceName).\(format)")
        }
        // Build unified context using ResumeContextBuilder
        let profile = profileProvider.currentProfile()
        let context = try ResumeContextBuilder.buildContext(for: resume, profile: profile)
        // Fix font URLs for macOS system fonts and preprocess helpers
        let fontsFixed = HTMLUtility.fixFontReferences(content)
        let translation = HandlebarsTranslator.translate(fontsFixed)
        logTranslationWarnings(translation.warnings, slug: template)
        var finalContent = preprocessTemplateForGRMustache(translation.template)
        if format == "html", let css = templateStore.cssTemplateContent(slug: normalizedTemplate), !css.isEmpty {
            finalContent = "<style>\n\(css)\n</style>\n" + finalContent
        }
        // Use GRMustache to render the template
        let mustacheTemplate = try Mustache.Template(string: finalContent)
        TemplateFilters.register(on: mustacheTemplate)
        let renderedContent = try mustacheTemplate.render(context)
        // For HTML format, save debug output
        if format == "html" {
            saveDebugHTML(renderedContent, template: template, format: format)
        }
        return renderedContent
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
    private func logTranslationWarnings(_ warnings: [String], slug: String) {
        guard warnings.isEmpty == false else { return }
        for warning in warnings {
            Logger.warning("Handlebars compatibility (\(slug)): \(warning)")
        }
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
}
enum PDFGeneratorError: Error, LocalizedError {
    case templateNotFound(String)
    case chromeNotFound
    case pdfGenerationFailed
    case invalidResumeData

    var errorDescription: String? {
        switch self {
        case .templateNotFound(let template):
            return "Template '\(template)' not found in bundle"
        case .chromeNotFound:
            return "Chrome or Chromium not found for PDF generation"
        case .pdfGenerationFailed:
            return "Failed to generate PDF"
        case .invalidResumeData:
            return "Invalid resume data format"
        }
    }
}
