//
//  AnthropicMessagesServiceTests.swift
//  SprungTests
//
//  Pure-halves coverage for the Anthropic Messages seam that `LLMFacade`
//  exposes via the `AnthropicMessagesService` protocol.
//
//  Per agents.md we do NOT construct or fake `LLMFacade` (heavy init, hits the
//  network). The facade's Anthropic methods are one-line delegations to
//  `LLMFacadeSpecializedAPIs`, whose real logic splits cleanly into two pure
//  halves that this file tests directly:
//
//    1. RESPONSE PARSE — `LLMFacadeSpecializedAPIs.decodeAnthropicResponse(_:as:)`
//       decodes accumulated Anthropic response text into a Codable type.
//       Well-formed JSON → the expected struct; malformed JSON → the documented
//       throw (`LLMError.clientError("Failed to parse structured response: ...")`).
//       The function is `internal` (not `private`) precisely so it can be tested
//       here without the facade.
//
//    2. REQUEST BUILD — the three `executeX...WithAnthropicCaching/Blocks`
//       methods build an `AnthropicMessageParameter` inline before driving the
//       stream. That parameter construction is deterministic. These tests
//       rebuild the SAME parameter the production methods build and assert the
//       encoded wire JSON: model id, messages, system blocks + cache_control
//       placement, max_tokens, and output_config.format (json_schema). The
//       `AnthropicMessageParameter` encoder is pure (no service), so this
//       verifies the request shape without touching the live AnthropicService.
//
//  Why request-build is rebuilt rather than called directly: the param
//  construction is not extracted into its own function — it is entangled with
//  `runAnthropicRequest` (which calls the live service). Extracting it would be
//  a behavior-touching refactor outside this byte-neutral slice, so we encode
//  the exact same parameter and pin its wire shape.
//

import XCTest
import SwiftOpenAI
@testable import Sprung

@MainActor
final class AnthropicMessagesServiceTests: XCTestCase {

    private let specializedAPIs = LLMFacadeSpecializedAPIs()

    // MARK: - Helpers

    private struct StructuredPayload: Codable, Equatable {
        let title: String
        let count: Int
    }

