//
//  TextToSpeechSettingsView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/24/25.
//

import AVFoundation // Needed for AVAudioPlayerDelegate potentially
import SwiftUI

struct TextToSpeechSettingsView: View {
    // AppStorage properties specific to this view
    @AppStorage("openAiApiKey") private var openAiApiKey: String = "none"
    @AppStorage("ttsEnabled") private var ttsEnabled: Bool = false
    @AppStorage("ttsVoice") private var ttsVoice: String = "nova"
    @AppStorage("ttsInstructions") private var ttsInstructions: String = ""

    // State for managing TTS preview
    @State private var ttsProvider: OpenAITTSProvider?
    @State private var isPreviewingVoice: Bool = false
    @State private var ttsError: String? = nil
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Text-to-Speech")
                .font(.headline)
                .padding(.bottom, 5)

            // Enable TTS Toggle
            Toggle("Enable Text-to-Speech", isOn: $ttsEnabled)
                .toggleStyle(.switch)
                .disabled(openAiApiKey == "none") // Disable if no API key
                .onChange(of: ttsEnabled) { _, newValue in
                    // Initialize or deinitialize TTS provider based on toggle
                    if newValue && openAiApiKey != "none" {
                        initializeTTSProvider()
                    } else {
                        ttsProvider = nil // Release provider if disabled or key removed
                    }
                }

            // Show message if API key is missing
            if openAiApiKey == "none" {
                Text("Add OpenAI API key to enable TTS.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Show TTS options only if enabled
            if ttsEnabled && openAiApiKey != "none" {
                Divider().padding(.vertical, 5)

                // Voice Selection
                HStack {
                    Text("Voice")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Picker("", selection: $ttsVoice) {
                        // Use OpenAITTSProvider.Voice enum for options
                        ForEach(OpenAITTSProvider.Voice.allCases, id: \.rawValue) { voice in
                            Text(voice.displayName).tag(voice.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 250) // Limit picker width
                }

                // Voice Preview Button
                HStack {
                    Spacer()
                    Button(action: previewVoice) {
                        Label(isPreviewingVoice ? "Stop Preview" : "Preview Voice",
                              systemImage: isPreviewingVoice ? "stop.circle.fill" : "play.circle.fill") // Use stop/play icons
                    }
                    .disabled(isPreviewingVoice && ttsProvider == nil) // Disable if previewing without provider
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(isPreviewingVoice ? "Stop voice preview" : "Preview the selected voice")
                    Spacer()
                }
                .padding(.top, 5)

                // Voice Instructions Section
                Divider().padding(.vertical, 5)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Voice Instructions")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Reset to Default") {
                            ttsInstructions = defaultInstructions
                        }
                        .buttonStyle(.link) // Use link style for less emphasis
                        .controlSize(.small)
                        .font(.caption)
                    }

                    TextEditor(text: $ttsInstructions)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 100, idealHeight: 150, maxHeight: 200) // Constrain height
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .scrollContentBackground(.hidden) // Hide default background if needed

                    Text("Instructions guide the AI's voice delivery (affect, tone, pacing).")
                        .font(.caption2) // Smaller caption
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.7), lineWidth: 1)
        )
        .onAppear {
            // Initialize TTS provider on appear if enabled and key exists
            if ttsEnabled && openAiApiKey != "none" {
                initializeTTSProvider()
            }
        }
        .onChange(of: openAiApiKey) { _, newKey in
            // Re-initialize provider if key changes and TTS is enabled
            if ttsEnabled && newKey != "none" {
                initializeTTSProvider()
            } else {
                ttsProvider = nil // Deinitialize if key becomes invalid
                ttsEnabled = false // Disable TTS if key removed
            }
        }
        .alert("TTS Error", isPresented: $showTTSErrorAlert) { // Use unique binding name
            Button("OK") { showTTSErrorAlert = false }
        } message: {
            Text(ttsError ?? "An unknown error occurred with text-to-speech.")
        }
    }

    // Initialize or update the TTS provider
    private func initializeTTSProvider() {
        // Avoid re-initializing if the key hasn't changed
        if ttsProvider?.apiKey != openAiApiKey {
            ttsProvider = OpenAITTSProvider(apiKey: openAiApiKey)
        }
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
