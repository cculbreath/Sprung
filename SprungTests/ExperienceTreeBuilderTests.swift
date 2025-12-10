import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class ExperienceTreeBuilderTests: XCTestCase {

    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    override func setUpWithError() throws {
        // Setup in-memory SwiftData container
        let schema = Schema([
            Resume.self,
            ExperienceDefaults.self,
            JobApp.self,
            ResRef.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: config)
        modelContext = modelContainer.mainContext
    }

    func testBuildTree_Structure() throws {
        // Given ExperienceDefaults with sample data
        let defaults = ExperienceDefaults()
        defaults.isWorkEnabled = true
        
        let work = WorkExperienceDefault(id: UUID())
        work.name = "Tech Corp"
        work.position = "Senior Dev"
        work.highlights = [HighlightDefault(text: "Shipped cool stuff")]
        defaults.workExperiences.append(work)
        
        modelContext.insert(defaults)
        
        // And a Resume
        let jobApp = JobApp()
        let resume = Resume(jobApp: jobApp, enabledSources: [])
        modelContext.insert(resume)
        
        // And a Manifest
        let manifest = TemplateManifest(
            slug: "test",
            sectionOrder: ["work"],
            sections: [
                "work": TemplateManifest.Section(
                    type: .arrayOfObjects,
                    defaultValue: nil,
                    fields: [
                        TemplateManifest.Section.FieldDescriptor(
                            key: "*",
                            children: [
                                TemplateManifest.Section.FieldDescriptor(key: "name"),
                                TemplateManifest.Section.FieldDescriptor(key: "position"),
                                TemplateManifest.Section.FieldDescriptor(
                                    key: "highlights",
                                    children: [
                                        TemplateManifest.Section.FieldDescriptor(key: "text")
                                    ]
                                )
                            ]
                        )
                    ]
                )
            ]
        )

        // When building the tree
        let builder = ExperienceDefaultsToTree(resume: resume, experienceDefaults: defaults, manifest: manifest)
        let root = builder.buildTree()

        // Then verify tree structure
        XCTAssertNotNil(root)
        XCTAssertEqual(root?.name, "root")
        
        // Find "work" section
        let workNode = root?.children?.first(where: { $0.name == "work" })
        XCTAssertNotNil(workNode)
        
        // Find the job entry (using default title logic "Tech Corp" or "Senior Dev" or similar, 
        // the builder usually uses name/position if available)
        let jobNode = workNode?.children?.first
        XCTAssertNotNil(jobNode)
        
        // Verify values inside
        let positionNode = jobNode?.children?.first(where: { $0.name == "position" })
        XCTAssertEqual(positionNode?.value, "Senior Dev")
        
        let nameNode = jobNode?.children?.first(where: { $0.name == "name" })
        XCTAssertEqual(nameNode?.value, "Tech Corp")
        
        // Verify highlights
        let highlightsContainer = jobNode?.children?.first(where: { $0.name == "highlights" })
        XCTAssertNotNil(highlightsContainer)
        let highlightNode = highlightsContainer?.children?.first
        XCTAssertEqual(highlightNode?.value, "Shipped cool stuff")
    }
}
