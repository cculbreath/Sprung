//
//  APIKeysSettingsView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/24/25.
//

import SwiftUI

struct APIKeysSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(EnabledLLMStore.self) private var enabledLLMStore

    @AppStorage("scrapingDogApiKey") private var scrapingDogApiKey: String = "none"
    @AppStorage("openRouterApiKey") private var openRouterApiKey: String = ""
    @AppStorage("openAiTTSApiKey") private var openAiTTSApiKey: String = "none"

    @State private var showModelSelectionSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Manage credentials used for importing jobs and accessing external AI services. Leave a field blank to remove the saved key.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            APIKeyEditor(
                title: "OpenRouter",
                systemImage: "globe",
                value: $openRouterApiKey,
                placeholder: "sk-or-…",
                help: "Required for multi-model résumé reasoning and OpenRouter integrations.",
                onSave: handleOpenRouterSave
            )

            APIKeyEditor(
                title: "Scraping Dog",
                systemImage: "dog.fill",
                value: $scrapingDogApiKey,
                placeholder: "sdg-…",
                help: "Optional fallback scraper for LinkedIn job imports.",
                normalizesNoneValue: true
            )

            APIKeyEditor(
                title: "OpenAI (Voice)",
                systemImage: "speaker.wave.2",
                value: $openAiTTSApiKey,
                placeholder: "sk-…",
                help: "Used for text-to-speech previews when narrating résumés.",
                normalizesNoneValue: true,
                onSave: handleOpenAITTSSave
            )

            Divider()

            HStack(spacing: 12) {
                Button("Choose OpenRouter Models…") {
                    appState.reconfigureOpenRouterService()
                    showModelSelectionSheet = true
                }
                .disabled(!appState.hasValidOpenRouterKey)

                if appState.hasValidOpenRouterKey {
                    Label(
                        "\(appState.openRouterService.availableModels.count) available, \(enabledLLMStore.enabledModelIds.count) selected",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                    .symbolRenderingMode(.hierarchical)
                } else {
                    Label("OpenRouter key required", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                        .symbolRenderingMode(.hierarchical)
                }
            }
        }
        .sheet(isPresented: $showModelSelectionSheet) {
            OpenRouterModelSelectionSheet()
                .environment(appState)
        }
    }

    private func handleOpenRouterSave(_ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            APIKeyManager.delete(.openRouter)
            openRouterApiKey = ""
        } else {
            _ = APIKeyManager.set(.openRouter, value: trimmed)
            openRouterApiKey = trimmed
        }

        appState.reconfigureOpenRouterService()
        NotificationCenter.default.post(name: .apiKeysChanged, object: nil)
    }

    private func handleOpenAITTSSave(_ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            APIKeyManager.delete(.openAI)
            openAiTTSApiKey = "none"
        } else {
            _ = APIKeyManager.set(.openAI, value: trimmed)
            openAiTTSApiKey = trimmed
        }
        NotificationCenter.default.post(name: .apiKeysChanged, object: nil)
    }
}

private struct APIKeyEditor: View {
    let title: String
    let systemImage: String
    @Binding var value: String
    var placeholder: String = "API Key"
    var help: String?
    var normalizesNoneValue: Bool = false
    var onSave: ((String) -> Void)?

    @State private var isEditing = false
    @State private var draft: String = ""

    private var displayValue: String {
        normalizesNoneValue && value == "none" ? "" : value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: systemImage)
                    .labelStyle(.titleAndIcon)

                Spacer()

                if isEditing {
                    HStack(spacing: 8) {
                        Button("Save") {
                            commit()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Cancel") {
                            cancel()
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Button("Edit") {
                        startEditing()
                    }
                    .buttonStyle(.link)
                }
            }

            if isEditing {
                SecureField(placeholder, text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        commit()
                    }
            } else if !displayValue.isEmpty {
                Text(mask(displayValue))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Not configured")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }

            if let help {
                Text(help)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func startEditing() {
        draft = displayValue
        isEditing = true
    }

    private func cancel() {
        isEditing = false
        draft = displayValue
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = trimmed.isEmpty && normalizesNoneValue ? "none" : trimmed

        value = stored
        onSave?(trimmed)
        isEditing = false
    }

    private func mask(_ raw: String) -> String {
        guard raw.count > 8 else { return raw }
        let prefix = raw.prefix(4)
        let suffix = raw.suffix(4)
        return "\(prefix)…\(suffix)"
    }
}
