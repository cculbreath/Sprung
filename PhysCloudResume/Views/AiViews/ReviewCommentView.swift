import SwiftUI

struct ReviewCommentView: View {
  @Binding var comment: String
  @Binding var isCommenting: Bool
  let saveAction: () -> Void  // Closure without parameters

  var body: some View {
    VStack(alignment: .leading) {
      Text("Comments/Instructions to improve text generation")
        .font(.footnote)
      TextField("Reviewer Comments", text: $comment)
        .lineLimit(3...10)
      HStack {
        Button(
          "Save",
          action: {
            isCommenting = false
            saveAction()  // Call the closure directly
          })
        Button(
          "Cancel",
          action: {
            isCommenting = false
          })
      }
    }.padding()
  }
}
