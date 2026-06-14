//
//  OnboardingCostEstimatorTests.swift
//  SprungTests
//
//  Pure-logic coverage for OnboardingCostEstimator.estimate: volumes -> cost
//  bands, per-pool (Anthropic vs OpenRouter) split, unpriced-operation tracking,
//  uncertainty multipliers, and zero/large edges. Plus the formatRange helper.
//

import XCTest
@testable import Sprung

final class OnboardingCostEstimatorTests: XCTestCase {

    /// A flat price table: every model id resolves to the same simple price so
    /// arithmetic is hand-checkable. $1 input, $2 output, $0.1 read, $1.25 write
    /// per million tokens.
    private static let flatPrice = ModelPrice(
        inputPerMTok: 1.0,
        outputPerMTok: 2.0,
        cacheReadPerMTok: 0.1,
        cacheWritePerMTok: 1.25
    )

    /// Build a model-id map assigning a distinct id per operation, all priced via
    /// the flat table below.
    private func allOpsModelIds() -> [OnboardingModelOperation: String] {
        var ids: [OnboardingModelOperation: String] = [:]
        for op in OnboardingModelOperation.allCases {
            ids[op] = "model-\(op.rawValue)"
        }
        return ids
    }

    private func flatTable(for ids: [OnboardingModelOperation: String]) -> [String: ModelPrice] {
        var table: [String: ModelPrice] = [:]
        for id in ids.values { table[id] = Self.flatPrice }
        return table
    }

    // MARK: - Unpriced operations

    func testAllOperationsUnpricedWhenTableEmpty() {
        let ids = allOpsModelIds()
        let estimate = OnboardingCostEstimator.estimate(
            volumes: OnboardingVolumes(docPages: 10, codeKLOC: 5),
            modelIds: ids,
            priceTable: [:]
        )
        XCTAssertEqual(Set(estimate.unpricedOperations), Set(OnboardingModelOperation.allCases),
                       "with no prices, every profiled op must be reported unpriced")
        XCTAssertEqual(estimate.totalLowUSD, 0, accuracy: 1e-9)
        XCTAssertEqual(estimate.totalHighUSD, 0, accuracy: 1e-9)
    }

    func testMissingModelIdIsUnpriced() {
        // Provide a table but omit one operation's id entirely.
        var ids = allOpsModelIds()
        ids[.interview] = nil
        let estimate = OnboardingCostEstimator.estimate(
            volumes: OnboardingVolumes(docPages: 0, codeKLOC: 0),
            modelIds: ids,
            priceTable: flatTable(for: ids)
        )
        XCTAssertTrue(estimate.unpricedOperations.contains(.interview),
                      "an operation with no model id must be unpriced")
        XCTAssertFalse(estimate.unpricedOperations.contains(.docAnalysis))
    }

    func testEmptyModelIdStringIsUnpriced() {
        var ids = allOpsModelIds()
        ids[.gitIngest] = ""
        let estimate = OnboardingCostEstimator.estimate(
            volumes: OnboardingVolumes(docPages: 0, codeKLOC: 0),
            modelIds: ids,
            priceTable: flatTable(for: ids)
        )
        XCTAssertTrue(estimate.unpricedOperations.contains(.gitIngest),
                      "an empty model id must be treated as unpriced, never substituted")
    }

    // MARK: - Pool split (Anthropic vs OpenRouter)

    func testCostsSplitByBillingPool() {
        let ids = allOpsModelIds()
        let estimate = OnboardingCostEstimator.estimate(
            volumes: OnboardingVolumes(docPages: 1, codeKLOC: 1),
            modelIds: ids,
            priceTable: flatTable(for: ids)
        )
        XCTAssertTrue(estimate.unpricedOperations.isEmpty, "all ops should be priced")
        // Both pools have profiled, billable operations -> both > 0.
        XCTAssertGreaterThan(estimate.anthropicHighUSD, 0)
        XCTAssertGreaterThan(estimate.openRouterHighUSD, 0)
        XCTAssertEqual(estimate.totalLowUSD,
                       estimate.anthropicLowUSD + estimate.openRouterLowUSD, accuracy: 1e-9)
        XCTAssertEqual(estimate.totalHighUSD,
                       estimate.anthropicHighUSD + estimate.openRouterHighUSD, accuracy: 1e-9)
    }

    // MARK: - Uncertainty multipliers

    func testLowAndHighFollowMultiplierRatio() {
        let ids = allOpsModelIds()
        let estimate = OnboardingCostEstimator.estimate(
            volumes: OnboardingVolumes(docPages: 3, codeKLOC: 2),
            modelIds: ids,
            priceTable: flatTable(for: ids)
        )
        // Each pool's low/high derive from the same central via fixed multipliers,
        // so high/low == highMultiplier/lowMultiplier exactly.
        let expectedRatio = OnboardingCostEstimator.highMultiplier / OnboardingCostEstimator.lowMultiplier
        XCTAssertGreaterThan(estimate.totalLowUSD, 0)
        XCTAssertEqual(estimate.totalHighUSD / estimate.totalLowUSD, expectedRatio, accuracy: 1e-6,
                       "the band ratio must equal high/low multiplier ratio")
        XCTAssertLessThan(estimate.totalLowUSD, estimate.totalHighUSD)
    }

