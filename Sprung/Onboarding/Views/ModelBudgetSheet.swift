//
//  ModelBudgetSheet.swift
//  Sprung
//
//  Pre-run budget chooser shown before every onboarding interview start.
//  Presents three family-based presets (resolved against live model lists),
//  volume sliders that drive a live cost estimate, and an always-available
//  "keep current settings" path. Nothing is written until the user confirms;
//  prices come from a live fetch and are stamped with their date.
//

import SwiftUI
import SwiftOpenAI

struct ModelBudgetSheet: View {
    let llmFacade: LLMFacade
    let openRouterService: OpenRouterService
    /// Called after the user confirms (preset applied or current settings kept).
    let onProceed: () -> Void
    /// Opens the full model settings (sheet stays up; user proceeds when ready).
    let onOpenSettings: () -> Void
    let onCancel: () -> Void

    // Volume estimates persist between runs — most users re-run with similar material.
    @AppStorage("onboardingBudgetDocPages") private var docPages: Double = 60
    @AppStorage("onboardingBudgetCodeKLOC") private var codeKLOC: Double = 20

    @State private var anthropicModels: [AnthropicModel] = []
    @State private var priceTable: [String: ModelPrice] = [:]
    @State private var pricesAsOf: Date?
    @State private var resolvedPresets: [ResolvedModelPreset] = []
    @State private var selectedPresetId: String?
    @State private var isLoading = true
    @State private var loadError: String?

