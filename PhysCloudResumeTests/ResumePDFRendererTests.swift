import XCTest
import SwiftUI
import SwiftData
@testable import PhysCloudResume

@MainActor
final class ResumePDFRendererTests: XCTestCase {
    
    // Services and models
    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!
    private var resumeStore: ResStore!
    private var coverRefStore: CoverRefStore!
    private var coverLetterStore: CoverLetterStore!
    private var jobAppStore: JobAppStore!
    private var appState: AppState!
    
    // Resume rendering endpoint
    private let resumeRenderingEndpoint = "https://resume.physicscloud.net/render"
    
    // Setup testing environment
    override func setUp() async throws {
        try await super.setUp()
        
        // Initialize in-memory SwiftData container for testing
        modelContainer = try ModelContainer(for: JobApp.self, Resume.self, TreeNode.self, ResModel.self, 
                                          configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        
        modelContext = ModelContext(modelContainer)
        
        // Initialize stores
        resumeStore = ResStore(context: modelContext)
        coverRefStore = CoverRefStore(context: modelContext)
        coverLetterStore = CoverLetterStore(context: modelContext, refStore: coverRefStore)
        jobAppStore = JobAppStore(context: modelContext, resStore: resumeStore, coverLetterStore: coverLetterStore)
        
        // Initialize app state
        appState = AppState()
    }
    
    override func tearDown() async throws {
        jobAppStore = nil
        appState = nil
        modelContainer = nil
        modelContext = nil
        try await super.tearDown()
    }
    
    // Test the basic resume creation and rendering process
    func testResumeRenderingWithStandardJSON() async throws {
        // Create a test job application
        let jobApp = createTestJobApp()
        
        // Create a test resume
        let resModel = ResModel(
            name: "Standard Resume",
            json: ResModelJSONSamples.standardResume,
            renderedResumeText: "",
            style: "Professional"
        )
        
        // Create a resume using the ResModel
        let resume = Resume(jobApp: jobApp, enabledSources: [], model: resModel)
        
        // Create tree structure manually instead of using buildTreeFromModel
        createTreeStructureFromStandardJSON(for: resume)
        
        // Verify the tree was built correctly
        XCTAssertNotNil(resume.rootNode, "Resume should have a root node")
        XCTAssertGreaterThan(resume.nodes.count, 0, "Resume should have tree nodes")
        
        // Render the resume using the production endpoint
        try await renderResumeUsingProductionEndpoint(resume: resume)
        
        // Verify the rendered text was generated
        XCTAssertFalse(resume.textRes.isEmpty, "Resume should have rendered text")
        XCTAssertFalse(resume.model?.renderedResumeText.isEmpty ?? true, "ResModel should have rendered text")
        
        // Check for expected content in the rendered text
        XCTAssertTrue(resume.textRes.contains("Christopher Culbreath"), "Rendered text should contain the name")
        XCTAssertTrue(resume.textRes.contains("PhD in Chemical Physics"), "Rendered text should contain education info")
        
        print("✅ Successfully rendered resume with standard JSON")
    }
    
    func testResumeRenderingWithMinimalJSON() async throws {
        // Create a test job application
        let jobApp = createTestJobApp()
        
        // Create a test resume
        let resModel = ResModel(
            name: "Minimal Resume",
            json: ResModelJSONSamples.minimalResume,
            renderedResumeText: "",
            style: "Professional"
        )
        
        // Create a resume using the ResModel
        let resume = Resume(jobApp: jobApp, enabledSources: [], model: resModel)
        
        // Create tree structure manually
        createTreeStructureFromMinimalJSON(for: resume)
        
        // Verify the tree was built correctly
        XCTAssertNotNil(resume.rootNode, "Resume should have a root node")
        XCTAssertGreaterThan(resume.nodes.count, 0, "Resume should have tree nodes")
        
        // Render the resume using the production endpoint
        try await renderResumeUsingProductionEndpoint(resume: resume)
        
        // Verify the rendered text was generated
        XCTAssertFalse(resume.textRes.isEmpty, "Resume should have rendered text")
        XCTAssertFalse(resume.model?.renderedResumeText.isEmpty ?? true, "ResModel should have rendered text")
        
        // Check for expected content in the rendered text
        XCTAssertTrue(resume.textRes.contains("Test User"), "Rendered text should contain the name")
        XCTAssertTrue(resume.textRes.contains("Test Degree"), "Rendered text should contain education info")
        
        print("✅ Successfully rendered resume with minimal JSON")
    }
    
    // Helper method to create a test job app
    private func createTestJobApp() -> JobApp {
        let jobApp = JobApp(
            jobPosition: "Senior Physics Researcher",
            jobLocation: "Stanford, CA",
            companyName: "Test Research Institute",
            jobDescription: """
            We are seeking a Senior Physics Researcher with experience in quantum mechanics, 
            particle physics, and computational modeling. The ideal candidate will have a PhD in Physics 
            and 5+ years of research experience. Knowledge of Python, computational physics, 
            and experience with large datasets is required.
            """
        )
        
        // Insert job app into context
        modelContext.insert(jobApp)
        
        return jobApp
    }
    
    // Create tree structure from standard JSON
    private func createTreeStructureFromStandardJSON(for resume: Resume) {
        // Create root node
        let rootNode = TreeNode(name: "Root", value: "", inEditor: true, status: .isNotLeaf, resume: resume)
        resume.rootNode = rootNode
        
        // Create personal information section
        let personalSection = TreeNode(name: "Personal Information", value: "", inEditor: true, status: .isNotLeaf, resume: resume)
        personalSection.addChild(TreeNode(name: "Name", value: "Christopher Culbreath", inEditor: true, status: .disabled, resume: resume))
        personalSection.addChild(TreeNode(name: "Email", value: "cc@physicscloud.net", inEditor: true, status: .disabled, resume: resume))
        personalSection.addChild(TreeNode(name: "Phone", value: "(805) 234-0847", inEditor: true, status: .disabled, resume: resume))
        personalSection.addChild(TreeNode(name: "Location", value: "Austin, Texas", inEditor: true, status: .disabled, resume: resume))
        
        // Create education section
        let educationSection = TreeNode(name: "Education", value: "", inEditor: true, status: .isNotLeaf, resume: resume)
        let phdNode = TreeNode(name: "PhD Chemical Physics", value: "", inEditor: true, status: .isNotLeaf, resume: resume, isTitleNode: true)
        phdNode.addChild(TreeNode(name: "Institution", value: "Liquid Crystal Institute, Kent State", inEditor: true, status: .disabled, resume: resume))
        phdNode.addChild(TreeNode(name: "Year", value: "2015", inEditor: true, status: .disabled, resume: resume))
        
        let bsNode = TreeNode(name: "BS Physics", value: "", inEditor: true, status: .isNotLeaf, resume: resume, isTitleNode: true)
        bsNode.addChild(TreeNode(name: "Institution", value: "Cal Poly San Luis Obispo", inEditor: true, status: .disabled, resume: resume))
        bsNode.addChild(TreeNode(name: "Year", value: "2008", inEditor: true, status: .disabled, resume: resume))
        
        educationSection.addChild(phdNode)
        educationSection.addChild(bsNode)
        
        // Create experience section
        let experienceSection = TreeNode(name: "Work Experience", value: "", inEditor: true, status: .isNotLeaf, resume: resume)
        
        let job1 = TreeNode(name: "Automation & Materials Engineer", value: "", inEditor: true, status: .isNotLeaf, resume: resume, isTitleNode: true)
        job1.addChild(TreeNode(name: "Company", value: "Elastium Technologies", inEditor: true, status: .disabled, resume: resume))
        job1.addChild(TreeNode(name: "Location", value: "Emeryville, CA", inEditor: true, status: .disabled, resume: resume))
        job1.addChild(TreeNode(name: "Period", value: "2017-2020", inEditor: true, status: .disabled, resume: resume))
        job1.addChild(TreeNode(name: "Description", value: "Developed specialized manufacturing equipment and methods to produce previously unattainable high-performance shape memory alloys.", inEditor: true, status: .disabled, resume: resume))
        
        let job2 = TreeNode(name: "Senior Lecturer", value: "", inEditor: true, status: .isNotLeaf, resume: resume, isTitleNode: true)
        job2.addChild(TreeNode(name: "Company", value: "Cal Poly", inEditor: true, status: .disabled, resume: resume))
        job2.addChild(TreeNode(name: "Location", value: "San Luis Obispo, CA", inEditor: true, status: .disabled, resume: resume))
        job2.addChild(TreeNode(name: "Period", value: "2016-2024", inEditor: true, status: .disabled, resume: resume))
        job2.addChild(TreeNode(name: "Description", value: "Taught physics to undergraduate engineers and scientists, specializing in optics, thermodynamics, and electromagnetism.", inEditor: true, status: .disabled, resume: resume))
        
        experienceSection.addChild(job1)
        experienceSection.addChild(job2)
        
        // Create skills section
        let skillsSection = TreeNode(name: "Skills and Expertise", value: "", inEditor: true, status: .isNotLeaf, resume: resume)
        skillsSection.addChild(TreeNode(name: "Technical", value: "Quantum Mechanics, Particle Physics, Python, MATLAB, signal processing, time-series analysis", inEditor: true, status: .disabled, resume: resume))
        skillsSection.addChild(TreeNode(name: "Soft", value: "Team Leadership, Scientific Writing, Presentations", inEditor: true, status: .disabled, resume: resume))
        
        // Add sections to root node
        rootNode.addChild(personalSection)
        rootNode.addChild(educationSection)
        rootNode.addChild(experienceSection)
        rootNode.addChild(skillsSection)
    }
    
    // Create tree structure from minimal JSON
    private func createTreeStructureFromMinimalJSON(for resume: Resume) {
        // Create a root node
        let rootNode = TreeNode(name: "Root", value: "", inEditor: true, status: .isNotLeaf, resume: resume)
        resume.rootNode = rootNode
        
        // Add basic sections
        let personalSection = TreeNode(name: "Personal Information", value: "", inEditor: true, status: .isNotLeaf, resume: resume)
        personalSection.addChild(TreeNode(name: "Name", value: "Test User", inEditor: true, status: .disabled, resume: resume))
        personalSection.addChild(TreeNode(name: "Email", value: "test@example.com", inEditor: true, status: .disabled, resume: resume))
        personalSection.addChild(TreeNode(name: "Phone", value: "(123) 456-7890", inEditor: true, status: .disabled, resume: resume))
        
        let educationSection = TreeNode(name: "Education", value: "", inEditor: true, status: .isNotLeaf, resume: resume)
        let degreeNode = TreeNode(name: "Test Degree", value: "", inEditor: true, status: .isNotLeaf, resume: resume, isTitleNode: true)
        degreeNode.addChild(TreeNode(name: "Institution", value: "University", inEditor: true, status: .disabled, resume: resume))
        degreeNode.addChild(TreeNode(name: "Year", value: "2020", inEditor: true, status: .disabled, resume: resume))
        educationSection.addChild(degreeNode)
        
        let experienceSection = TreeNode(name: "Work Experience", value: "", inEditor: true, status: .isNotLeaf, resume: resume)
        let positionNode = TreeNode(name: "Test Position", value: "", inEditor: true, status: .isNotLeaf, resume: resume, isTitleNode: true)
        positionNode.addChild(TreeNode(name: "Company", value: "Test Company", inEditor: true, status: .disabled, resume: resume))
        positionNode.addChild(TreeNode(name: "Period", value: "2020-2023", inEditor: true, status: .disabled, resume: resume))
        positionNode.addChild(TreeNode(name: "Description", value: "Accomplishment 1. Accomplishment 2.", inEditor: true, status: .disabled, resume: resume))
        experienceSection.addChild(positionNode)
        
        // Add sections to root
        rootNode.addChild(personalSection)
        rootNode.addChild(educationSection)
        rootNode.addChild(experienceSection)
    }
    
    // Helper method to render resume using production endpoint
    private func renderResumeUsingProductionEndpoint(resume: Resume) async throws {
        // Create a dictionary representation of the resume
        var resumeDict: [String: Any] = [:]
        resumeDict["style"] = resume.model?.style ?? "Professional"
        
        // Convert tree structure to dictionary
        var sections: [[String: Any]] = []
        if let rootNode = resume.rootNode {
            if let children = rootNode.children {
                for sectionNode in children {
                    var section: [String: Any] = [:]
                    section["name"] = sectionNode.name
                    
                    var fields: [[String: Any]] = []
                    if let fieldNodes = sectionNode.children {
                        for fieldNode in fieldNodes {
                            var field: [String: Any] = [:]
                            field["name"] = fieldNode.name
                            field["value"] = fieldNode.value
                            fields.append(field)
                        }
                    }
                    
                    section["fields"] = fields
                    sections.append(section)
                }
            }
        }
        
        resumeDict["sections"] = sections
        
        // Convert to JSON
        let jsonData = try JSONSerialization.data(withJSONObject: resumeDict, options: [.prettyPrinted])
        
        // Make request to production endpoint
        let url = URL(string: resumeRenderingEndpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        // Execute request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check response
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "ResumeRenderingError", code: (response as? HTTPURLResponse)?.statusCode ?? 0, 
                         userInfo: [NSLocalizedDescriptionKey: "Failed to render resume"])
        }
        
        // Get text from response
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "ResumeRenderingError", code: 1001, 
                         userInfo: [NSLocalizedDescriptionKey: "Could not decode response"])
        }
        
        // Set rendered text
        resume.model?.renderedResumeText = text
        resume.textRes = text
    }
}
