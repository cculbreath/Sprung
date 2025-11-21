import SwiftUI
/// Lightweight wrapper that mimics the grouped cards used across onboarding flows.
struct SectionCard<Content: View>: View {
    let title: String
    let content: () -> Content
    init(
        title: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.content = content
    }
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(title)
                .font(.headline)
        }
    }
}
