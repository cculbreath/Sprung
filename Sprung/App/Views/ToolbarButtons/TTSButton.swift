//
//  TTSButton.swift
//  Sprung
//
//
import SwiftUI
/// Toolbar button for text-to-speech functionality with status display and option-click restart
struct TTSButton: View {
    @Environment(CoverLetterStore.self) private var coverLetterStore
    @Environment(AppState.self) private var appState
    @AppStorage("ttsEnabled") private var ttsEnabled: Bool = false
    @AppStorage("ttsVoice") private var ttsVoice: String = "nova"
    @AppStorage("ttsInstructions") private var ttsInstructions: String = ""

    @State private var ttsViewModel: TTSViewModel?
    @State private var ttsProvider: OpenAITTSProvider?

    private var isDisabled: Bool {
        !ttsEnabled || coverLetterStore.cL?.generated != true || coverLetterStore.cL?.content.isEmpty == true
    }

    private var buttonColor: Color {
        if isDisabled {
            return .secondary
        }

        guard let viewModel = ttsViewModel else { return .primary }

        if viewModel.isBuffering {
            return .orange
        } else if viewModel.isSpeaking {
            return .green
        } else if viewModel.isPaused {
            return .yellow
        } else {
            return .primary
        }
    }

    private var buttonIcon: String {
        guard let viewModel = ttsViewModel, !isDisabled else {
            return "speaker.slash"
        }

        if viewModel.isBuffering {
            return "speaker.badge.exclamationmark"
        } else if viewModel.isSpeaking {
            return "speaker.wave.3"
        } else if viewModel.isPaused {
            return "speaker.wave.1"
        } else {
            return "speaker.wave.2"
        }
    }

    private var helpText: String {
        if !ttsEnabled {
            return "TTS is disabled in settings"
        } else if coverLetterStore.cL?.generated != true {
            return "No generated cover letter to read"
        } else if let viewModel = ttsViewModel {
            if viewModel.isBuffering {
                return "TTS is buffering audio... (Option-click to restart)"
            } else if viewModel.isSpeaking {
                return "TTS is reading aloud (click to pause, Option-click to restart)"
            } else if viewModel.isPaused {
                return "TTS is paused (click to resume, Option-click to restart)"
            } else {
                return "Read cover letter aloud (Option-click to restart)"
            }
        } else {
            return "Read cover letter aloud"
        }
    }

    var body: some View {
        Button(action: handleClick) {
            Label("TTS", systemImage: buttonIcon)
                .font(.system(size: 14, weight: .light))
                .foregroundColor(buttonColor)
        }
        .buttonStyle(.automatic)
        .disabled(isDisabled)
        .help(helpText)
        .onAppear {
            setupTTS()
        }
        .onChange(of: ttsEnabled) { _, _ in
            setupTTS()
        }
        .onReceive(NotificationCenter.default.publisher(for: .apiKeysChanged)) { _ in
            setupTTS()
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerTTSButton)) { _ in
            // Programmatically trigger the button action (from menu commands)
            handleClick()
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerTTSStart)) { _ in
            // Force start TTS
            startTTS()
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerTTSStop)) { _ in
            // Force stop TTS
            ttsViewModel?.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerTTSRestart)) { _ in
            // Force restart TTS
            restartTTS()
        }
    }

    private func handleClick() {
        let event = NSApp.currentEvent
        let isOptionClick = event?.modifierFlags.contains(.option) == true

        guard let viewModel = ttsViewModel else { return }

        if isOptionClick {
            // Option-click: restart TTS
            restartTTS()
        } else {
            // Regular click: toggle play/pause
            if viewModel.isSpeaking {
                viewModel.pause()
            } else if viewModel.isPaused {
                viewModel.resume()
            } else {
                startTTS()
            }
        }
    }

    private func setupTTS() {
        guard ttsEnabled, appState.hasValidOpenAiKey, let key = APIKeyManager.get(.openAI), !key.isEmpty else {
            ttsProvider = nil
            ttsViewModel = nil
            return
        }

        // Create TTS provider and view model
        let provider = OpenAITTSProvider(apiKey: key)
        let viewModel = TTSViewModel(ttsProvider: provider)

        ttsProvider = provider
        ttsViewModel = viewModel
    }

    private func startTTS() {
        guard let viewModel = ttsViewModel,
              let coverLetter = coverLetterStore.cL,
              coverLetter.generated,
              !coverLetter.content.isEmpty else { return }

        let voice = OpenAITTSProvider.Voice(rawValue: ttsVoice) ?? .nova
        let instructions = ttsInstructions.isEmpty ? nil : ttsInstructions

        viewModel.speakContent(coverLetter.content, voice: voice, instructions: instructions)
    }

    private func restartTTS() {
        guard let viewModel = ttsViewModel else { return }

        // Stop current playback
        viewModel.stop()

        // Start fresh
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startTTS()
        }
    }
}
