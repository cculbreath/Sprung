//
//  InMemoryStoreCase.swift
//  SprungTests
//
//  Base class for any test that needs a live SwiftData object graph. Each test gets a
//  fresh, ephemeral in-memory `ModelContainer` built from the canonical `SprungSchema`,
//  so the suite never reads or mutates the developer's real `default.store`. The host app
//  itself is also kept off the real store under XCTest (see `SprungApp.isRunningUnitTests`).
//
//  Subclass and use `context` directly, or call `makeStore(...)` to construct a store
//  bound to this container's main context.
//

import XCTest
import SwiftData
@testable import Sprung

@MainActor
class InMemoryStoreCase: XCTestCase {

    /// Fresh in-memory container, rebuilt for every test method.
    private(set) var container: ModelContainer!

    /// The container's main context — thread-confined to the main actor.
    var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(
            for: SprungSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Insert a model into the test context and return it (for fluent fixture setup).
    @discardableResult
    func insert<T: PersistentModel>(_ model: T) -> T {
        context.insert(model)
        return model
    }

    /// Save the context, failing the test on error rather than swallowing it.
    func saveContext(file: StaticString = #filePath, line: UInt = #line) {
        do {
            try context.save()
        } catch {
            XCTFail("ModelContext.save() failed: \(error)", file: file, line: line)
        }
    }

    /// Fetch all instances of a model type currently in the test context.
    func fetchAll<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }
}
