//
//  OnboardingCostEstimator.swift
//  Sprung
//
//  Pre-run cost estimation for the onboarding budget sheet.
//
//  Converts the user's volume estimates (document pages, code size) into
//  per-operation token forecasts, then prices them with the live ModelPricing
//  table. Results are RANGES, split by billing pool (Anthropic credit vs
//  OpenRouter account), because session length and document density vary.
//
//  CALIBRATION PROVENANCE: constants are first-pass values anchored to the
//  fully instrumented 2026-06-12 onboarding session (154 requests; per-source
//  token totals from TokenUsageTracker: docs ≈ 2.2M prompt tokens for roughly
//  150 page-equivalents across all ingestion passes, git agent ≈ 2.0M prompt /
//  1.0M cache-read tokens for roughly 30 KLOC, interview ≈ 120K unique prompt
//  + 35K output post-cache-fix). Refine from telemetry as more instrumented
//  runs accumulate — every run's event dump has per-source actuals to compare
//  against these forecasts.
//

import Foundation

// MARK: - Inputs

/// The user's estimate of how much material this run will ingest.
struct OnboardingVolumes {
    /// Total pages of documents (resumes, cover letters, writing samples, reports).
    var docPages: Double
    /// Code to be scanned by the git agent, in thousands of lines.
    var codeKLOC: Double
}

// MARK: - Output

struct OnboardingCostEstimate {
    var anthropicLowUSD: Double = 0
    var anthropicHighUSD: Double = 0
    var openRouterLowUSD: Double = 0
    var openRouterHighUSD: Double = 0
    /// Operations that could not be priced (no model resolved, or model absent
    /// from the price table). Shown as a caveat, never silently dropped.
    var unpricedOperations: [OnboardingModelOperation] = []

    var totalLowUSD: Double { anthropicLowUSD + openRouterLowUSD }
    var totalHighUSD: Double { anthropicHighUSD + openRouterHighUSD }
}

// MARK: - Estimator

enum OnboardingCostEstimator {
    /// Token forecast for one operation as a function of run volume.
    /// `promptTokens*` are priced at the cache-write rate for Anthropic-billed
    /// operations (agents write content into the prompt cache once) and at the
    /// plain input rate for OpenRouter-billed operations (those paths don't
    /// assume prompt caching). `cacheRead*` price at the cache-read rate.
    struct OperationProfile {
        var fixedPromptTokens: Double = 0
        var fixedOutputTokens: Double = 0
        var fixedCacheReadTokens: Double = 0
        var promptTokensPerPage: Double = 0
        var outputTokensPerPage: Double = 0
        var cacheReadTokensPerPage: Double = 0
        var promptTokensPerKLOC: Double = 0
        var outputTokensPerKLOC: Double = 0
        var cacheReadTokensPerKLOC: Double = 0
    }

    /// Uncertainty band applied to the central forecast.
    static let lowMultiplier = 0.6
    static let highMultiplier = 1.7

    /// Calibration table — see provenance note in the file header.
    static let profiles: [OnboardingModelOperation: OperationProfile] = [
        // The conversation itself: ~120K unique prompt content per run with
        // incremental caching, plus reads that re-serve the growing prefix
        // each turn. Scales mildly with document count (upload notifications,
        // discussion turns).
        .interview: OperationProfile(
            fixedPromptTokens: 130_000,
            fixedOutputTokens: 25_000,
            fixedCacheReadTokens: 2_500_000,
            promptTokensPerPage: 1_200,
            outputTokensPerPage: 80,
            cacheReadTokensPerPage: 8_000
        ),
        // All ingestion passes over each document (summary, narrative cards,
        // skill bank, enrichment) — content written once, re-read by passes.
        .docAnalysis: OperationProfile(
            fixedPromptTokens: 20_000,
            fixedOutputTokens: 2_000,
            promptTokensPerPage: 10_000,
            outputTokensPerPage: 350,
            cacheReadTokensPerPage: 4_000
        ),
        // Post-ingestion dedupe/curation loop over generated cards.
        .cardMerge: OperationProfile(
            fixedPromptTokens: 40_000,
            fixedOutputTokens: 3_000,
            promptTokensPerPage: 1_500,
            outputTokensPerPage: 150
        ),
        // Multi-turn repository analysis: prompt volume tracks code size.
        .gitIngest: OperationProfile(
            promptTokensPerKLOC: 65_000,
            outputTokensPerKLOC: 2_500,
            cacheReadTokensPerKLOC: 33_000
        ),
        .inferenceGuidance: OperationProfile(
            fixedPromptTokens: 15_000,
            fixedOutputTokens: 2_000,
            promptTokensPerPage: 200
        ),
        .skillsProcessing: OperationProfile(
            fixedPromptTokens: 10_000,
            fixedOutputTokens: 1_000,
            promptTokensPerPage: 1_200,
            outputTokensPerPage: 100
        ),
        .skillCuration: OperationProfile(
            fixedPromptTokens: 25_000,
            fixedOutputTokens: 4_000,
            promptTokensPerPage: 400
        ),
        // One-shot voice synthesis from writing samples.
        .voiceProfile: OperationProfile(
            fixedPromptTokens: 50_000,
            fixedOutputTokens: 3_000
        ),
        // Knowledge-card fact extraction over assigned artifacts.
        .kcAgent: OperationProfile(
            fixedPromptTokens: 15_000,
            fixedOutputTokens: 1_500,
            promptTokensPerPage: 2_500,
            outputTokensPerPage: 250
        ),
        .backgroundProcessing: OperationProfile(
            fixedPromptTokens: 20_000,
            fixedOutputTokens: 1_000,
            promptTokensPerPage: 400
        ),
    ]

