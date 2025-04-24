// `//
////  AiPanelView.swift
////  PhysicsCloudResume
////
////  Created by Christopher Culbreath on 8/25/24.
////
//
// import SwiftUI
//
// struct AiPanelView: View {
//  @Binding var res: Resume
//  @State var attentionGrab: Int = 2
//  @AppStorage("openAiApiKey") var openAiApiKey: String = "none"
//
//  @State private var isButHover: Bool = false
//
//  var body: some View {
//    let q = res.generateQuery(attentionGrab: attentionGrab)
//    GroupBox {
//      VStack {
//        HStack {
//          Button( action: {print("nope")}) {
//            Image(
//              isButHover
//                ? "ai-squiggle.bubble.left.fill"
//                : "ai-squiggle.bubble.left"
//            )
//            .foregroundColor(.pink)
//            .font(.system(size: 22))
//            .fontWeight(.light)
//          }.buttonStyle(.borderless).onHover { hover in
//            isButHover = hover
//          }
//          Stepper("Attenion grabbing intensity \(attentionGrab)", value: $attentionGrab, in: 0...4)
//        }
//        ChatView(key: openAiApiKey, apiQuery: q, res: $res)
//      }.frame(maxWidth: .infinity, minHeight: 100)
//    }
//  }
// }