    // MARK: - Hand-checked single operation

    func testSingleAnthropicOperationArithmetic() {
        // Isolate one Anthropic-billed op (.voiceProfile is OpenRouter; use .cardMerge,
        // which has only fixed tokens beyond per-page so zero volume gives a clean number).
        // cardMerge: fixedPrompt 40_000, fixedOutput 3_000, no cacheRead fixed.
        let op = OnboardingModelOperation.cardMerge
        XCTAssertTrue(op.billsToAnthropic)
        let ids: [OnboardingModelOperation: String] = [op: "the-model"]
        let table = ["the-model": Self.flatPrice]
        let estimate = OnboardingCostEstimator.estimate(
            volumes: OnboardingVolumes(docPages: 0, codeKLOC: 0),
            modelIds: ids,
            priceTable: table
        )
        // promptTokens=40_000 at cacheWrite 1.25/MTok; output=3_000 at 2.0/MTok.
        // central = (40_000*1.25 + 3_000*2.0 + 0) / 1_000_000 = (50_000 + 6_000)/1e6 = 0.056
        let central = (40_000.0 * 1.25 + 3_000.0 * 2.0) / 1_000_000.0
        XCTAssertEqual(estimate.anthropicLowUSD, central * OnboardingCostEstimator.lowMultiplier, accuracy: 1e-9)
        XCTAssertEqual(estimate.anthropicHighUSD, central * OnboardingCostEstimator.highMultiplier, accuracy: 1e-9)
        XCTAssertEqual(estimate.openRouterLowUSD, 0, accuracy: 1e-9)
    }

    func testSingleOpenRouterOperationUsesInputRateNotCacheWrite() {
        // .skillsProcessing bills to OpenRouter -> prompt priced at inputPerMTok (1.0),
        // NOT cacheWritePerMTok. fixedPrompt 10_000, fixedOutput 1_000.
        let op = OnboardingModelOperation.skillsProcessing
        XCTAssertFalse(op.billsToAnthropic)
        let ids: [OnboardingModelOperation: String] = [op: "or-model"]
        let table = ["or-model": Self.flatPrice]
        let estimate = OnboardingCostEstimator.estimate(
            volumes: OnboardingVolumes(docPages: 0, codeKLOC: 0),
            modelIds: ids,
            priceTable: table
        )
        // central = (10_000*1.0 + 1_000*2.0) / 1e6 = 12_000/1e6 = 0.012
        let central = (10_000.0 * 1.0 + 1_000.0 * 2.0) / 1_000_000.0
        XCTAssertEqual(estimate.openRouterLowUSD, central * OnboardingCostEstimator.lowMultiplier, accuracy: 1e-9)
        XCTAssertEqual(estimate.anthropicLowUSD, 0, accuracy: 1e-9)
    }

    // MARK: - Volume scaling

    func testCostScalesMonotonicallyWithVolume() {
        let ids = allOpsModelIds()
        let table = flatTable(for: ids)
        let small = OnboardingCostEstimator.estimate(
            volumes: OnboardingVolumes(docPages: 1, codeKLOC: 1),
            modelIds: ids, priceTable: table)
        let large = OnboardingCostEstimator.estimate(
            volumes: OnboardingVolumes(docPages: 100, codeKLOC: 50),
            modelIds: ids, priceTable: table)
        XCTAssertGreaterThan(large.totalHighUSD, small.totalHighUSD,
                             "more volume must cost more")
    }

    func testZeroVolumeStillHasFixedCosts() {
        let ids = allOpsModelIds()
        let estimate = OnboardingCostEstimator.estimate(
            volumes: OnboardingVolumes(docPages: 0, codeKLOC: 0),
            modelIds: ids, priceTable: flatTable(for: ids))
        // Several ops have fixed token costs independent of volume.
        XCTAssertGreaterThan(estimate.totalHighUSD, 0,
                             "fixed token costs apply even at zero volume")
    }

    // MARK: - formatRange

    func testFormatRangeIntegerDollars() {
        XCTAssertEqual(OnboardingCostEstimator.formatRange(lowUSD: 9, highUSD: 15), "$9–15")
    }

    func testFormatRangeRoundsToNearestInteger() {
        XCTAssertEqual(OnboardingCostEstimator.formatRange(lowUSD: 8.6, highUSD: 14.4), "$9–14")
    }

    func testFormatRangeSubDollarUsesCents() {
        XCTAssertEqual(OnboardingCostEstimator.formatRange(lowUSD: 0.10, highUSD: 0.25), "$0.10–0.25")
    }

    func testFormatRangeClampsNegativeLowToZero() {
        XCTAssertEqual(OnboardingCostEstimator.formatRange(lowUSD: -5, highUSD: 3), "$0–3")
    }

    func testFormatRangeClampsHighBelowLow() {
        // high < low -> high is raised to low.
        XCTAssertEqual(OnboardingCostEstimator.formatRange(lowUSD: 10, highUSD: 2), "$10–10")
    }
}
