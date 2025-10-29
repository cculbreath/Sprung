import SwiftUI

/// Side panel used to house secondary controls (e.g. filters, section browsers).
struct CollapsibleSidePanel<Content: View>: View {
    @Binding var isExpanded: Bool
    let width: CGFloat
    let content: () -> Content

    init(
        isExpanded: Binding<Bool>,
        width: CGFloat = 280,
        @ViewBuilder content: @escaping () -> Content
    ) {
        _isExpanded = isExpanded
        self.width = width
        self.content = content
    }

    var body: some View {
        Group {
            if isExpanded {
                content()
                    .frame(width: width)
                    .background(Color(NSColor.controlBackgroundColor))
                    .transition(.move(edge: .leading))
            }
        }
    }
}
