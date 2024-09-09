//
//  AiFunctionView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/4/24.
//

import SwiftOpenAI
import SwiftUI

struct AiFunctionView: View {
  @Binding var attentionGrab: Int
  @Binding var res: Resume
  @AppStorage("openAiApiKey") var openAiApiKey: String = "none"

  init(res: Binding<Resume>, attn: Binding<Int>) {
    self._res = res
    self._attentionGrab = attn
  }
  var body: some View {
    AiCommsView(
      service: OpenAIServiceFactory.service(apiKey: openAiApiKey, debugEnabled: true),
      query: res.generateQuery(attentionGrab: attentionGrab), res: $res
    ).onAppear { res.debounceExport() }
  }
}
