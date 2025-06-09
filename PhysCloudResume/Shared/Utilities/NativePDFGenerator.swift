import Foundation
import WebKit
import Mustache

@MainActor
class NativePDFGenerator: NSObject, ObservableObject {
    private var webView: WKWebView?
    private var currentCompletion: ((Result<Data, Error>) -> Void)?
    
    override init() {
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
    
    func generatePDF(for resume: Resume, template: String = "archer", format: String = "html") async throws -> Data {
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
    func generateTextResume(for resume: Resume, template: String = "archer") throws -> String {
        return try renderTemplate(for: resume, template: template, format: "txt")
    }
    
    func generatePDFFromCustomTemplate(for resume: Resume, customHTML: String) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                do {
                    let context = try createTemplateContext(from: resume)
                    let mustacheTemplate = try Template(string: customHTML)
                    let htmlContent = try mustacheTemplate.render(context)
                    
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
    func generateTextFromCustomTemplate(for resume: Resume, customText: String) throws -> String {
        let context = try createTemplateContext(from: resume)
        let mustacheTemplate = try Template(string: customText)
        return try mustacheTemplate.render(context)
    }
    
    @MainActor
    private func renderTemplate(for resume: Resume, template: String, format: String) throws -> String {
        // Load template from bundle with template-specific naming (case-insensitive)
        let resourceName = "\(template.lowercased())-template"
        
        // Try multiple path strategies to find the template
        var templatePath: String?
        var templateContent: String?
        
        // Strategy 0: Check Documents directory first for user modifications
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let userTemplatePath = documentsPath
            .appendingPathComponent("PhysCloudResume")
            .appendingPathComponent("Templates")
            .appendingPathComponent(template)
            .appendingPathComponent("\(resourceName).\(format)")
        
        if let content = try? String(contentsOf: userTemplatePath, encoding: .utf8) {
            templateContent = content
            templatePath = userTemplatePath.path
            Logger.debug("Using user-modified template from: \(userTemplatePath.path)")
        }
        
        // Strategy 1: Look in Templates/template subdirectory
        if templateContent == nil {
            templatePath = Bundle.main.path(forResource: resourceName, ofType: format, inDirectory: "Templates/\(template)")
            if let path = templatePath {
                templateContent = try? String(contentsOfFile: path, encoding: .utf8)
            }
        }
        
        // Strategy 2: Look directly in main bundle
        if templateContent == nil {
            templatePath = Bundle.main.path(forResource: resourceName, ofType: format)
            if let path = templatePath {
                templateContent = try? String(contentsOfFile: path, encoding: .utf8)
            }
        }
        
        // Strategy 3: Look for the template file anywhere in the bundle
        if templateContent == nil {
            let bundlePath = Bundle.main.bundlePath
            let fileManager = FileManager.default
            let enumerator = fileManager.enumerator(atPath: bundlePath)
            while let file = enumerator?.nextObject() as? String {
                if file.hasSuffix("\(resourceName).\(format)") {
                    let fullPath = bundlePath + "/" + file
                    templateContent = try? String(contentsOfFile: fullPath, encoding: .utf8)
                    if templateContent != nil {
                        templatePath = fullPath
                        break
                    }
                }
            }
        }
        
        // Fallback to embedded templates
        if templateContent == nil {
            templateContent = BundledTemplates.getTemplate(name: template, format: format)
            if templateContent != nil {
                Logger.debug("Using embedded template for \(template).\(format)")
            }
        }
        
        guard let content = templateContent else {
            // Debug: List available resources
            Logger.debug("Template not found: \(resourceName).\(format)")
            Logger.debug("Bundle path: \(Bundle.main.bundlePath)")
            if let resourcePath = Bundle.main.resourcePath {
                Logger.debug("Resource path: \(resourcePath)")
                let fileManager = FileManager.default
                if let files = try? fileManager.contentsOfDirectory(atPath: resourcePath) {
                    Logger.debug("Available resources: \(files.prefix(10))")
                }
            }
            throw PDFGeneratorError.templateNotFound("\(resourceName).\(format)")
        }
        
        // Convert Resume to template context
        let rawContext = try createTemplateContext(from: resume)
        let processedContext = preprocessContextForTemplate(rawContext, from: resume)
        
        // Fix font URLs for macOS system fonts and preprocess helpers
        let finalContent = preprocessTemplateForGRMustache(fixFontReferences(content))
        
        // Use GRMustache to render the template
        let mustacheTemplate = try Template(string: finalContent)
        let renderedContent = try mustacheTemplate.render(processedContext)
        
        // For HTML format, save debug output
        if format == "html" {
            saveDebugHTML(renderedContent, template: template, format: format)
        }
        
        return renderedContent
    }
    
    @MainActor
    private func createTemplateContext(from resume: Resume) throws -> [String: Any] {
        // Use the TreeToJson system to generate proper JSON structure
        guard let rootNode = resume.rootNode else {
            throw PDFGeneratorError.invalidResumeData
        }
        
        // Generate JSON using TreeToJson system
        guard let treeToJson = TreeToJson(rootNode: rootNode) else {
            throw PDFGeneratorError.invalidResumeData
        }
        
        let jsonString = treeToJson.buildJsonString()
        Logger.debug("Generated JSON for template: \(jsonString)")
        
        // Parse the generated JSON
        guard let jsonData = jsonString.data(using: .utf8),
              let resumeData = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
            throw PDFGeneratorError.invalidResumeData
        }
        
        // Get applicant profile for contact information
        let applicant = ApplicantProfileManager.shared.getProfile()
        
        // Create complete context with contact info + resume data
        var context = resumeData
        
        // Add contact information from applicant profile
        context["contact"] = [
            "name": applicant.name,
            "email": applicant.email,
            "phone": applicant.phone,
            "website": applicant.websites,
            "location": [
                "city": applicant.city,
                "state": applicant.state
            ]
        ]
        
        // Return context directly without 'r' wrapper for GRMustache compatibility
        return context
    }
    
    private func applyWebKitScaling(to fontSizes: [String: Any]) -> [String: Any] {
        var scaled = [String: Any]()
        let scaleFactor = 0.75 // 72 DPI / 96 DPI
        
        for (key, value) in fontSizes {
            if let stringValue = value as? String {
                // Extract numeric value from pt string (e.g., "12.0pt" -> 12.0)
                let numericString = stringValue.replacingOccurrences(of: "pt", with: "").trimmingCharacters(in: .whitespaces)
                if let numericValue = Double(numericString) {
                    let scaledValue = numericValue * scaleFactor
                    scaled[key] = String(format: "%.1fpt", scaledValue)
                } else {
                    // Keep original if we can't parse
                    scaled[key] = value
                }
            } else if let numericValue = value as? Double {
                let scaledValue = numericValue * scaleFactor
                scaled[key] = String(format: "%.1fpt", scaledValue)
            } else if let numericValue = value as? Int {
                let scaledValue = Double(numericValue) * scaleFactor
                scaled[key] = String(format: "%.1fpt", scaledValue)
            } else {
                // Keep original for non-numeric values
                scaled[key] = value
            }
        }
        
        return scaled
    }
    
    private func preprocessContextForTemplate(_ context: [String: Any], from resume: Resume) -> [String: Any] {
        var processed = context
        
        // Apply nonBreakingSpaces to name
        if var contact = processed["contact"] as? [String: Any],
           let name = contact["name"] as? String {
            contact["name"] = name.replacingOccurrences(of: " ", with: "&nbsp;")
            processed["contact"] = contact
        }
        
        // Process job-titles array to add nonBreakingSpaces and create joined version
        if let jobTitles = processed["job-titles"] as? [String] {
            let processedTitles = jobTitles.map { $0.replacingOccurrences(of: " ", with: "&nbsp;") }
            processed["job-titles"] = processedTitles
            processed["jobTitles"] = processedTitles // Also provide camelCase alias for template compatibility
            processed["jobTitlesJoined"] = processedTitles.joined(separator: "&nbsp;&middot;&nbsp;")
            
            // Add centered job titles for text templates
            let plainJobTitles = jobTitles.joined(separator: " · ")
            processed["centeredJobTitles"] = TextFormatHelpers.wrapper(plainJobTitles, width: 80, centered: true)
        }
        
        // Convert employment to array format while preserving TreeNode order
        if let employment = processed["employment"] as? [String: Any] {
            let employmentArray = convertEmploymentToArrayWithSorting(employment, from: resume)
            processed["employment"] = employmentArray
        }
        
        // Convert skills-and-expertise object to array format
        if let skillsDict = processed["skills-and-expertise"] as? [String: Any] {
            var skillsArray: [[String: Any]] = []
            for (title, description) in skillsDict {
                skillsArray.append([
                    "title": title,
                    "description": description
                ])
            }
            processed["skills-and-expertise"] = skillsArray
            
            // Add formatted text helpers for text templates
            processed["skillsAndExpertiseFormatted"] = TextFormatHelpers.splitAligned(skillsArray, width: 80)
        }
        
        // Convert education object to array format
        if let educationDict = processed["education"] as? [String: Any] {
            var educationArray: [[String: Any]] = []
            for (institution, details) in educationDict {
                if var detailsDict = details as? [String: Any] {
                    detailsDict["institution"] = institution
                    educationArray.append(detailsDict)
                }
            }
            processed["education"] = educationArray
        }
        
        // Convert projects-highlights object to array format
        if let projectsDict = processed["projects-highlights"] as? [String: Any] {
            var projectsArray: [[String: Any]] = []
            for (name, description) in projectsDict {
                projectsArray.append([
                    "name": name,
                    "description": description
                ])
            }
            processed["projects-highlights"] = projectsArray
            
            // Add formatted text for projects
            processed["projectsHighlightsFormatted"] = TextFormatHelpers.wrapBlurb(projectsArray)
        }
        
        // Add pre-formatted text sections for text templates
        if let contact = processed["contact"] as? [String: Any] {
            if let name = contact["name"] as? String {
                processed["centeredName"] = TextFormatHelpers.wrapper(name, width: 80, centered: true)
            }
            
            if let location = contact["location"] as? [String: Any] {
                let city = location["city"] as? String ?? ""
                let state = location["state"] as? String ?? ""
                let phone = contact["phone"] as? String ?? ""
                let email = contact["email"] as? String ?? ""
                let website = contact["website"] as? String ?? ""
                
                let contactLine = "\(city), \(state) * \(phone) * \(email) * \(website)"
                processed["centeredContact"] = TextFormatHelpers.wrapper(contactLine, width: 80, centered: true)
            }
        }
        
        if let summary = processed["summary"] as? String {
            processed["wrappedSummary"] = TextFormatHelpers.wrapper(summary, width: 80, leftMargin: 6, rightMargin: 6)
        }
        
        // Add section line formatting
        if let sectionLabels = processed["section-labels"] as? [String: Any] {
            for (key, value) in sectionLabels {
                if let label = value as? String {
                    processed["sectionLine_\(key)"] = TextFormatHelpers.sectionLine(label, width: 80)
                }
            }
        }
        
        // Add footer text from more-info if available
        if let moreInfo = processed["more-info"] as? String {
            // For HTML templates, keep original with markup
            processed["footerText"] = moreInfo
            // For text templates, strip tags and format
            let cleanFooterText = moreInfo.replacingOccurrences(of: #"<\/?[^>]+(>|$)|↪︎"#, with: "", options: .regularExpression).uppercased()
            processed["footerTextFormatted"] = TextFormatHelpers.formatFooter(cleanFooterText, width: 80)
        }
        
        // Apply WebKit scaling to font-sizes for HTML output
        if let fontSizes = processed["font-sizes"] as? [String: Any] {
            processed["font-sizes"] = applyWebKitScaling(to: fontSizes)
        }
        
        return processed
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
    
    private func convertEmploymentToArrayWithSorting(_ employment: [String: Any], from resume: Resume) -> [[String: Any]] {
        // Get employment nodes directly from TreeNode structure to preserve sort order
        guard let rootNode = resume.rootNode,
              let employmentSection = rootNode.children?.first(where: { $0.name == "employment" }),
              let employmentNodes = employmentSection.children else {
            // Fallback to original method if we can't access TreeNodes
            return convertEmploymentToArray(employment)
        }
        
        // Sort by TreeNode myIndex to preserve user's drag-and-drop ordering
        let sortedNodes = employmentNodes.sorted { $0.myIndex < $1.myIndex }
        
        var employmentArray: [[String: Any]] = []
        
        for node in sortedNodes {
            // Get the employer name from the TreeNode
            let employer = node.name
            
            // Get the details from the parsed JSON data
            if let details = employment[employer] as? [String: Any] {
                var detailsDict = details
                detailsDict["employer"] = employer
                
                // Add formatted employment line for text templates
                let location = detailsDict["location"] as? String ?? ""
                let start = detailsDict["start"] as? String ?? ""
                let end = detailsDict["end"] as? String ?? ""
                detailsDict["employmentFormatted"] = TextFormatHelpers.jobString(employer, location: location, start: start, end: end, width: 80)
                
                employmentArray.append(detailsDict)
            }
        }
        
        return employmentArray
    }
    
    private func convertEmploymentToArray(_ employment: [String: Any]) -> [[String: Any]] {
        var employmentArray: [[String: Any]] = []
        
        for (employer, details) in employment {
            if var detailsDict = details as? [String: Any] {
                detailsDict["employer"] = employer
                
                // Add formatted employment line for text templates
                let location = detailsDict["location"] as? String ?? ""
                let start = detailsDict["start"] as? String ?? ""
                let end = detailsDict["end"] as? String ?? ""
                detailsDict["employmentFormatted"] = TextFormatHelpers.jobString(employer, location: location, start: start, end: end, width: 80)
                
                employmentArray.append(detailsDict)
            }
        }
        
        return employmentArray
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
            Task {
                do {
                    let pdfData = try await self?.generatePDFFromWebView()
                    self?.currentCompletion?(.success(pdfData!))
                } catch {
                    self?.currentCompletion?(.failure(error))
                }
                self?.currentCompletion = nil
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
