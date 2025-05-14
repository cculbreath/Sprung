// PhysCloudResume/Resumes/Models/Resume.swift

import Foundation
import SwiftData

@Model
class Resume: Identifiable, Hashable {
    @Attribute(.unique) var id: UUID = UUID()

    /// Stores the OpenAI response ID for server-side conversation state
    var previousResponseId: String? = nil

    var needToTree: Bool = true
    var needToFont: Bool = true

    @Relationship(deleteRule: .cascade)
    var rootNode: TreeNode? // The top-level node
    var fontSizeNodes: [FontSizeNode] = []
    var includeFonts: Bool = false
    // Labels for keys previously imported; persisted as keyLabels map
    var keyLabels: [String: String] = [:]
    // Stored raw JSON data for imported editor keys; persisted as Data
    var importedEditorKeysData: Data? = nil
    /// Transient array of editor keys, backed by JSON in importedEditorKeysData
    var importedEditorKeys: [String] {
        get {
            guard let data = importedEditorKeysData else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            importedEditorKeysData = try? JSONEncoder().encode(newValue)
        }
    }

    func label(_ key: String) -> String {
        if let myLabel = keyLabels[key] {
            return myLabel
        } else {
            return key
        }
    }

    /// Computed list of all `TreeNode`s that belong to this resume.
    var nodes: [TreeNode] {
        guard let rootNode else { return [] }
        return Resume.collectNodes(from: rootNode)
    }

    private static func collectNodes(from node: TreeNode) -> [TreeNode] {
        var all: [TreeNode] = [node]
        for child in node.children ?? [] {
            all.append(contentsOf: collectNodes(from: child))
        }
        return all
    }

    var dateCreated: Date = Date()
    weak var jobApp: JobApp?

    @Relationship(deleteRule: .nullify, inverse: \ResRef.enabledResumes)
    var enabledSources: [ResRef]

    var model: ResModel? = nil
    var createdDateString: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "hh:mm a 'on' MM/dd/yy"
        return dateFormatter.string(from: dateCreated)
    }

    var textRes: String = ""
    var pdfData: Data?

    @Transient
    var isExporting: Bool = false
    var jsonTxt: String {
        if let myRoot = rootNode, let json = TreeToJson(rootNode: myRoot)?.buildJsonString() {
            return json
        } else { return "" }
    }

    func getUpdatableNodes() -> [[String: Any]] {
        if let node = rootNode {
            return TreeNode.traverseAndExportNodes(node: node)
        } else {
            return [[:]]
        }
    }

    var meta: String = "\"format\": \"FRESH@0.6.0\", \"version\": \"0.1.0\""

    init(
        jobApp: JobApp,
        enabledSources: [ResRef],
        model: ResModel
    ) {
        self.model = model
        self.jobApp = jobApp
        dateCreated = Date()
        self.enabledSources = enabledSources
    }

    @MainActor
    func generateQuery() async -> ResumeApiQuery {
        return ResumeApiQuery(resume: self)
    }

    func generateQuery() -> ResumeApiQuery {
        // Instead of using an empty profile and updating it later asynchronously,
        // create a complete profile with default values so that the query has valid data
        // This avoids the race condition where the query is used before the Task updates it
        let profile = ApplicantProfile() // Uses default values from ApplicantProfile init
        let applicant = Applicant(
            name: profile.name,
            address: profile.address,
            city: profile.city,
            state: profile.state,
            zip: profile.zip,
            websites: profile.websites,
            email: profile.email,
            phone: profile.phone
        )
        let query = ResumeApiQuery(resume: self, applicantProfile: profile)
        query.updateApplicant(applicant)
        return query
    }

    func loadPDF(from fileURL: URL = FileHandler.pdfUrl(),
                 completion: (() -> Void)? = nil)
    {
        DispatchQueue.global(qos: .background).async { [weak self] in
            defer { DispatchQueue.main.async { completion?() } }
            do {
                let data = try Data(contentsOf: fileURL)
                DispatchQueue.main.async { self?.pdfData = data }
            } catch {
                Logger.debug("Error loading PDF from \(fileURL): \(error)")
                DispatchQueue.main.async {}
            }
        }
    }

    @Transient private var exportWorkItem: DispatchWorkItem?

    func debounceExport(onStart: (() -> Void)? = nil,
                        onFinish: (() -> Void)? = nil)
    {
        exportWorkItem?.cancel()
        isExporting = true
        onStart?()

        exportWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if let jsonFile = FileHandler.saveJSONToFile(jsonString: jsonTxt) {
                Task { @MainActor in // Ensure export service call and property updates are on MainActor
                    do {
                        // This now calls the async version of export which updates pdfData and textRes
                        try await ApiResumeExportService().export(jsonURL: jsonFile, for: self)
                    } catch {
                        Logger.debug("Error during debounced export: \(error)")
                    }
                    self.isExporting = false
                    onFinish?()
                }
            } else {
                Logger.debug("Failed to save JSON to file for debounced export.")
                Task { @MainActor in // Ensure UI updates are on MainActor
                    self.isExporting = false
                    onFinish?()
                }
            }
        }
        if let workItem = exportWorkItem {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
        }
    }

    // MARK: - Async Rendering and Export (Modified for Fix Overflow)

    @MainActor // Ensure this function and its mutations run on the main actor
    func ensureFreshRenderedText() async throws {
        // Cancel any ongoing debounced export as we want a direct, awaitable one.
        exportWorkItem?.cancel()

        isExporting = true
        defer { isExporting = false }

        guard let jsonFile = FileHandler.saveJSONToFile(jsonString: jsonTxt) else {
            throw NSError(domain: "ResumeRender", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to save JSON to file for rendering."])
        }

        // Directly call the export service and await its completion.
        // The ApiResumeExportService().export function is already async
        // and should update self.pdfData and self.textRes upon completion.
        do {
            try await ApiResumeExportService().export(jsonURL: jsonFile, for: self)
            Logger.debug("ensureFreshRenderedText: Successfully exported and updated resume data.")
            Logger.debug(textRes)
        } catch {
            Logger.debug("ensureFreshRenderedText: Failed to export resume - \(error.localizedDescription)")
            throw error // Re-throw the error to be caught by the caller
        }
    }

    // MARK: - Hashable

    static func == (lhs: Resume, rhs: Resume) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
