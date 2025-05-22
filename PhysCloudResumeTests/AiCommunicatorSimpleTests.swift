import XCTest
import SwiftUI
import SwiftData
@testable import PhysCloudResume

@MainActor
final class AiCommunicatorSimpleTests: XCTestCase {
    
    // Services and models
    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!
    private var resumeStore: ResStore!
    private var coverRefStore: CoverRefStore!
    private var coverLetterStore: CoverLetterStore!
    private var jobAppStore: JobAppStore!
    private var appState: AppState!
    
    // Single test model for basic functionality testing
    private var testModel: String = "gpt-4.1"  // Using a reliable model for basic tests
    
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
        
        // Set up test job app and resume
        try await setupTestDataUsingCreateNewResumeFlow()
        
        // Set the model as preferred
        UserDefaults.standard.set(testModel, forKey: "preferredLLMModel")
    }
    
    override func tearDown() async throws {
        jobAppStore = nil
        appState = nil
        modelContainer = nil
        modelContext = nil
        try await super.tearDown()
    }
    
    // Test basic resume structure creation without API calls
    func testResumeStructureCreation() async throws {
        // Get the selected resume
        guard let resume = jobAppStore.selectedApp?.selectedRes else {
            XCTFail("Selected resume should not be nil")
            return
        }
        
        // Verify basic structure
        XCTAssertNotNil(resume.rootNode, "Resume should have a root node")
        XCTAssertGreaterThan(resume.nodes.count, 0, "Resume should have tree nodes")
        
        // Verify nodes have proper structure
        let rootNode = resume.rootNode!
        XCTAssertEqual(rootNode.name, "Root", "Root node should be named 'Root'")
        XCTAssertTrue(rootNode.hasChildren, "Root node should have children")
        
        // Verify we have the expected sections
        let sectionNames = rootNode.children?.map { $0.name } ?? []
        XCTAssertTrue(sectionNames.contains("Personal Information"), "Should have Personal Information section")
        XCTAssertTrue(sectionNames.contains("Education"), "Should have Education section")
        XCTAssertTrue(sectionNames.contains("Experience"), "Should have Experience section")
        
        print("✅ Resume structure test passed")
    }
    
    // Test JSON generation without network calls
    func testJSONGeneration() async throws {
        // Get the selected resume
        guard let resume = jobAppStore.selectedApp?.selectedRes else {
            XCTFail("Selected resume should not be nil")
            return
        }
        
        // Test JSON generation
        let jsonString = resume.jsonTxt
        XCTAssertFalse(jsonString.isEmpty, "Resume should generate JSON")
        
        // Verify JSON is valid
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("JSON string should be convertible to data")
            return
        }
        
        do {
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData)
            XCTAssertNotNil(jsonObject, "Should be able to parse generated JSON")
            
            if let dict = jsonObject as? [String: Any] {
                XCTAssertNotNil(dict["contact"], "JSON should have contact section")
            }
        } catch {
            XCTFail("Generated JSON should be valid: \(error)")
        }
        
        print("✅ JSON generation test passed")
    }
    
    // Test node marking for AI review
    func testNodeMarkingForAI() async throws {
        // Get the selected resume
        guard let resume = jobAppStore.selectedApp?.selectedRes else {
            XCTFail("Selected resume should not be nil")
            return
        }
        
        // Mark nodes for AI review
        for node in resume.nodes {
            node.status = .aiToReplace
        }
        
        // Verify nodes are marked
        let aiMarkedNodes = resume.nodes.filter { $0.status == .aiToReplace }
        XCTAssertGreaterThan(aiMarkedNodes.count, 0, "Some nodes should be marked for AI review")
        
        // Test getUpdatableNodes
        let updatableNodes = resume.getUpdatableNodes()
        XCTAssertGreaterThan(updatableNodes.count, 0, "Should have updatable nodes")
        
        print("✅ Node marking test passed")
    }
    
    // MARK: - Helper Methods
    
    private func setupTestDataUsingCreateNewResumeFlow() async throws {
        // Create a job application
        let jobApp = JobApp(
            jobPosition: "Senior Physics Researcher", 
            jobLocation: "Stanford, CA",
            companyName: "Quantum Physics Institute",
            jobDescription: """
            We are seeking a Senior Physics Researcher with experience in quantum mechanics, 
            particle physics, and computational modeling.
            """
        )
        
        // Insert job app into context
        modelContext.insert(jobApp)
        
        // Create a ResModel with minimal structure for faster testing
        let resModel = ResModel(
            name: "Test Model",
            json: ResModelJSONSamples.minimalResume,
            renderedResumeText: "",
            style: "Professional"
        )
        
        // Create a resume using the ResModel
        let resume = Resume(jobApp: jobApp, enabledSources: [], model: resModel)
        
        // Create the tree structure manually
        createBasicTreeStructure(for: resume)
        
        // Set some rendered text manually (avoiding network call)
        resume.textRes = """
        Test User
        
        PERSONAL INFORMATION
        ====================
        Email: test@example.com
        Phone: (123) 456-7890
        
        EDUCATION
        =========
        Test Degree
        Institution: Test University
        Year: 2020
        
        EXPERIENCE
        ==========
        Test Position
        Company: Test Company
        Period: 2020-2023
        Test description of job responsibilities
        """
        
        // Set it as the selected resume for the job app
        jobApp.addResume(resume)
        jobApp.selectedRes = resume
        
        // Select it in the job app store
        jobAppStore.selectedApp = jobApp
    }
    
    private func createBasicTreeStructure(for resume: Resume) {
        // Create a root node
        let rootNode = TreeNode(name: "Root", value: "", inEditor: true, status: .isNotLeaf, resume: resume)
        resume.rootNode = rootNode
        
        // Add basic sections
        let personalSection = TreeNode(name: "Personal Information", value: "", inEditor: true, status: .isNotLeaf, resume: resume)
        let nameNode = TreeNode(name: "Name", value: "Test User", inEditor: true, status: .disabled, resume: resume)
        let emailNode = TreeNode(name: "Email", value: "test@example.com", inEditor: true, status: .disabled, resume: resume)
        let phoneNode = TreeNode(name: "Phone", value: "(123) 456-7890", inEditor: true, status: .disabled, resume: resume)
        
        personalSection.addChild(nameNode)
        personalSection.addChild(emailNode)
        personalSection.addChild(phoneNode)
        
        let educationSection = TreeNode(name: "Education", value: "", inEditor: true, status: .isNotLeaf, resume: resume)
        let degreeNode = TreeNode(name: "Degree", value: "Test Degree", inEditor: true, status: .disabled, resume: resume)
        let schoolNode = TreeNode(name: "School", value: "Test University", inEditor: true, status: .disabled, resume: resume)
        let yearNode = TreeNode(name: "Year", value: "2020", inEditor: true, status: .disabled, resume: resume)
        
        educationSection.addChild(degreeNode)
        educationSection.addChild(schoolNode)
        educationSection.addChild(yearNode)
        
        let experienceSection = TreeNode(name: "Experience", value: "", inEditor: true, status: .isNotLeaf, resume: resume)
        let positionNode = TreeNode(name: "Position", value: "Test Position", inEditor: true, status: .disabled, resume: resume)
        let companyNode = TreeNode(name: "Company", value: "Test Company", inEditor: true, status: .disabled, resume: resume)
        let dateNode = TreeNode(name: "Period", value: "2020-2023", inEditor: true, status: .disabled, resume: resume)
        let descriptionNode = TreeNode(name: "Description", value: "Test description of job responsibilities", inEditor: true, status: .disabled, resume: resume)
        
        experienceSection.addChild(positionNode)
        experienceSection.addChild(companyNode)
        experienceSection.addChild(dateNode)
        experienceSection.addChild(descriptionNode)
        
        // Add sections to root
        rootNode.addChild(personalSection)
        rootNode.addChild(educationSection)
        rootNode.addChild(experienceSection)
    }
}