    private var volumes: OnboardingVolumes {
        OnboardingVolumes(docPages: docPages, codeKLOC: codeKLOC)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            volumeSliders
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView("Loading models and prices…")
                    Spacer()
                }
                .frame(minHeight: 180)
            } else {
                presetCards
                if let loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            Divider()
            footerButtons
            footnote
        }
        .padding(24)
        .frame(width: 760)
        .task { await load() }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Set your AI budget for this run")
                .font(.title2.bold())
            Text("Pick a preset to apply these models to all onboarding operations, or keep what you have. Estimates update with your volume settings below.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var volumeSliders: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("Documents")
                    .frame(width: 90, alignment: .leading)
                Slider(value: $docPages, in: 0...500, step: 5)
                Text(docPagesCaption)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 130, alignment: .trailing)
            }
            HStack(spacing: 12) {
                Text("Code")
                    .frame(width: 90, alignment: .leading)
                Slider(value: $codeKLOC, in: 0...100, step: 2.5)
                Text(codeCaption)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 130, alignment: .trailing)
            }
        }
    }

    private var docPagesCaption: String {
        docPages < 1 ? "none" : "≈ \(Int(docPages)) pages"
    }

    private var codeCaption: String {
        codeKLOC < 1 ? "none" : "≈ \(Int(codeKLOC * 1000)) lines"
    }

    private var presetCards: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(resolvedPresets, id: \.preset.id) { resolved in
                presetCard(resolved)
            }
        }
    }

    private func presetCard(_ resolved: ResolvedModelPreset) -> some View {
        let isSelected = selectedPresetId == resolved.preset.id
        let estimate = OnboardingCostEstimator.estimate(
            volumes: volumes,
            modelIds: resolved.modelIds,
            priceTable: priceTable
        )
        return Button {
            selectedPresetId = resolved.preset.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(resolved.preset.title)
                    .font(.headline)
                Text(estimateText(estimate))
                    .font(.title3.bold().monospacedDigit())
                Text(poolSplitText(estimate))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(resolved.preset.tagline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                keyModelLines(resolved)
                if !resolved.unresolved.isEmpty {
                    Label(
                        "No live model for: \(resolved.unresolved.map(\.displayName).joined(separator: ", "))",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption2)
                    .foregroundStyle(.orange)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// The four Anthropic-billed assignments are the cost story — show those;
    /// OpenRouter services are summarized on one line.
    private func keyModelLines(_ resolved: ResolvedModelPreset) -> some View {
        let keyOperations: [OnboardingModelOperation] = [.interview, .docAnalysis, .cardMerge, .gitIngest]
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(keyOperations) { operation in
                if let name = resolved.displayNames[operation] {
                    HStack(spacing: 4) {
                        Text(operation.displayName)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(name)
                    }
                    .font(.caption2)
                }
            }
            if let family = resolved.preset.assignments[.kcAgent] {
                HStack(spacing: 4) {
                    Text("Support services")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text("\(family.displayName)-class via OpenRouter")
                }
                .font(.caption2)
            }
        }
    }

    private func estimateText(_ estimate: OnboardingCostEstimate) -> String {
        guard !priceTable.isEmpty else { return "estimate unavailable" }
        return "≈ " + OnboardingCostEstimator.formatRange(
            lowUSD: estimate.totalLowUSD,
            highUSD: estimate.totalHighUSD
        )
    }

    private func poolSplitText(_ estimate: OnboardingCostEstimate) -> String {
        guard !priceTable.isEmpty else { return " " }
        let anthropic = OnboardingCostEstimator.formatRange(
            lowUSD: estimate.anthropicLowUSD, highUSD: estimate.anthropicHighUSD
        )
        let openRouter = OnboardingCostEstimator.formatRange(
            lowUSD: estimate.openRouterLowUSD, highUSD: estimate.openRouterHighUSD
        )
        return "Anthropic \(anthropic) · OpenRouter \(openRouter)"
    }

    private var footerButtons: some View {
        HStack(spacing: 12) {
            Button("Cancel", role: .cancel, action: onCancel)
            Button("Customize in Settings…", action: onOpenSettings)
            Spacer()
            Button(keepCurrentTitle) { onProceed() }
            Button(applyTitle) {
                if let resolved = resolvedPresets.first(where: { $0.preset.id == selectedPresetId }) {
                    resolved.apply()
                }
                onProceed()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selectedPresetId == nil)
        }
    }

    private var keepCurrentTitle: String {
        let estimate = OnboardingCostEstimator.estimate(
            volumes: volumes,
            modelIds: OnboardingCostEstimator.currentModelIds(),
            priceTable: priceTable
        )
        guard !priceTable.isEmpty, estimate.totalHighUSD > 0 else {
            return "Keep Current Settings & Start"
        }
        let range = OnboardingCostEstimator.formatRange(
            lowUSD: estimate.totalLowUSD, highUSD: estimate.totalHighUSD
        )
        return "Keep Current (≈ \(range)) & Start"
    }

    private var applyTitle: String {
        guard let selectedPresetId,
              let resolved = resolvedPresets.first(where: { $0.preset.id == selectedPresetId }) else {
            return "Apply & Start"
        }
        return "Apply \(resolved.preset.title) & Start"
    }

    private var footnote: some View {
        Text(footnoteText)
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    private var footnoteText: String {
        var parts: [String] = [
            "Estimates are ranges based on list prices and your volume inputs; actual cost depends on session length and document density."
        ]
        if let pricesAsOf {
            parts.append("Prices as of \(pricesAsOf.formatted(date: .abbreviated, time: .shortened)).")
        } else {
            parts.append("Live prices unavailable — estimates hidden.")
        }
        parts.append("Anthropic and OpenRouter operations bill separate accounts.")
        return parts.joined(separator: " ")
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        // Anthropic model list (required to resolve the Anthropic-billed ops).
        do {
            let response = try await llmFacade.anthropicListModels()
            anthropicModels = response.data
        } catch {
            loadError = "Could not load Anthropic models: \(error.localizedDescription)"
            Logger.warning("💰 Budget sheet: Anthropic model list failed: \(error)", category: .ai)
        }

        // OpenRouter list doubles as the live price source. The service caches
        // for an hour; fetch only when empty.
        if openRouterService.availableModels.isEmpty {
            await openRouterService.fetchModels()
        }
        let openRouterModels = openRouterService.availableModels

        if !openRouterModels.isEmpty {
            priceTable = ModelPricing.buildTable(from: openRouterModels)
            ModelPricing.persistTable(priceTable)
            pricesAsOf = Date()
        } else if let persisted = ModelPricing.loadPersistedTable() {
            priceTable = persisted.table
            pricesAsOf = persisted.asOf
            Logger.warning("💰 Budget sheet: using persisted price table from \(persisted.asOf)", category: .ai)
        }

        resolvedPresets = OnboardingModelPreset.all.map {
            ModelPresetCatalog.resolve(
                $0,
                anthropicModels: anthropicModels,
                openRouterModels: openRouterModels
            )
        }
        if selectedPresetId == nil {
            selectedPresetId = OnboardingModelPreset.balanced.id
        }
    }
}