    /// Estimate the run cost for a set of resolved model assignments.
    /// - Parameters:
    ///   - volumes: the user's volume estimates from the sheet sliders
    ///   - modelIds: concrete model ID per operation (from a resolved preset
    ///     or from the current UserDefaults values)
    ///   - priceTable: live price table from ModelPricing
    static func estimate(
        volumes: OnboardingVolumes,
        modelIds: [OnboardingModelOperation: String],
        priceTable: [String: ModelPrice]
    ) -> OnboardingCostEstimate {
        var result = OnboardingCostEstimate()

        for operation in OnboardingModelOperation.allCases {
            guard let profile = profiles[operation] else { continue }
            guard let modelId = modelIds[operation], !modelId.isEmpty,
                  let price = ModelPricing.price(for: modelId, in: priceTable) else {
                result.unpricedOperations.append(operation)
                continue
            }

            let promptTokens = profile.fixedPromptTokens
                + profile.promptTokensPerPage * volumes.docPages
                + profile.promptTokensPerKLOC * volumes.codeKLOC
            let outputTokens = profile.fixedOutputTokens
                + profile.outputTokensPerPage * volumes.docPages
                + profile.outputTokensPerKLOC * volumes.codeKLOC
            let cacheReadTokens = profile.fixedCacheReadTokens
                + profile.cacheReadTokensPerPage * volumes.docPages
                + profile.cacheReadTokensPerKLOC * volumes.codeKLOC

            // Anthropic-billed paths cache aggressively: prompt content bills
            // once at the write rate. OpenRouter-billed paths are priced at the
            // plain input rate with no caching assumed.
            let promptRate = operation.billsToAnthropic
                ? price.cacheWritePerMTok
                : price.inputPerMTok
            let central = (promptTokens * promptRate
                + outputTokens * price.outputPerMTok
                + cacheReadTokens * price.cacheReadPerMTok) / 1_000_000

            if operation.billsToAnthropic {
                result.anthropicLowUSD += central * lowMultiplier
                result.anthropicHighUSD += central * highMultiplier
            } else {
                result.openRouterLowUSD += central * lowMultiplier
                result.openRouterHighUSD += central * highMultiplier
            }
        }

        return result
    }

    /// Current model assignments straight from UserDefaults — used to estimate
    /// the "keep current settings" path.
    static func currentModelIds() -> [OnboardingModelOperation: String] {
        var ids: [OnboardingModelOperation: String] = [:]
        for operation in OnboardingModelOperation.allCases {
            let value = UserDefaults.standard.string(forKey: operation.defaultsKey) ?? ""
            if !value.isEmpty {
                ids[operation] = value
            }
        }
        return ids
    }

    /// Compact display string for an estimate range, e.g. "$9–15".
    static func formatRange(lowUSD: Double, highUSD: Double) -> String {
        let low = max(0, lowUSD)
        let high = max(low, highUSD)
        if high < 1 {
            return String(format: "$%.2f–%.2f", low, high)
        }
        return "$\(Int(low.rounded()))–\(Int(high.rounded()))"
    }
}
