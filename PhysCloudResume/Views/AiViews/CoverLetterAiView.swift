import Foundation
import SwiftUI

struct CoverLetterAiView: View {
    @AppStorage("openAiApiKey") var openAiApiKey: String = "none"
    @AppStorage("ttsEnabled") var ttsEnabled: Bool = false
    @AppStorage("ttsVoice") var ttsVoice: String = "nova"
    @Binding var buttons: CoverLetterButtons
    @Binding var refresh: Bool

    var body: some View {
        // Create OpenAI client using our abstraction layer
        let openAIClient = OpenAIClientFactory.createClient(apiKey: openAiApiKey)

        // Initialize TTS provider
        let ttsProvider = OpenAITTSProvider(apiKey: openAiApiKey)

        return CoverLetterAiContentView(
            openAIClient: openAIClient,
            ttsProvider: ttsProvider,
            buttons: $buttons,
            refresh: $refresh,
            ttsEnabled: $ttsEnabled,
            ttsVoice: $ttsVoice
        )
        .onAppear { print("Ai Cover Letter") }
    }
}

struct CoverLetterAiContentView: View {
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore

    @State var aiMode: CoverAiMode = .none
    @Binding var buttons: CoverLetterButtons
    @Binding var refresh: Bool

    // Abstraction layer for OpenAI
    let openAIClient: OpenAIClientProtocol
    // TTS provider for speech synthesis
    let ttsProvider: OpenAITTSProvider

    // TTS related state
    @Binding var ttsEnabled: Bool
    @Binding var ttsVoice: String
    @AppStorage("ttsInstructions") private var ttsInstructions: String = ""
    @State private var isSpeaking: Bool = false
    @State private var ttsError: String? = nil
    @State private var showTTSError: Bool = false

    // Use @Bindable for chatProvider
    @Bindable var chatProvider: CoverChatProvider
    // Wrapper for displaying result notifications or errors
    @State private var errorWrapper: ErrorMessageWrapper? = nil

    init(
        openAIClient: OpenAIClientProtocol,
        ttsProvider: OpenAITTSProvider,
        buttons: Binding<CoverLetterButtons>,
        refresh: Binding<Bool>,
        ttsEnabled: Binding<Bool> = .constant(false),
        ttsVoice: Binding<String> = .constant("nova")
    ) {
        self.openAIClient = openAIClient
        self.ttsProvider = ttsProvider
        _buttons = buttons
        chatProvider = CoverChatProvider(client: openAIClient)
        _refresh = refresh
        _ttsEnabled = ttsEnabled
        _ttsVoice = ttsVoice
    }

    var cL: Binding<CoverLetter> {
        guard let selectedApp = jobAppStore.selectedApp else {
            fatalError("No selected app")
        }
        return Binding(get: {
            selectedApp.selectedCover!
        }, set: {
            selectedApp.selectedCover = $0
        })
    }

