import Foundation
import SwiftOpenAI
import SwiftUI

struct CoverLetterAiView: View {
    @AppStorage("openAiApiKey") var openAiApiKey: String = "none"
    @Binding var buttons: CoverLetterButtons
    @Binding var refresh: Bool

    var body: some View {
        // Create a custom URLSessionConfiguration with extended timeout
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 360 // 360 seconds for extended timeout

        // Initialize the service with the custom configuration and pass debugEnabled as false
        let service = OpenAIServiceFactory.service(
            apiKey: openAiApiKey, configuration: configuration, debugEnabled: false
        )

        return CoverLetterAiContentView(
            service: service,
            buttons: $buttons,
            refresh: $refresh
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
    let service: OpenAIService

    // Use @Bindable for chatProvider
    @Bindable var chatProvider: CoverChatProvider
    // Wrapper for displaying result notifications or errors
    @State private var errorWrapper: ErrorMessageWrapper? = nil

    init(
        service: OpenAIService,
        buttons: Binding<CoverLetterButtons>,
        refresh: Binding<Bool>
    ) {
        self.service = service
        _buttons = buttons
        chatProvider = CoverChatProvider(service: service)
        _refresh = refresh
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
                    VStack {
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
                            }
                            .help("Generate new Cover Letter")
                        } else {
                            ProgressView()
                                .scaleEffect(0.75, anchor: .center)
                        }
                    }
                    .padding()
                    .onAppear { print("AI content") }

                    // Choose Best Cover Letter
                    VStack {
                        if buttons.chooseBestRequested {
                            ProgressView()
                                .scaleEffect(0.75, anchor: .center)
                        } else {
                            Button(action: {
                                chooseBestCoverLetter()
                            }) {
                                Image(systemName: "hand.thumbsup")
                                    .font(.system(size: 20, weight: .regular))
                            }
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
                    }
                    .padding()
                }
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
    }

    // MARK: - Actions

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
                    service: service,
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
                        Selected "\(best.name)" as best cover letter.

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
