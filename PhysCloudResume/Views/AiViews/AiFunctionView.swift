import SwiftUI

struct AiFunctionView: View {
    @Binding var res: Resume?
    @AppStorage("openAiApiKey") var openAiApiKey: String = "none"
    @AppStorage("ttsEnabled") var ttsEnabled: Bool = false
    @AppStorage("ttsVoice") var ttsVoice: String = "nova"

    // Use our abstraction layer for OpenAI
    private var openAIClient: OpenAIClientProtocol
    // For TTS functionality
    private var ttsProvider: OpenAITTSProvider

    init(res: Binding<Resume?>) {
        _res = res

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 600 // 10 minutes for extended timeout
        configuration.timeoutIntervalForResource = 600 // Also set resource timeout

        // Increase the connections per host for better performance
        configuration.httpMaximumConnectionsPerHost = 6

        // Use our abstraction layer for OpenAI
        openAIClient = OpenAIClientFactory.createClient(apiKey: openAiApiKey)

        // Initialize TTS provider
        ttsProvider = OpenAITTSProvider(apiKey: openAiApiKey)
    }

    var body: some View {
        if let myRes = res {
            AiCommsView(
                openAIClient: openAIClient,
                ttsProvider: ttsProvider,
                query: myRes.generateQuery(),
                res: $res,
                ttsEnabled: $ttsEnabled,
                ttsVoice: $ttsVoice
            )
            .onAppear { myRes.debounceExport() }
        } else {
            Text("No Resume Available")
        }
    }
}
