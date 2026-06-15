//
//  UpdateTodoListToolTests.swift
//  SprungTests
//
//  Input-validation tests for the one onboarding tool whose dependency is cleanly
//  constructible without the full coordinator graph: UpdateTodoListTool takes only
//  an InterviewTodoStore (a self-contained actor with a no-arg init). It validates
//  the `todos` payload BEFORE touching the store, so we can prove the
//  valid → .immediate / malformed → .invalidParameters contract end to end and
//  confirm the store actually receives the parsed items.
//
//  (The timeline / section / publication / dossier / ingest tools all hold a `weak`
//  OnboardingInterviewCoordinator and guard on it FIRST, so their arg-validation
//  paths are unreachable without a live coordinator — see the Phase 4 report.)
//

import XCTest
import SwiftyJSON
@testable import Sprung

final class UpdateTodoListToolTests: XCTestCase {

    // MARK: - Helpers

    private func makeTool() -> (UpdateTodoListTool, InterviewTodoStore) {
        let store = InterviewTodoStore()          // eventBus defaults to nil
        return (UpdateTodoListTool(todoStore: store), store)
    }

    /// Unwrap an `.immediate` result's JSON, failing the test otherwise.
    private func immediateJSON(_ result: ToolResult,
                               file: StaticString = #filePath, line: UInt = #line) -> JSON? {
        guard case .immediate(let json) = result else {
            XCTFail("expected .immediate, got \(result)", file: file, line: line)
            return nil
        }
        return json
    }

    // MARK: - Valid input

    func testValidTodosReturnsImmediateAndPopulatesStore() async throws {
        let (tool, store) = makeTool()
        let params = JSON([
            "todos": [
                ["content": "Collect writing samples", "status": "in_progress",
                 "activeForm": "Collecting writing samples"],
                ["content": "Capture job search context", "status": "pending"],
                ["content": "Validate profile", "status": "completed"]
            ]
        ])

        let result = try await tool.execute(params)
        let json = immediateJSON(result)
        XCTAssertEqual(json?["status"].string, "completed")
        XCTAssertEqual(json?["message"].string, "Todo list updated with 3 item(s)")

        // The store actually received the three parsed items, in order.
        let items = await store.items
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.map(\.content),
                       ["Collect writing samples", "Capture job search context", "Validate profile"])
        XCTAssertEqual(items.map(\.status), [.inProgress, .pending, .completed])
        XCTAssertEqual(items[0].activeForm, "Collecting writing samples")
        // No activeForm key → nil.
        XCTAssertNil(items[1].activeForm)
    }

    func testStatusRawValuesMapToEnumCases() async throws {
        let (tool, store) = makeTool()
        let params = JSON([
            "todos": [
                ["content": "a", "status": "pending"],
                ["content": "b", "status": "in_progress"],
                ["content": "c", "status": "completed"]
            ]
        ])
        _ = try await tool.execute(params)
        let items = await store.items
        XCTAssertEqual(items.map(\.status), [.pending, .inProgress, .completed],
                       "wire status strings must map to the InterviewTodoStatus cases")
    }

    func testContentIsTrimmed() async throws {
        let (tool, store) = makeTool()
        let params = JSON(["todos": [["content": "   spaced item  ", "status": "pending"]]])
        _ = try await tool.execute(params)
        let items = await store.items
        XCTAssertEqual(items.first?.content, "spaced item", "surrounding whitespace must be trimmed")
    }

    func testEmptyTodosArrayIsAcceptedAndClearsToEmpty() async throws {
        let (tool, store) = makeTool()
        // An empty array is a valid (present) array — the tool replaces with zero items.
        let result = try await tool.execute(JSON(["todos": []]))
        let json = immediateJSON(result)
        XCTAssertEqual(json?["message"].string, "Todo list updated with 0 item(s)")
        let items = await store.items
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - Invalid input

    func testMissingTodosThrowsInvalidParameters() async {
        let (tool, _) = makeTool()
        await assertInvalidParameters { try await tool.execute(JSON()) }
    }

    func testTodosWrongTypeThrowsInvalidParameters() async {
        let (tool, _) = makeTool()
        // A string where an array is expected → `.array` is nil → invalidParameters.
        await assertInvalidParameters { try await tool.execute(JSON(["todos": "not-an-array"])) }
    }

    func testEmptyContentThrowsInvalidParameters() async {
        let (tool, _) = makeTool()
        let params = JSON(["todos": [["content": "   ", "status": "pending"]]])
        await assertInvalidParameters { try await tool.execute(params) }
    }

    func testMissingContentThrowsInvalidParameters() async {
        let (tool, _) = makeTool()
        let params = JSON(["todos": [["status": "pending"]]])
        await assertInvalidParameters { try await tool.execute(params) }
    }

    func testUnknownStatusThrowsInvalidParameters() async {
        let (tool, _) = makeTool()
        let params = JSON(["todos": [["content": "x", "status": "halfway"]]])
        await assertInvalidParameters { try await tool.execute(params) }
    }

    func testMissingStatusThrowsInvalidParameters() async {
        let (tool, _) = makeTool()
        let params = JSON(["todos": [["content": "x"]]])
        await assertInvalidParameters { try await tool.execute(params) }
    }

    // MARK: - Error assertion helper

    /// Assert the closure throws `ToolError.invalidParameters`. A thrown error (not a
    /// returned `.error`) is the tool's contract for malformed args.
    private func assertInvalidParameters(
        _ body: () async throws -> ToolResult,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            let result = try await body()
            XCTFail("expected ToolError.invalidParameters, got result \(result)", file: file, line: line)
        } catch let error as ToolError {
            guard case .invalidParameters = error else {
                return XCTFail("expected .invalidParameters, got \(error)", file: file, line: line)
            }
        } catch {
            XCTFail("expected ToolError.invalidParameters, got \(error)", file: file, line: line)
        }
    }
}
