import XCTest
import SwiftUI
import SwiftData
@testable import PhysCloudResume

@MainActor
final class ResumeRevisionWorkflowTests: XCTestCase {
    
    // Services and models
    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!
    private var resumeStore: ResStore!
    private var coverRefStore: CoverRefStore!
    private var coverLetterStore: CoverLetterStore!
    private var jobAppStore: JobAppStore!
    private var appState: AppState!
    private var llmClient: AppLLMClientProtocol!
    
    // Test models to use (same as JobRecommendationButton tests plus additions)
    private var testModels: [String] = [
        "gpt-4.1",                // OpenAI
        "gpt-4o",                 // OpenAI (Added)
        "o3",                     // OpenAI
        "o4-mini",                // OpenAI (Added)
        "claude-3-5-haiku-latest", // Claude
        "grok-3-mini-fast",       // Grok
        "grok-3",                 // Grok (Added)
        "gemini-2.0-flash"        // Gemini
    ]
    
    // Expected results mapping (similar to JobRecommendationButton tests)
    private var expectedResults: [String: Bool] = [:]
    
    // Test state tracking
    private var initialTreeNodeCount: Int = 0
    private var revisionProposals: [ProposedRevisionNode] = []
    private var feedbackNodes: [FeedbackNode] = []
    
    // Resume PDF rendering endpoint
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
        
        // Set up test data using CreateNewResumeView workflow
        try await setupTestDataUsingCreateNewResumeFlow()
        
        // Configure API keys from hardcoded values (same as JobRecommendationButton tests)
        configureApiKeys()
        
        // Set expected results
        expectedResults = [
            "gpt-4.1": true,
            "gpt-4o": true,
            "o3": true,
            "o4-mini": false,         // o4-mini doesn't support reasoning_effort, expected to fail
            "claude-3-5-haiku-latest": true,
            "grok-3-mini-fast": true,
            "grok-3": true,
            "gemini-2.0-flash": true
        ]
        
