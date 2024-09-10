import SwiftOpenAI
import SwiftUI

struct AiFunctionView: View {
  @Binding var attentionGrab: Int
  @Binding var res: Resume?
  @AppStorage("openAiApiKey") var openAiApiKey: String = "none"

  init(res: Binding<Resume?>, attn: Binding<Int>) {
    self._res = res
    self._attentionGrab = attn
  }

  var body: some View {
    if let myRes = res {
      AiCommsView(
        service: OpenAIServiceFactory.service(apiKey: openAiApiKey, debugEnabled: true),
        query: myRes.generateQuery(attentionGrab: attentionGrab), // Use unwrapped `myRes`
        res: $res // Pass the binding directly
      )
      .onAppear { myRes.debounceExport() } // Use `myRes` instead of force-unwrapping
    } else {
      Text("No Resume Available") // Optionally, handle the case when `res` is nil
    }
  }
}