    var body: some View {
        Group {
            if jobAppStore.selectedApp?.selectedCover != nil {
                HStack(spacing: 16) {
                    // Generate New Cover Letter
                    if !buttons.runRequested {
                        Button(action: {
                            print("Generate cover letter")
                            if !cL.wrappedValue.generated {
                                cL.wrappedValue.currentMode = .generate
                            } else {
                                let newCL = coverLetterStore.createDuplicate(letter: cL.wrappedValue)
                                cL.wrappedValue = newCL
                                print("Duplicated for regeneration")
                            }
                            chatProvider.coverChatAction(
                                res: jobAppStore.selectedApp?.selectedRes,
                                jobAppStore: jobAppStore,
                                chatProvider: chatProvider,
                                buttons: $buttons
                            )
                        }) {
                            Image("ai-squiggle")
                                .font(.system(size: 20, weight: .regular))
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .help("Generate new Cover Letter")
                    } else {
                        ProgressView()
                            .scaleEffect(0.75, anchor: .center)
                            .frame(width: 36, height: 36)
                    }

                    // Choose Best Cover Letter
                    if buttons.chooseBestRequested {
                        ProgressView()
                            .scaleEffect(0.75, anchor: .center)
                            .frame(width: 36, height: 36)
                    } else {
                        Button(action: {
                            chooseBestCoverLetter()
                        }) {
                            Image(systemName: "medal.fill")
                                .font(.system(size: 20, weight: .regular))
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .disabled(
                            jobAppStore.selectedApp?.coverLetters.count ?? 0 <= 1
                                || cL.wrappedValue.writingSamplesString.isEmpty
                        )
                        .help(
                            (jobAppStore.selectedApp?.coverLetters.count ?? 0) <= 1
                                ? "At least two cover letters are required"
                                : cL.wrappedValue.writingSamplesString.isEmpty
                                ? "Add writing samples to enable choosing best cover letter"
                                : "Select the best cover letter based on style and voice"
                        )
                    }

                    // TTS Button - only show if TTS is enabled and we have content
                    if ttsEnabled && cL.wrappedValue.generated && !cL.wrappedValue.content.isEmpty {
                        Button(action: {
                            speakCoverLetter()
                        }) {
                            Image(systemName: isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2")
                                .font(.system(size: 20, weight: .regular))
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .help(isSpeaking ? "Stop speaking" : "Read cover letter aloud")
                        .disabled(buttons.runRequested || buttons.chooseBestRequested)
                    }
                }
                .onAppear { print("AI content") }
            }
        }
        // Show alert on result or error
        .alert(item: $errorWrapper) { wrapper in
            Alert(
                title: Text("Cover Letter Recommendation"),
                message: Text(wrapper.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert("TTS Error", isPresented: $showTTSError) {
            Button("OK") { showTTSError = false }
        } message: {
            Text(ttsError ?? "An error occurred with text-to-speech")
        }
    }

    // MARK: - Actions

    /// Read the cover letter aloud using TTS
    func speakCoverLetter() {
        // If currently speaking, stop playback
        if isSpeaking {
            ttsProvider.stopSpeaking()
            isSpeaking = false
            return
        }

        // Get the content from the current cover letter
        let content = cL.wrappedValue.content
        guard !content.isEmpty else {
            ttsError = "No content to speak"
            showTTSError = true
            return
        }

        // Prepare the text for speech - remove markdown formatting if needed
        let cleanContent = content
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")

        // Set UI state to speaking
        isSpeaking = true

        // Get the voice from the user preference
        let voice = OpenAITTSProvider.Voice(rawValue: ttsVoice) ?? .nova

        // Get voice instructions if available
        let instructions = ttsInstructions.isEmpty ? nil : ttsInstructions

        // Request TTS conversion and playback with instructions
        ttsProvider.speakText(cleanContent, voice: voice, instructions: instructions) { error in
            DispatchQueue.main.async {
                // Reset speaking state when playback completes
                self.isSpeaking = false

                // Handle any errors
                if let error = error {
                    self.ttsError = error.localizedDescription
                    self.showTTSError = true
                    print("TTS error: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Initiates the choose‑best‑cover‑letter operation
    func chooseBestCoverLetter() {
        guard let jobApp = jobAppStore.selectedApp else { return }
        let letters = jobApp.coverLetters
        buttons.chooseBestRequested = true

        // Capture writing samples from any existing cover letter
        let writingSamples = letters.first?.writingSamplesString ?? ""
        Task {
            do {
                let provider = CoverLetterRecommendationProvider(
                    client: openAIClient,
                    jobApp: jobApp,
                    writingSamples: writingSamples
                )
                let result = try await provider.fetchBestCoverLetter()
                await MainActor.run {
                    // Update selected cover and notify user
                    if let uuid = UUID(uuidString: result.bestLetterUuid),
                       let best = jobApp.coverLetters.first(where: { $0.id == uuid })
                    {
                        jobAppStore.selectedApp?.selectedCover = best
                        let message = """
                        Selected "\(best.sequencedName)" as best cover letter.

                        Analysis:
                        \(result.strengthAndVoiceAnalysis)

                        Reason:
                        \(result.verdict)
                        """
                        errorWrapper = ErrorMessageWrapper(message: message)
                    }
                    buttons.chooseBestRequested = false
                }
            } catch {
                await MainActor.run {
                    print("Choose best error: \(error.localizedDescription)")
                    buttons.chooseBestRequested = false
                    errorWrapper = ErrorMessageWrapper(
                        message: "Error choosing best cover letter: \(error.localizedDescription)"
                    )
                }
            }
        }
    }
}
