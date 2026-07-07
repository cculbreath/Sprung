//
//  RenderPipelineFixtures.swift
//  SprungTests
//
//  Phase 2 (Resume Render Pipeline) fixtures. Kept local to RenderPipeline/ so parallel
//  phases never contend on the shared ModelFactories.swift. Provides:
//    - a minimal, file-free `TemplateManifest` (enough to satisfy ExperienceDefaultsToTree.init
//      without touching Sprung/Resources or TemplateManifestLoader)
//    - a `Resume` + `TreeNode` tree builder bound to a live in-memory context
//
//  All TreeNode/Resume construction goes through a `ModelContext` because both are SwiftData
//  @Model types; tests using these helpers must subclass `InMemoryStoreCase`.
//

import Foundation
import SwiftData
@testable import Sprung

@MainActor
enum RenderFixtures {

    // MARK: - Minimal manifest

    /// The smallest valid manifest: empty sections/order. The defaultAIFields pattern
    /// resolver walks the TreeNode tree directly and never reads the manifest, so an
    /// empty manifest fully satisfies `ExperienceDefaultsToTree.init` for resolver tests.
    static func emptyManifest(slug: String = "test-template") -> TemplateManifest {
        TemplateManifest(
            slug: slug,
            schemaVersion: TemplateManifest.currentSchemaVersion,
            sectionOrder: [],
            sections: [:]
        )
    }

    // MARK: - Resume / TreeNode construction

    /// A bare Resume attached to `context`, with NO template (so the data builder uses the
    /// no-manifest path — pure tree walk) and no rootNode yet.
    static func makeResume(in context: ModelContext) -> Resume {
        let jobApp = JobApp()
        context.insert(jobApp)
        let resume = Resume(jobApp: jobApp)
        context.insert(resume)
        return resume
    }

    /// Build and attach a root node for `resume`. Inserted into the context.
    @discardableResult
    static func makeRoot(for resume: Resume, in context: ModelContext) -> TreeNode {
        let root = TreeNode(
            name: "root",
            value: "",
            inEditor: true,
            status: .isNotLeaf,
            resume: resume
        )
        context.insert(root)
        resume.rootNode = root
        return root
    }

    /// Add a child node under `parent` using the production `addChild` (which assigns
    /// myIndex/depth/parent). Returns the new node. Inserted into `context`.
    @discardableResult
    static func addNode(
        to parent: TreeNode,
        name: String,
        value: String = "",
        status: LeafStatus = .saved,
        in context: ModelContext
    ) -> TreeNode {
        let node = TreeNode(
            name: name,
            value: value,
            inEditor: true,
            status: status,
            resume: parent.resume
        )
        context.insert(node)
        parent.addChild(node)
        return node
    }
}