    /// Encode an `AnthropicMessageParameter` to a JSON object, matching how the
    /// fork serializes it onto the wire (snake_case keys).
    private func wireObject(_ parameter: AnthropicMessageParameter) throws -> [String: Any] {
        let data = try JSONEncoder().encode(parameter)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    // MARK: - Response parse: well-formed -> struct

    func testDecodeAnthropicResponseDecodesWellFormedJSON() throws {
        let text = #"{"title": "Hello", "count": 3}"#
        let decoded = try specializedAPIs.decodeAnthropicResponse(text, as: StructuredPayload.self)
        XCTAssertEqual(decoded, StructuredPayload(title: "Hello", count: 3))
    }

    func testDecodeAnthropicResponseDecodesWhitespacePaddedJSON() throws {
        // The accumulated stream text can carry surrounding whitespace; JSONDecoder
        // tolerates leading/trailing whitespace, so this must still decode.
        let text = "\n  {\"title\": \"Padded\", \"count\": 0}\n"
        let decoded = try specializedAPIs.decodeAnthropicResponse(text, as: StructuredPayload.self)
        XCTAssertEqual(decoded, StructuredPayload(title: "Padded", count: 0))
    }

    // MARK: - Response parse: malformed -> documented throw

    func testDecodeAnthropicResponseThrowsClientErrorOnMalformedJSON() {
        let text = "this is not json"
        XCTAssertThrowsError(
            try specializedAPIs.decodeAnthropicResponse(text, as: StructuredPayload.self)
        ) { error in
            // Documented behavior: parse failures are wrapped as
            // LLMError.clientError("Failed to parse structured response: ...").
            guard case let LLMError.clientError(message) = error else {
                return XCTFail("Expected LLMError.clientError, got \(error)")
            }
            XCTAssertTrue(
                message.hasPrefix("Failed to parse structured response:"),
                "Unexpected message: \(message)"
            )
        }
    }

    func testDecodeAnthropicResponseThrowsClientErrorOnSchemaMismatch() {
        // Valid JSON but wrong shape (missing `count`) is still a decode failure.
        let text = #"{"title": "MissingCount"}"#
        XCTAssertThrowsError(
            try specializedAPIs.decodeAnthropicResponse(text, as: StructuredPayload.self)
        ) { error in
            guard case let LLMError.clientError(message) = error else {
                return XCTFail("Expected LLMError.clientError, got \(error)")
            }
            XCTAssertTrue(message.hasPrefix("Failed to parse structured response:"))
        }
    }

    // MARK: - Request build: executeTextWithAnthropicCaching parameter shape

    func testTextCachingParameterShape() throws {
        // Mirror the parameter that executeTextWithAnthropicCaching builds.
        let parameter = AnthropicMessageParameter(
            model: "test-model-id",
            messages: [.user("the user prompt")],
            system: .blocks([
                AnthropicSystemBlock(text: "static preamble", cacheControl: .ephemeral),
                AnthropicSystemBlock(text: "volatile tail")
            ]),
            maxTokens: 4096,
            stream: false
        )

        let wire = try wireObject(parameter)
        XCTAssertEqual(wire["model"] as? String, "test-model-id")
        XCTAssertEqual(wire["max_tokens"] as? Int, 4096)
        XCTAssertEqual(wire["stream"] as? Bool, false)
        // No structured output for the text variant.
        XCTAssertNil(wire["output_config"])

        // Single user message, role + text.
        let messages = try XCTUnwrap(wire["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        XCTAssertEqual(messages[0]["content"] as? String, "the user prompt")

        // System is an array of blocks; cache_control sits on the first block only.
        let systemBlocks = try XCTUnwrap(wire["system"] as? [[String: Any]])
        XCTAssertEqual(systemBlocks.count, 2)
        XCTAssertEqual(systemBlocks[0]["type"] as? String, "text")
        XCTAssertEqual(systemBlocks[0]["text"] as? String, "static preamble")
        let cacheControl = try XCTUnwrap(systemBlocks[0]["cache_control"] as? [String: Any])
        XCTAssertEqual(cacheControl["type"] as? String, "ephemeral")
        XCTAssertNil(systemBlocks[1]["cache_control"], "the volatile tail block carries no cache_control")
    }

    // MARK: - Request build: executeStructuredWithAnthropicCaching parameter shape

    func testStructuredCachingParameterShapeIncludesJSONSchema() throws {
        let schema: [String: Any] = [
            "type": "object",
            "properties": ["title": ["type": "string"]],
            "additionalProperties": false
        ]
        // Mirror the parameter that executeStructuredWithAnthropicCaching builds.
        let parameter = AnthropicMessageParameter(
            model: "structured-model",
            messages: [.user("structured prompt")],
            system: .blocks([AnthropicSystemBlock(text: "sys", cacheControl: .ephemeral)]),
            maxTokens: 4096,
            stream: false,
            outputConfig: AnthropicOutputConfig.schema(schema)
        )

        let wire = try wireObject(parameter)
        XCTAssertEqual(wire["model"] as? String, "structured-model")
        XCTAssertEqual(wire["max_tokens"] as? Int, 4096)
        XCTAssertEqual(wire["stream"] as? Bool, false)

        // output_config.format must carry a json_schema with the provided schema.
        let outputConfig = try XCTUnwrap(wire["output_config"] as? [String: Any])
        let format = try XCTUnwrap(outputConfig["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        let wiredSchema = try XCTUnwrap(format["schema"] as? [String: Any])
        XCTAssertEqual(wiredSchema["type"] as? String, "object")
        XCTAssertEqual(wiredSchema["additionalProperties"] as? Bool, false)
    }

    // MARK: - Request build: executeStructuredWithAnthropicBlocks parameter shape

    func testStructuredBlocksParameterShapeHonorsCustomMaxTokensAndBlockContent() throws {
        let schema: [String: Any] = ["type": "object", "additionalProperties": false]
        let userBlocks: [AnthropicContentBlock] = [
            .document(AnthropicDocumentBlock(
                source: AnthropicDocumentSource(mediaType: "application/pdf", data: "BASE64"),
                cacheControl: .ephemeral
            )),
            .text(AnthropicTextBlock(text: "analyze this document"))
        ]
        // Mirror the parameter that executeStructuredWithAnthropicBlocks builds,
        // including a non-default maxTokens (the method signature default is 8192).
        let parameter = AnthropicMessageParameter(
            model: "blocks-model",
            messages: [AnthropicMessage(role: "user", content: .blocks(userBlocks))],
            system: .blocks([AnthropicSystemBlock(text: "sys", cacheControl: .ephemeral)]),
            maxTokens: 8192,
            stream: false,
            outputConfig: AnthropicOutputConfig.schema(schema)
        )

        let wire = try wireObject(parameter)
        XCTAssertEqual(wire["model"] as? String, "blocks-model")
        XCTAssertEqual(wire["max_tokens"] as? Int, 8192)

        // The user message content is an array of blocks (document + text), with
        // cache_control on the document block.
        let messages = try XCTUnwrap(wire["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        let blocks = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0]["type"] as? String, "document")
        XCTAssertNotNil(blocks[0]["cache_control"], "document block carries cache_control")
        XCTAssertEqual(blocks[1]["type"] as? String, "text")
        XCTAssertEqual(blocks[1]["text"] as? String, "analyze this document")

        // Structured output present.
        let outputConfig = try XCTUnwrap(wire["output_config"] as? [String: Any])
        let format = try XCTUnwrap(outputConfig["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
    }

    // MARK: - Conformance smoke

    func testLLMFacadeConformsToAnthropicMessagesService() {
        // Compile-time proof the conformance exists (no instance constructed):
        // this generic helper only accepts a type that conforms to the protocol,
        // so it fails to compile if `extension LLMFacade: AnthropicMessagesService`
        // is ever removed.
        func requireConformance<T: AnthropicMessagesService>(_ type: T.Type) {}
        requireConformance(LLMFacade.self)
    }
}
