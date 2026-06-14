//
//  ModelPricingTests.swift
//  SprungTests
//
//  Pure-logic coverage for ModelPricing's ID-normalization and lookup helpers,
//  which underpin the onboarding cost estimator. normalize / familyAndVersion /
//  isVersion / price(for:in:) / costUSD are all pure functions.
//

import XCTest
@testable import Sprung

final class ModelPricingTests: XCTestCase {

    // MARK: - normalize

    func testNormalizeStripsVendorPrefix() {
        XCTAssertEqual(ModelPricing.normalize("anthropic/claude-sonnet-4.6"), "claude-sonnet-4-6")
    }

    func testNormalizeStripsVariantSuffix() {
        XCTAssertEqual(ModelPricing.normalize("claude-haiku-4-5:thinking"), "claude-haiku-4-5")
    }

    func testNormalizeStripsDatedSnapshot() {
        XCTAssertEqual(ModelPricing.normalize("claude-haiku-4-5-20251001"), "claude-haiku-4-5")
    }

    func testNormalizeLowercasesAndConvertsDots() {
        XCTAssertEqual(ModelPricing.normalize("Claude-Opus-4.8"), "claude-opus-4-8")
    }

    func testNormalizeCombinedTransforms() {
        XCTAssertEqual(
            ModelPricing.normalize("Anthropic/Claude-Sonnet-4.6:free"),
            "claude-sonnet-4-6"
        )
    }

    // MARK: - familyAndVersion

    func testFamilyAndVersionParsesFamilyFirstOrdering() {
        let parsed = ModelPricing.familyAndVersion("claude-opus-4-8")
        XCTAssertEqual(parsed?.family, "opus")
        XCTAssertEqual(parsed?.version, [4, 8])
    }

    func testFamilyAndVersionParsesVersionFirstOrdering() {
        let parsed = ModelPricing.familyAndVersion("claude-3-5-haiku")
        XCTAssertEqual(parsed?.family, "haiku")
        XCTAssertEqual(parsed?.version, [3, 5])
    }

    func testFamilyAndVersionReturnsNilForNonClaude() {
        XCTAssertNil(ModelPricing.familyAndVersion("gpt-4o"))
    }

    // MARK: - isVersion newerThan

    func testIsVersionGreaterFirstDifferingComponentWins() {
        XCTAssertTrue(ModelPricing.isVersion([4, 8], newerThan: [4, 6]))
        XCTAssertFalse(ModelPricing.isVersion([4, 6], newerThan: [4, 8]))
    }

    func testIsVersionLongerWinsAfterEqualPrefix() {
        // Dated snapshot ([4,5,20251001]) outranks its undated alias ([4,5]).
        XCTAssertTrue(ModelPricing.isVersion([4, 5, 20251001], newerThan: [4, 5]))
        XCTAssertFalse(ModelPricing.isVersion([4, 5], newerThan: [4, 5, 20251001]))
    }

    func testIsVersionEqualIsNotNewer() {
        XCTAssertFalse(ModelPricing.isVersion([4, 5], newerThan: [4, 5]))
    }

    // MARK: - price(for:in:)

    private static let price = ModelPrice(
        inputPerMTok: 3, outputPerMTok: 15, cacheReadPerMTok: 0.3, cacheWritePerMTok: 3.75)

    func testPriceExactMatch() {
        let table = ["anthropic/claude-sonnet-4.6": Self.price]
        XCTAssertEqual(ModelPricing.price(for: "anthropic/claude-sonnet-4.6", in: table), Self.price)
    }

    func testPriceNormalizedMatch() {
        // Table keyed by normalized id; lookup with the dated/dotted variant.
        let table = ["claude-sonnet-4-6": Self.price]
        XCTAssertEqual(ModelPricing.price(for: "anthropic/claude-sonnet-4.6", in: table), Self.price)
    }

    func testPriceFamilyVersionFallback() {
        // Neither exact nor normalized key present, but a same-family-same-version
        // entry exists under a different surface form.
        let table = ["openrouter-slug-claude-opus-4-8-special": Self.price]
        XCTAssertEqual(ModelPricing.price(for: "claude-opus-4-8", in: table), Self.price)
    }

    func testPriceReturnsNilWhenAbsent() {
        XCTAssertNil(ModelPricing.price(for: "claude-haiku-9-9", in: ["claude-opus-4-8": Self.price]))
    }

    // MARK: - costUSD

    func testCostUSDArithmetic() {
        // 1M input at $3, 0.5M output at $15, 2M read at $0.3, 1M write at $3.75.
        let cost = ModelPricing.costUSD(
            inputTokens: 1_000_000,
            outputTokens: 500_000,
            cacheReadTokens: 2_000_000,
            cacheCreationTokens: 1_000_000,
            at: Self.price)
        // = (1e6*3 + 5e5*15 + 2e6*0.3 + 1e6*3.75) / 1e6
        // = (3_000_000 + 7_500_000 + 600_000 + 3_750_000) / 1e6 = 14.85
        XCTAssertEqual(cost, 14.85, accuracy: 1e-9)
    }

    func testCostUSDZeroUsageIsZero() {
        let cost = ModelPricing.costUSD(
            inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheCreationTokens: 0,
            at: Self.price)
        XCTAssertEqual(cost, 0, accuracy: 1e-12)
    }
}
