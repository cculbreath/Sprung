//
//  TextToSpeechSettingsView.swift
//  Sprung
//
//
import AVFoundation
import SwiftUI
struct TextToSpeechSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(LLMFacade.self) private var llmFacade
    @AppStorage("ttsEnabled") private var ttsEnabled: Bool = false
    @AppStorage("ttsModel") private var ttsModel: String = "gpt-4o-mini-tts"
    @AppStorage("ttsVoice") private var ttsVoice: String = "nova"
    @AppStorage("ttsInstructions") private var ttsInstructions: String = ""
    @State private var ttsProvider: OpenAITTSProvider?
    @State private var isPreviewingVoice: Bool = false
    @State private var ttsError: String?
    @State private var showTTSErrorAlert: Bool = false
    private let defaultInstructions = """
    Voice Affect: Confident, composed, and respectful; project well-supported authority and confidence without hubris.
    Tone: Sincere, empathetic, and authoritative—but not arrogant. Express genuine humility while conveying competence.
    Pacing: Brisk and confident, quickly but intelligible. Faster than most would think appropriate but not to the point of sounding digitally sped up. Slow moderately for emphasis, demonstrating thoughtfulness while prioritizing efficiency and respect for your audience's time.
    Emotion: Engaged and confident; speak with warmth and charisma. Lean into rising pitch, confident resolution, and the identifiable rhythms of a skilled orator.
    Pronunciation: Clear and precise, emphasizing understanding and fluency with technical concepts, and a deft handling of even the most stubborn aspects of the English language.
    Pauses: Brief pauses for emphasis and gravitas, but with an overall cadence of efficiency and forward momentum.
    """
    private var selectedModel: OpenAITTSProvider.TTSModel {
        OpenAITTSProvider.TTSModel(rawValue: ttsModel) ?? .gpt4oMiniTTS
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enable Text-to-Speech", isOn: $ttsEnabled)
                .toggleStyle(.switch)
                .disabled(!appState.hasValidOpenAiKey)
                .onChange(of: ttsEnabled) { _, newValue in
                    if newValue && appState.hasValidOpenAiKey {
                        initializeTTSProvider()
                    } else {
                        ttsProvider = nil
                    }
                }
            if !appState.hasValidOpenAiKey {
                Text("Add an OpenAI API key to enable the résumé narration preview.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if ttsEnabled && appState.hasValidOpenAiKey {
                Picker("Model", selection: $ttsModel) {
                    ForEach(OpenAITTSProvider.TTSModel.allCases, id: \.rawValue) { model in
                        Text(model.displayName).tag(model.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: ttsModel) { _, _ in
                    // Reset voice if not supported by new model
                    if !selectedModel.supportedVoices.contains(where: { $0.rawValue == ttsVoice }) {
                        ttsVoice = "nova"
                    }
                }
                Picker("Voice", selection: $ttsVoice) {
                    ForEach(selectedModel.supportedVoices, id: \.rawValue) { voice in
                        Text(voice.displayName).tag(voice.rawValue)
                    }
                }
                .pickerStyle(.menu)
                HStack {
                    Spacer()
                    Button(action: previewVoice) {
                        Label(
                            isPreviewingVoice ? "Stop Preview" : "Preview Voice",
                            systemImage: isPreviewingVoice ? "stop.circle.fill" : "play.circle.fill"
                        )
                    }
                    .disabled(isPreviewingVoice && ttsProvider == nil)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Spacer()
                }
                if selectedModel.supportsInstructions {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Voice Instructions")
                                .font(.headline)
                                .fontWeight(.semibold)
                            Spacer()
                            Button("Reset") {
                                ttsInstructions = defaultInstructions
                            }
                            .buttonStyle(.link)
                            .controlSize(.small)
                        }
                        TextEditor(text: $ttsInstructions)
                            .font(.system(.callout, design: .monospaced))
                            .frame(minHeight: 120, maxHeight: 220)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                            )
                        Text("Instructions guide the AI narrator's tone, pacing, and emphasis when generating audio.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear {
            if ttsEnabled && appState.hasValidOpenAiKey { initializeTTSProvider() }
        }
        .onChange(of: ttsEnabled) { _, enabled in
            if enabled { initializeTTSProvider() } else { ttsProvider = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .apiKeysChanged)) { _ in
            if ttsEnabled && appState.hasValidOpenAiKey {
                initializeTTSProvider()
            } else {
                ttsProvider = nil
            }
        }
        .alert("TTS Error", isPresented: $showTTSErrorAlert) {
            Button("OK") { showTTSErrorAlert = false }
        } message: {
            Text(ttsError ?? "An unknown error occurred with text-to-speech.")
        }
    }
    private func initializeTTSProvider() {
        guard appState.hasValidOpenAiKey else {
            ttsProvider = nil
            return
        }
        let ttsClient = llmFacade.createTTSClient()
        ttsProvider = OpenAITTSProvider(ttsClient: ttsClient)
    }
    private func previewVoice() {
        if isPreviewingVoice {
            ttsProvider?.stopSpeaking()
            isPreviewingVoice = false
            return
        }
        guard let provider = ttsProvider else {
            ttsError = "TTS Provider not initialized. Check API Key."
            showTTSErrorAlert = true
            return
        }
        let sampleText = "This is a preview of the \(ttsVoice) voice."
        isPreviewingVoice = true
        ttsError = nil
        let model = selectedModel
        let voiceEnum = OpenAITTSProvider.Voice(rawValue: ttsVoice) ?? .nova
        let instructions = model.supportsInstructions && !ttsInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ttsInstructions : nil
        provider.speakText(sampleText, model: model, voice: voiceEnum, instructions: instructions) { error in
            DispatchQueue.main.async {
                self.isPreviewingVoice = false
                if let error = error {
                    self.ttsError = "Preview failed: \(error.localizedDescription)"
                    self.showTTSErrorAlert = true
                }
            }
        }
    }
}
