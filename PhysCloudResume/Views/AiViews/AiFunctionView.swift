import SwiftOpenAI
import SwiftUI

struct AiFunctionView: View {
    @Binding var res: Resume?
    @AppStorage("openAiApiKey") var openAiApiKey: String = "none"

    init(res: Binding<Resume?>) {
        _res = res
    }

    var body: some View {
        if let myRes = res {
            AiCommsView(
                service: OpenAIServiceFactory.service(apiKey: openAiApiKey, debugEnabled: true),
                query: myRes.generateQuery(),
                res: $res
            )
            .onAppear { myRes.debounceExport() } // Use `myRes` instead of force-unwrapping
        } else {
            Text("No Resume Available") // Optionally, handle the case when `res` is nil
        }
    }
}
