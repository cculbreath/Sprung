import SwiftOpenAI
import SwiftUI

struct AiFunctionView: View {
    @Binding var res: Resume?
    @AppStorage("openAiApiKey") var openAiApiKey: String = "none"

    private var service: OpenAIService!

    init(res: Binding<Resume?>) {
        _res = res

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 360 // 360 seconds for extended timeout

        service = OpenAIServiceFactory.service(
            apiKey: openAiApiKey, configuration: configuration, debugEnabled: false
        )
    }

    var body: some View {
        if let myRes = res {
            AiCommsView(
                service: service,
                query: myRes.generateQuery(),
                res: $res
            )
            .onAppear { myRes.debounceExport() } // Use `myRes` instead of force-unwrapping
        } else {
            Text("No Resume Available") // Optionally, handle the case when `res` is nil
        }
    }
}
