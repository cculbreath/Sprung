//
//  ModelCapabilityValidatorTests.swift
//  SprungTests
//
//  Pins ModelCapabilityValidator's capabilityTable (single source of truth
//  for prompt-cache-retention / flex-processing gating, consolidated from
//  two separate Sets per plans/deferred-actions.md D-01) plus the
//  reasoning-effort gating helpers, and confirms unrecognized/future model
//  IDs (e.g. a hypothetical gpt-6) fall through to the conservative
//  (unsupported) default rather than being speculatively enabled.
//

import XCTest
@testable import Sprung

final class ModelCapabilityValidatorTests: XCTestCase {

    // MARK: - capabilityTable: prompt cache retention

    func testPromptCacheRetentionCompatibleModels() {
        for modelId in [
            "gpt-5.5", "gpt-5.5-pro",
            "gpt-5.4", "gpt-5.4-mini", "gpt-5.4-nano", "gpt-5.4-pro",
            "gpt-5.2",
            "gpt-5.1-codex-max", "gpt-5.1", "gpt-5.1-codex", "gpt-5.1-codex-mini", "gpt-5.1-chat-latest",
            "gpt-5", "gpt-5-codex",
            "gpt-4.1"
        ] {
            XCTAssertTrue(
                ModelCapabilityValidator.isPromptCacheRetentionCompatible(modelId),
                "\(modelId) should be cache-retention compatible")
        }
    }

    func testPromptCacheRetentionIncompatibleModels() {
        for modelId in ["gpt-5-mini", "gpt-5-nano", "o3", "o4-mini", "gpt-4o"] {
            XCTAssertFalse(
                ModelCapabilityValidator.isPromptCacheRetentionCompatible(modelId),
                "\(modelId) should not be cache-retention compatible")
        }
    }

    // MARK: - capabilityTable: flex processing

    func testFlexProcessingCompatibleModels() {
        for modelId in [
            "gpt-5.5", "gpt-5.5-pro",
            "gpt-5.4", "gpt-5.4-mini", "gpt-5.4-nano", "gpt-5.4-pro",
            "gpt-5.2", "gpt-5.1", "gpt-5", "gpt-5-mini", "gpt-5-nano",
            "o3", "o4-mini"
        ] {
            XCTAssertTrue(
                ModelCapabilityValidator.isFlexProcessingCompatible(modelId),
                "\(modelId) should be flex-processing compatible")
        }
    }

    func testFlexProcessingIncompatibleModels() {
        // Cache-retention-only variants: not flex-eligible.
        for modelId in [
            "gpt-5.1-codex-max", "gpt-5.1-codex", "gpt-5.1-codex-mini", "gpt-5.1-chat-latest",
            "gpt-5-codex", "gpt-4.1"
        ] {
            XCTAssertFalse(
                ModelCapabilityValidator.isFlexProcessingCompatible(modelId),
                "\(modelId) should not be flex-processing compatible")
        }
    }

    // MARK: - No speculation: unrecognized / future models get the conservative default

    func testUnrecognizedModelGetsNoCapabilities() {
        for modelId in ["gpt-6", "gpt-6-pro", "gpt-7", "totally-unknown-model"] {
            XCTAssertFalse(ModelCapabilityValidator.isPromptCacheRetentionCompatible(modelId))
            XCTAssertFalse(ModelCapabilityValidator.isFlexProcessingCompatible(modelId))
            XCTAssertFalse(ModelCapabilityValidator.supportsXHighReasoning(modelId))
        }
    }

    func testUnrecognizedGpt5PointReleaseStillSupportsNoneReasoning() {
        // supportsNoneReasoning is structural (any "gpt-5." point release),
        // not table-driven, so an unlisted future point release like
        // gpt-5.9 is still recognized as such — this is NOT gpt-6/gpt-7-style
        // cross-major-version speculation.
        XCTAssertTrue(ModelCapabilityValidator.supportsNoneReasoning("gpt-5.9"))
        XCTAssertFalse(ModelCapabilityValidator.supportsNoneReasoning("gpt-6.1"))
    }

    // MARK: - xhigh reasoning gating

    func testXHighReasoningSupportedFamilies() {
        for modelId in [
            "gpt-5.2", "gpt-5.4", "gpt-5.4-mini", "gpt-5.4-nano", "gpt-5.4-pro",
            "gpt-5.5", "gpt-5.5-pro"
        ] {
            XCTAssertTrue(ModelCapabilityValidator.supportsXHighReasoning(modelId))
        }
    }

    func testXHighReasoningUnsupportedFamilies() {
        for modelId in ["gpt-5", "gpt-5.1", "gpt-5.1-codex-max", "gpt-4.1", "o3"] {
            XCTAssertFalse(ModelCapabilityValidator.supportsXHighReasoning(modelId))
        }
    }

    // MARK: - sanitizeReasoningEffort

    func testSanitizeDowngradesXHighWhenUnsupported() {
        XCTAssertEqual(ModelCapabilityValidator.sanitizeReasoningEffort("xhigh", for: "gpt-5.1"), "high")
    }

    func testSanitizeKeepsXHighWhenSupported() {
        XCTAssertEqual(ModelCapabilityValidator.sanitizeReasoningEffort("xhigh", for: "gpt-5.2"), "xhigh")
    }

    func testSanitizeConvertsNoneToMinimalForGPT5Base() {
        XCTAssertEqual(ModelCapabilityValidator.sanitizeReasoningEffort("none", for: "gpt-5"), "minimal")
    }

    func testSanitizeConvertsMinimalToNoneForNonBaseModel() {
        XCTAssertEqual(ModelCapabilityValidator.sanitizeReasoningEffort("minimal", for: "gpt-5.1"), "none")
    }

    // MARK: - availableReasoningOptions

    func testAvailableReasoningOptionsForGPT5BaseExcludesNone() {
        let values = ModelCapabilityValidator.availableReasoningOptions(for: "gpt-5").map(\.value)
        XCTAssertFalse(values.contains("none"))
        XCTAssertTrue(values.contains("minimal"))
    }

    func testAvailableReasoningOptionsForNonBaseExcludesMinimal() {
        let values = ModelCapabilityValidator.availableReasoningOptions(for: "gpt-5.1").map(\.value)
        XCTAssertFalse(values.contains("minimal"))
        XCTAssertTrue(values.contains("none"))
    }

    func testAvailableReasoningOptionsExcludesXHighWhenUnsupported() {
        let values = ModelCapabilityValidator.availableReasoningOptions(for: "gpt-5.1").map(\.value)
        XCTAssertFalse(values.contains("xhigh"))
    }

    func testAvailableReasoningOptionsIncludesXHighWhenSupported() {
        let values = ModelCapabilityValidator.availableReasoningOptions(for: "gpt-5.2").map(\.value)
        XCTAssertTrue(values.contains("xhigh"))
    }
}
