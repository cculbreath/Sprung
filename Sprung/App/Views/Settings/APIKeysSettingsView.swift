//
//  APIKeysSettingsView.swift
//  Sprung
//
//
import SwiftUI
struct APIKeysSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(EnabledLLMStore.self) private var enabledLLMStore
    @Environment(_LLMService.self) private var llmService
    @Environment(OpenRouterService.self) private var openRouterService: OpenRouterService
    @State private var openRouterApiKey: String = APIKeyManager.get(.openRouter) ?? ""
    @State private var openAiTTSApiKey: String = APIKeyManager.get(.openAI) ?? ""
    @State private var geminiApiKey: String = APIKeyManager.get(.gemini) ?? ""
    @State private var showModelSelectionSheet = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Manage credentials used for importing jobs and accessing external AI services. Leave a field blank to remove the saved key.")
                .font(.callout)
                .foregroundStyle(.secondary)
            APIKeyEditor(
                title: "OpenRouter",
                systemImage: "globe",
                value: $openRouterApiKey,
                placeholder: "sk-or-…",
                help: "Required for multi-model résumé reasoning and OpenRouter integrations.",
                testEndpoint: .openRouter,
                onSave: handleOpenRouterSave
            )
            APIKeyEditor(
                title: "OpenAI (Voice and Onboarding Interview)",
                systemImage: "speaker.wave.2",
                value: $openAiTTSApiKey,
                placeholder: "sk-…",
                help: "Used for text-to-speech previews and onboarding interview conversations.",
                testEndpoint: .openAI,
                onSave: handleOpenAITTSSave
            )
            APIKeyEditor(
                title: "Google Gemini (PDF Extraction)",
                systemImage: "doc.viewfinder",
                value: $geminiApiKey,
                placeholder: "AIza…",
                help: "Used for native PDF extraction via Google's Files API. Handles large PDFs up to 2GB.",
                testEndpoint: .gemini,
                onSave: handleGeminiSave
            )
            Divider()
            HStack(spacing: 12) {
                Button("Choose OpenRouter Models…") {
                    appState.reconfigureOpenRouterService(using: llmService)
                    showModelSelectionSheet = true
                }
                .buttonStyle(.bordered)
                .disabled(!appState.hasValidOpenRouterKey)
                if appState.hasValidOpenRouterKey {
                    Label(
                        "\(openRouterService.availableModels.count) available, \(enabledLLMStore.enabledModelIds.count) selected",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                    .symbolRenderingMode(.hierarchical)
                } else {
                    Label("OpenRouter key required", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
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
        .task {
            refreshKeys()
        }
        .onReceive(NotificationCenter.default.publisher(for: .apiKeysChanged)) { _ in
            refreshKeys()
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
        appState.reconfigureOpenRouterService(using: llmService)
        NotificationCenter.default.post(name: .apiKeysChanged, object: nil)
    }
    private func handleOpenAITTSSave(_ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            APIKeyManager.delete(.openAI)
            openAiTTSApiKey = ""
        } else {
            _ = APIKeyManager.set(.openAI, value: trimmed)
            openAiTTSApiKey = trimmed
        }
        NotificationCenter.default.post(name: .apiKeysChanged, object: nil)
    }
    private func handleGeminiSave(_ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            APIKeyManager.delete(.gemini)
            geminiApiKey = ""
        } else {
            _ = APIKeyManager.set(.gemini, value: trimmed)
            geminiApiKey = trimmed
        }
        NotificationCenter.default.post(name: .apiKeysChanged, object: nil)
    }
    private func refreshKeys() {
        openRouterApiKey = APIKeyManager.get(.openRouter) ?? ""
        openAiTTSApiKey = APIKeyManager.get(.openAI) ?? ""
        geminiApiKey = APIKeyManager.get(.gemini) ?? ""
    }
}

// MARK: - API Test Endpoint
enum APITestEndpoint {
    case openRouter
    case openAI
    case gemini

    var testURL: URL {
        switch self {
        case .openRouter:
            return URL(string: "https://openrouter.ai/api/v1/models")!
        case .openAI:
            return URL(string: "https://api.openai.com/v1/models")!
        case .gemini:
            return URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!
        }
    }

    func buildRequest(apiKey: String) -> URLRequest {
        var request = URLRequest(url: testURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        switch self {
        case .openRouter:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .openAI:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .gemini:
            // Gemini uses query parameter for API key
            var components = URLComponents(url: testURL, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
            request.url = components.url
        }
        return request
    }
}

// MARK: - Test Result
enum APIKeyTestResult: Equatable {
    case idle
    case testing
    case valid
    case invalid(String)

    var icon: String {
        switch self {
        case .idle: return ""
        case .testing: return ""
        case .valid: return "checkmark.circle.fill"
        case .invalid: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .idle: return .secondary
        case .testing: return .secondary
        case .valid: return .green
        case .invalid: return .red
        }
    }
}

// MARK: - API Key Editor
private struct APIKeyEditor: View {
    let title: String
    let systemImage: String
    @Binding var value: String
    var placeholder: String = "API Key"
    var help: String?
    var testEndpoint: APITestEndpoint?
    var onSave: ((String) -> Void)?
    @State private var isEditing = false
    @State private var draft: String = ""
    @State private var testResult: APIKeyTestResult = .idle
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: systemImage)
                    .labelStyle(.titleAndIcon)
                    .font(.headline)
                Spacer()
                if isEditing {
                    HStack(spacing: 8) {
                        Button("Save") {
                            commit()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        Button("Cancel") {
                            cancel()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } else {
                    HStack(spacing: 8) {
                        if testEndpoint != nil && !value.isEmpty {
                            testButton
                        }
                        Button("Edit") {
                            startEditing()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            if isEditing {
                TextField(placeholder, text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit {
                        commit()
                    }
            } else if !value.isEmpty {
                HStack(spacing: 8) {
                    Text(mask(value))
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                    testResultIndicator
                }
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
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var testButton: some View {
        Button {
            Task { await testAPIKey() }
        } label: {
            if case .testing = testResult {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text("Test")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(value.isEmpty || testResult == .testing)
    }

    @ViewBuilder
    private var testResultIndicator: some View {
        switch testResult {
        case .idle:
            EmptyView()
        case .testing:
            EmptyView()
        case .valid:
            Label("Valid", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
        case .invalid(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
        }
    }

    private func startEditing() {
        draft = value
        isEditing = true
        testResult = .idle
    }

    private func cancel() {
        isEditing = false
        draft = value
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        value = trimmed
        onSave?(trimmed)
        isEditing = false
        testResult = .idle
    }

    private func mask(_ raw: String) -> String {
        guard raw.count > 8 else { return raw }
        let prefix = raw.prefix(4)
        let suffix = raw.suffix(4)
        return "\(prefix)…\(suffix)"
    }

    @MainActor
    private func testAPIKey() async {
        guard let endpoint = testEndpoint else { return }
        testResult = .testing
        let request = endpoint.buildRequest(apiKey: value)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200..<300:
                    testResult = .valid
                case 401:
                    testResult = .invalid("Invalid key")
                case 403:
                    testResult = .invalid("Access denied")
                case 429:
                    testResult = .invalid("Rate limited")
                default:
                    testResult = .invalid("Error \(httpResponse.statusCode)")
                }
            } else {
                testResult = .invalid("Unknown error")
            }
        } catch {
            testResult = .invalid("Connection failed")
        }
    }
}
