//
//  ModelBudgetSheet.swift
//  Sprung
//
//  Pre-run budget chooser shown before every onboarding interview start.
//  Presents three family-based presets (resolved against live model lists) plus
//  the user's current saved settings as a fourth, equally-selectable option, two
//  volume sliders that drive a live cost estimate, and a single Start action.
//  Nothing is written until the user confirms; prices come from a live fetch and
//  are stamped with their date.
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

    /// What the user has selected to run with — a named preset or their current
    /// saved settings. The Start button applies a preset (and no-ops for current).
    private enum BudgetChoice: Equatable {
        case preset(String)
        case current
    }

    // Volume estimates persist between runs — most users re-run with similar material.
    @AppStorage("onboardingBudgetDocPages") private var docPages: Double = 60
    @AppStorage("onboardingBudgetCodeKLOC") private var codeKLOC: Double = 20

    @State private var anthropicModels: [AnthropicModel] = []
    @State private var openRouterModels: [OpenRouterModel] = []
    @State private var priceTable: [String: ModelPrice] = [:]
    @State private var pricesAsOf: Date?
    @State private var resolvedPresets: [ResolvedModelPreset] = []
    @State private var selection: BudgetChoice = .preset(OnboardingModelPreset.balanced.id)
    @State private var isLoading = true
    @State private var loadError: String?

    private var volumes: OnboardingVolumes {
        OnboardingVolumes(docPages: docPages, codeKLOC: codeKLOC)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
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
                currentCard
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
        .frame(width: 720)
        .task { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Set your AI budget for this run")
                .font(.title2.bold())
            Text("Pick a preset to apply these models to all onboarding operations, or keep your current settings. Estimates update with the volume sliders.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Volume sliders

    private var volumeSliders: some View {
        VStack(alignment: .leading, spacing: 8) {
            sliderRow(title: "Documents", value: $docPages, range: 0...500, caption: docPagesCaption)
            sliderRow(title: "Code", value: $codeKLOC, range: 0...100, caption: codeCaption)
        }
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        caption: String
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(width: 80, alignment: .leading)
            Slider(value: value, in: range)
                .frame(width: 220)
            Text(caption)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private var docPagesCaption: String {
        docPages < 1 ? "none" : "≈ \(Int((docPages / 5).rounded()) * 5) pages"
    }

    private var codeCaption: String {
        codeKLOC < 1 ? "none" : "≈ \(Int(codeKLOC.rounded()))K lines"
    }

    // MARK: - Preset cards

    private var presetCards: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(resolvedPresets, id: \.preset.id) { resolved in
                presetCard(resolved)
            }
        }
    }

    private func presetCard(_ resolved: ResolvedModelPreset) -> some View {
        let isSelected = selection == .preset(resolved.preset.id)
        let estimate = OnboardingCostEstimator.estimate(
            volumes: volumes,
            modelIds: resolved.modelIds,
            priceTable: priceTable
        )
        return Button {
            selection = .preset(resolved.preset.id)
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
                modelLines(
                    names: resolved.displayNames,
                    support: resolved.preset.assignments[.kcAgent]
                        .map { "\($0.displayName)-class" }
                )
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
            .background(cardBackground(isSelected: isSelected))
            .overlay(cardBorder(isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Current-settings card

    private var currentCard: some View {
        let isSelected = selection == .current
        let estimate = OnboardingCostEstimator.estimate(
            volumes: volumes,
            modelIds: OnboardingCostEstimator.currentModelIds(),
            priceTable: priceTable
        )
        let names = currentDisplayNames
        return Button {
            selection = .current
        } label: {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Current settings")
                        .font(.headline)
                    Text(estimateText(estimate))
                        .font(.title3.bold().monospacedDigit())
                    Text(poolSplitText(estimate))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("Your saved model choices, applied as-is.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 240, alignment: .leading)

                Divider()

                if names.isEmpty {
                    Label("No models configured yet — open Settings to choose.", systemImage: "slider.horizontal.3")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    modelLines(names: names, support: currentSupportText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground(isSelected: isSelected))
            .overlay(cardBorder(isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared card pieces

    /// The four Anthropic-billed assignments are the cost story — show those;
    /// OpenRouter services are summarized on one line.
    private func modelLines(
        names: [OnboardingModelOperation: String],
        support: String?
    ) -> some View {
        let keyOperations: [OnboardingModelOperation] = [.interview, .docAnalysis, .cardMerge, .gitIngest]
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(keyOperations) { operation in
                if let name = names[operation] {
                    modelRow(operation.displayName, name)
                }
            }
            if let support {
                modelRow("Support", "\(support) · OpenRouter")
            }
        }
    }

    private func modelRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.caption2)
    }

    private func cardBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
    }

    private func cardBorder(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(
                isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
                lineWidth: isSelected ? 2 : 1
            )
    }

    // MARK: - Current-model resolution

    /// Current per-operation model display names for the four key (Anthropic-billed)
    /// operations, resolved from the live lists the settings pickers use.
    private var currentDisplayNames: [OnboardingModelOperation: String] {
        let keyOperations: [OnboardingModelOperation] = [.interview, .docAnalysis, .cardMerge, .gitIngest]
        var out: [OnboardingModelOperation: String] = [:]
        for operation in keyOperations {
            if let name = currentDisplayName(for: operation) {
                out[operation] = name
            }
        }
        return out
    }

    private func currentDisplayName(for operation: OnboardingModelOperation) -> String? {
        guard let id = OnboardingCostEstimator.currentModelIds()[operation], !id.isEmpty else { return nil }
        if let model = anthropicModels.first(where: { $0.id == id }) { return model.displayName }
        if let model = openRouterModels.first(where: { $0.id == id }) { return model.displayName }
        // Fallback: a model the user picked that's no longer in the live list —
        // strip any provider prefix so it's at least legible.
        return ModelId(id).strippingProvider("anthropic")
    }

    /// Family summary for the current OpenRouter support services, mirroring the
    /// presets' "Sonnet-class" line.
    private var currentSupportText: String? {
        guard let id = OnboardingCostEstimator.currentModelIds()[.kcAgent], !id.isEmpty else { return nil }
        if let familyVersion = ModelPricing.familyAndVersion(ModelPricing.normalize(id)) {
            return "\(familyVersion.family.capitalized)-class"
        }
        return openRouterModels.first(where: { $0.id == id })?.displayName
    }

    // MARK: - Estimate formatting

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

    // MARK: - Footer

    private var footerButtons: some View {
        HStack(spacing: 12) {
            Button("Cancel", role: .cancel, action: onCancel)
            Button("Customize in Settings…", action: onOpenSettings)
            Spacer()
            Button("Start Interview", action: startSelected)
                .keyboardShortcut(.defaultAction)
                .disabled(isLoading)
        }
    }

    /// Apply the selected preset (current settings are kept as-is) then proceed.
    private func startSelected() {
        if case .preset(let id) = selection,
           let resolved = resolvedPresets.first(where: { $0.preset.id == id }) {
            resolved.apply()
        }
        onProceed()
    }

    private var footnote: some View {
        Text(footnoteText)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
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
        openRouterModels = openRouterService.availableModels

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
    }
}
