//
//  TextToSpeechSettingsView.swift
//  Sprung
//
//
import AVFoundation // Needed for AVAudioPlayerDelegate potentially
import SwiftUI
struct TextToSpeechSettingsView: View {
    // AppStorage properties specific to this view
    @Environment(AppState.self) private var appState
    @Environment(LLMFacade.self) private var llmFacade
    @AppStorage("ttsEnabled") private var ttsEnabled: Bool = false
    @AppStorage("ttsVoice") private var ttsVoice: String = "nova"
    @AppStorage("ttsInstructions") private var ttsInstructions: String = ""
    // State for managing TTS preview
    @State private var ttsProvider: OpenAITTSProvider?
    @State private var isPreviewingVoice: Bool = false
    @State private var ttsError: String?
    @State private var showTTSErrorAlert: Bool = false // Use a different name to avoid conflict
    // Default instructions constant
    private let defaultInstructions = """
    Voice Affect: Confident, composed, and respectful; project well-supported authority and confidence without hubris.
    Tone: Sincere, empathetic, and authoritative—but not arrogant. Express genuine humility while conveying competence.
    Pacing: Brisk and confident, quickly but intelligible. Faster than most would think appropriate but not to the point of sounding digitally sped up. Slow moderately for emphasis, demonstrating thoughtfulness while prioritizing efficiency and respect for your audience's time.
    Emotion: Engaged and confident; speak with warmth and charisma. Lean into rising pitch, confident resolution, and the identifiable rhythms of a skilled orator.
    Pronunciation: Clear and precise, emphasizing understanding and fluency with technical concepts, and a deft handling of even the most stubborn aspects of the English language.
    Pauses: Brief pauses for emphasis and gravitas, but with an overall cadence of efficiency and forward momentum.
    """
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
                Picker("Voice", selection: $ttsVoice) {
                    ForEach(OpenAITTSProvider.Voice.allCases, id: \.rawValue) { voice in
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
                    Text("Instructions guide the AI narrator’s tone, pacing, and emphasis when generating audio.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
        .alert("TTS Error", isPresented: $showTTSErrorAlert) { // Use unique binding name
            Button("OK") { showTTSErrorAlert = false }
        } message: {
            Text(ttsError ?? "An unknown error occurred with text-to-speech.")
        }
    }
    // Initialize or update the TTS provider using LLMFacade
    private func initializeTTSProvider() {
        guard appState.hasValidOpenAiKey else {
            ttsProvider = nil
            return
        }
        // Create TTS provider using LLMFacade's TTS client
        let ttsClient = llmFacade.createTTSClient()
        ttsProvider = OpenAITTSProvider(ttsClient: ttsClient)
    }
    // Preview the currently selected TTS voice
    private func previewVoice() {
        // If already previewing, stop it
        if isPreviewingVoice {
            ttsProvider?.stopSpeaking()
            isPreviewingVoice = false
            return
        }
        // Ensure provider is initialized
        guard let provider = ttsProvider else {
            ttsError = "TTS Provider not initialized. Check API Key."
            showTTSErrorAlert = true
            return
        }
        // Sample text for preview
        let sampleText = "This is a preview of the \(ttsVoice) voice."
        isPreviewingVoice = true
        ttsError = nil // Clear previous errors
        // Get the selected voice enum case
        let voiceEnum = OpenAITTSProvider.Voice(rawValue: ttsVoice) ?? .nova
        // Get instructions, use nil if empty
        let instructions = ttsInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : ttsInstructions
        // Speak the sample text
        provider.speakText(sampleText, voice: voiceEnum, instructions: instructions) { error in
            DispatchQueue.main.async {
                self.isPreviewingVoice = false // Reset state when done or on error
                if let error = error {
                    self.ttsError = "Preview failed: \(error.localizedDescription)"
                    self.showTTSErrorAlert = true
                }
            }
        }
    }
}