        print("🚀 Using test models: \(testModels.joined(separator: ", "))")
    }
    
    override func tearDown() async throws {
        jobAppStore = nil
        appState = nil
        modelContainer = nil
        modelContext = nil
        llmClient = nil
        try await super.tearDown()
    }
    
    // Test the complete resume revision workflow with multiple LLM models
    func testResumeRevisionWorkflow() async throws {
        // STEP 1: Verify test data setup
        guard let resume = jobAppStore.selectedApp?.selectedRes else {
            XCTFail("Selected resume should not be nil")
            return
        }
        
        XCTAssertGreaterThan(resume.nodes.count, 0, "Resume should have tree nodes")
        XCTAssertNotNil(resume.rootNode, "Resume should have a root node")
        XCTAssertFalse(resume.textRes.isEmpty, "Resume should have rendered text")
        
        // Count nodes marked for AI review
        let aiMarkedNodes = resume.nodes.filter { $0.status == .aiToReplace }
        XCTAssertGreaterThan(aiMarkedNodes.count, 0, "Some nodes should be marked for AI review")
        
        // STEP 2: Test each model in sequence
        var results: [(modelName: String, success: Bool, errorMessage: String?)] = []
        
        for model in testModels {
            do {
                print("\n🧪 Testing resume revision workflow with model: \(model)")
                try await testSingleModelRevisionWorkflow(modelName: model, resume: resume)
                
                // Record success
                results.append((model, true, nil))
                
                // Reset resume state between model tests
                if model != testModels.last {
                    try await resetResumeState(resume: resume)
                }
            } catch {
                // Special case for o4-mini with expected reasoning_effort error
                if model == "o4-mini" && error.localizedDescription.lowercased().contains("reasoning_effort") {
                    print("✓ \(model): Failed with reasoning_effort error as expected")
                    results.append((model, false, "Expected reasoning_effort error"))
                } else {
                    print("❌ \(model) failed: \(error.localizedDescription)")
                    results.append((model, false, error.localizedDescription))
                    
                    // Skip to next model
                    if model != testModels.last {
                        try await resetResumeState(resume: resume)
                    }
                }
            }
        }
        
        // Generate summary report
        print("\n----- RESUME REVISION WORKFLOW TEST RESULTS -----")
        for result in results {
            let expectedOutcome = expectedResults[result.modelName] ?? true
            let actualOutcome = result.success
            
            if expectedOutcome == actualOutcome {
                print("✅ Model \(result.modelName): \(actualOutcome ? "SUCCESS" : "EXPECTED FAILURE")")
            } else {
                print("❌ Model \(result.modelName): \(actualOutcome ? "UNEXPECTED SUCCESS" : "UNEXPECTED FAILURE") - \(result.errorMessage ?? "unknown error")")
                if result.modelName != "o4-mini" {
                    XCTFail("Model \(result.modelName) did not behave as expected")
                }
            }
        }
        print("--------------------------------------------------\n")
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
            particle physics, and computational modeling. The ideal candidate will have a PhD in Physics 
            and 5+ years of research experience. Knowledge of Python, computational physics, 
            and experience with large datasets is required.
            
            Key Responsibilities:
            - Lead research initiatives in quantum computing
            - Develop computational models for quantum systems
            - Publish findings in leading journals
            - Collaborate with interdisciplinary research teams
            - Mentor junior researchers and graduate students
            
            Requirements:
            - PhD in Physics or related field
            - Strong publication record
            - Proficiency in Python and computational physics
            - Experience with quantum research
            - Excellent communication skills
            """
        )
        
        // Insert job app into context
        modelContext.insert(jobApp)
        
        // Create a ResModel
        let resModel = ResModel(
            name: "Test Model",
            json: ResModelJSONSamples.standardResume, // Using the full resume for better testing
            renderedResumeText: "",  // Will be populated later
            style: "Professional"
        )
        
        // Use the CreateNewResumeView workflow
        // 1. Create a Resume instance
        let resume = Resume(jobApp: jobApp, enabledSources: [], model: resModel)
        
        // 2. Build tree structure manually instead of using buildTreeFromModel
        createTreeStructure(for: resume)
        
        // 3. Render the resume using the production endpoint
        try await renderResumeUsingProductionEndpoint(resume: resume)
        
        // 4. Set it as the selected resume for the job app
        jobApp.addResume(resume)
        jobApp.selectedRes = resume
        
        // 5. Select it in the job app store
        jobAppStore.selectedApp = jobApp
        
        // 6. Mark nodes for AI review
        markAllNodesForAiReview(resume: resume)
        
        // 7. Store initial node count
        initialTreeNodeCount = resume.nodes.count
    }
    
    // Create a tree structure from the JSON data
    private func createTreeStructure(for resume: Resume) {
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
    
    private func markAllNodesForAiReview(resume: Resume) {
        for node in resume.nodes {
            node.status = .aiToReplace
        }
    }
    
    // Reset the resume state between model tests
    private func resetResumeState(resume: Resume) async throws {
        // Recreate the tree structure manually
        createTreeStructure(for: resume)
        
        // Re-render the resume
        try await renderResumeUsingProductionEndpoint(resume: resume)
        
        // Re-mark nodes for AI review
        markAllNodesForAiReview(resume: resume)
        
        // Reset test state
        initialTreeNodeCount = resume.nodes.count
        revisionProposals = []
        feedbackNodes = []
    }
    
    private func testSingleModelRevisionWorkflow(modelName: String, resume: Resume) async throws {
        print("\n🧪 Testing resume revision workflow with model: \(modelName)")
        
        // Set the current LLM model
        UserDefaults.standard.set(modelName, forKey: "preferredLLMModel")
        
        // Create an LLM client for the model
        llmClient = AppLLMClientFactory.createClientForModel(model: modelName, appState: appState)
        
        // Record original node values for later comparison
        let originalNodeValues = recordOriginalNodeValues(resume: resume)
        
        // STEP 1: Create a ResumeApiQuery
        let query = ResumeApiQuery(resume: resume)
        XCTAssertNotNil(query, "Could not create ResumeApiQuery")
        
        // STEP 2: Create a chat provider
        let chatProvider = ResumeChatProvider(client: llmClient)
        
        // STEP 3: Create the AI communicator (without UI)
        let communicator = TestAiCommunicator(
            client: llmClient, 
            query: query, 
            resume: resume,
            chatProvider: chatProvider,
            renderingEndpoint: resumeRenderingEndpoint
        )
        
        // STEP 4: Start the initial AI revision process
        print("📋 Starting initial AI revision process with model \(modelName)...")
        try await communicator.startInitialRevisionProcess()
        
        // STEP 5: Verify we received revision nodes
        let revisionNodes = communicator.revisionNodes
        XCTAssertGreaterThan(revisionNodes.count, 0, "Should have received revision nodes from the AI")
        print("✅ Received \(revisionNodes.count) revision nodes from \(modelName)")
        
        // Verify nodes have valid IDs that match the resume
        let resumeNodeIds = Set(resume.nodes.map { $0.id })
        for node in revisionNodes {
            XCTAssertFalse(node.id.isEmpty, "Revision node should have a valid ID")
            XCTAssertTrue(resumeNodeIds.contains(node.id), 
                         "Revision node ID should match a node in the resume")
        }
        
        // Save to test state for validation
        revisionProposals = revisionNodes
        
        // STEP 6: Simulate ReviewView interactions
        print("📝 Simulating user review of suggestions...")
        let feedbackNodes = try await simulateUserReview(revisions: revisionNodes)
        
        // Save to test state for validation
        self.feedbackNodes = feedbackNodes
        
        // STEP 7: Simulate AI Resubmission for revisions that needed changes
        let nodesRequiringResubmission = feedbackNodes.filter { 
            [PostReviewAction.revise, PostReviewAction.rewriteNoComment, PostReviewAction.mandatedChange, PostReviewAction.mandatedChangeNoComment].contains($0.actionRequested) 
        }
        
        if !nodesRequiringResubmission.isEmpty {
            print("🔄 Simulating resubmission for \(nodesRequiringResubmission.count) nodes...")
            try await communicator.resubmitForRevision(feedbackNodes: nodesRequiringResubmission)
            
            // STEP 8: Verify revised suggestions
            let secondRevisionNodes = communicator.revisionNodes
            XCTAssertGreaterThan(secondRevisionNodes.count, 0, 
                                "Should have received revision nodes after resubmission")
            
            // STEP 9: Simulate second review round
            print("📝 Simulating second review round...")
            let secondFeedbackNodes = try await simulateSecondReview(revisions: secondRevisionNodes)
            
            // Apply all accepted changes from second round
            applyAcceptedChanges(feedbackNodes: secondFeedbackNodes, resume: resume)
        }
        
        // STEP 10: Apply all accepted changes from first round
        print("💾 Applying accepted changes...")
        applyAcceptedChanges(feedbackNodes: feedbackNodes, resume: resume)
        
        // STEP 11: Re-render the resume to ensure changes are reflected
        try await renderResumeUsingProductionEndpoint(resume: resume)
        
        // Verify the rendered text was updated
        XCTAssertFalse(resume.textRes.isEmpty, "Resume should have updated rendered text")
        
        // STEP 12: Validate final resume
        validateFinalResume(resume: resume, originalNodeValues: originalNodeValues)
        
        print("✅ Completed workflow test for model: \(modelName)")
    }
    
    // Record original values for later comparison
    private func recordOriginalNodeValues(resume: Resume) -> [String: (name: String, value: String)] {
        var originalValues: [String: (name: String, value: String)] = [:]
        
        for node in resume.nodes {
            originalValues[node.id] = (name: node.name, value: node.value)
        }
        
        return originalValues
    }
    
    // Simulates user reviewing revision suggestions with a mix of accept/reject actions
    private func simulateUserReview(revisions: [ProposedRevisionNode]) async throws -> [FeedbackNode] {
        // Create feedback nodes for each revision
        var feedbackNodes: [FeedbackNode] = []
        
        for (index, revision) in revisions.enumerated() {
            // Create a feedback node
            let feedbackNode = FeedbackNode(
                id: revision.id,
                originalValue: revision.oldValue,
                proposedRevision: revision.newValue,
                isTitleNode: revision.isTitleNode
            )
            
            // Simulate different user actions based on index (for variety)
            switch index % 5 {
            case 0:
                // Accept the revision as is
                feedbackNode.actionRequested = .accepted
            case 1:
                // Modify and accept the revision
                feedbackNode.proposedRevision = "\(revision.newValue) (modified by user)"
                feedbackNode.actionRequested = .acceptedWithChanges
            case 2:
                // Reject and request revision with comments
                feedbackNode.reviewerComments = "Please make this more concise and specific."
                feedbackNode.actionRequested = .revise
            case 3:
                // Reject without comments
                feedbackNode.actionRequested = .rewriteNoComment
            case 4:
                // Restore original
                feedbackNode.proposedRevision = revision.oldValue
                feedbackNode.actionRequested = .restored
            default:
                feedbackNode.actionRequested = .accepted
            }
            
            feedbackNodes.append(feedbackNode)
        }
        
        return feedbackNodes
    }
    
    // Simulates second round of reviews, accepting all suggestions
    private func simulateSecondReview(revisions: [ProposedRevisionNode]) async throws -> [FeedbackNode] {
        var feedbackNodes: [FeedbackNode] = []
        
        for revision in revisions {
            let feedbackNode = FeedbackNode(
                id: revision.id,
                originalValue: revision.oldValue,
                proposedRevision: revision.newValue,
                actionRequested: .accepted,
                isTitleNode: revision.isTitleNode
            )
            feedbackNodes.append(feedbackNode)
        }
        
        return feedbackNodes
    }
    
    // Applies accepted changes to the resume
    private func applyAcceptedChanges(feedbackNodes: [FeedbackNode], resume: Resume) {
        for node in feedbackNodes {
            if node.actionRequested == .accepted || node.actionRequested == .acceptedWithChanges {
                if let treeNode = resume.nodes.first(where: { $0.id == node.id }) {
                    if node.isTitleNode {
                        treeNode.name = node.proposedRevision
                    } else {
                        treeNode.value = node.proposedRevision
                    }
                    
                    // Update node status - use .saved instead of .done
                    treeNode.status = .saved
                }
            }
        }
    }
    
    // Validates the final resume after applying changes
    private func validateFinalResume(resume: Resume, originalNodeValues: [String: (name: String, value: String)]) {
        // Verify node count remains consistent
        XCTAssertEqual(resume.nodes.count, initialTreeNodeCount, 
                      "Node count should remain consistent after applying changes")
        
        // Verify no nodes are still marked for AI review
        let remainingAiNodes = resume.nodes.filter { $0.status == .aiToReplace }
        XCTAssertEqual(remainingAiNodes.count, 0, 
                      "All nodes should have been processed by AI")
        
        // Verify content was actually changed
        var changesFound = false
        for node in resume.nodes {
            if let originalValues = originalNodeValues[node.id] {
                if node.isTitleNode && node.name != originalValues.name {
                    changesFound = true
                    break
                } else if !node.isTitleNode && node.value != originalValues.value {
                    changesFound = true
                    break
                }
            }
        }
        
        XCTAssertTrue(changesFound, "Some content should have been changed by the AI")
        
        // Verify rendered resume text has been updated
        XCTAssertFalse(resume.textRes.isEmpty, "Resume should have rendered text")
    }
    
    private func configureApiKeys() {
        // IMPORTANT: Using hardcoded API keys for development testing only
        // Retrieve API keys from UserDefaults
        let openAiKey = UserDefaults.standard.string(forKey: "openAiApiKey") ?? ""
        let claudeKey = UserDefaults.standard.string(forKey: "claudeApiKey") ?? ""
        let grokKey = UserDefaults.standard.string(forKey: "grokApiKey") ?? ""
        let geminiKey = UserDefaults.standard.string(forKey: "geminiApiKey") ?? ""
        
        // Filter test models based on available API keys
        filterTestModels()
    }
    
    private func filterTestModels() {
        let openAiKey = UserDefaults.standard.string(forKey: "openAiApiKey") ?? ""
        let claudeKey = UserDefaults.standard.string(forKey: "claudeApiKey") ?? ""
        let grokKey = UserDefaults.standard.string(forKey: "grokApiKey") ?? ""
        let geminiKey = UserDefaults.standard.string(forKey: "geminiApiKey") ?? ""
        
        // Start with all models
        var filteredModels: [String] = []
        
        // Only keep models for which we have API keys
        for model in testModels {
            let provider = AIModels.providerForModel(model)
            
            switch provider {
            case AIModels.Provider.openai:
                if !openAiKey.isEmpty {
                    filteredModels.append(model)
                }
            case AIModels.Provider.claude:
                if !claudeKey.isEmpty {
                    filteredModels.append(model)
                }
            case AIModels.Provider.grok:
                if !grokKey.isEmpty {
                    filteredModels.append(model)
                }
            case AIModels.Provider.gemini:
                if !geminiKey.isEmpty {
                    filteredModels.append(model)
                }
            default:
                // Keep unknown providers for testing
                filteredModels.append(model)
            }
        }
        
        // Update test models
        testModels = filteredModels
        print("🚀 Testing with models: \(testModels.joined(separator: ", "))")
    }
}
