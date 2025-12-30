import SwiftUI

/// Generic review card component providing consistent styling and layout for review workflows.
/// Provides a title, scrollable content area, and action buttons in a styled card container.
struct ReviewCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let contentMaxHeight: CGFloat
    let onCancel: () -> Void
    @ViewBuilder let content: () -> Content
    @ViewBuilder let actions: () -> AnyView

    init(
        title: String,
        subtitle: String? = nil,
        contentMaxHeight: CGFloat = 320,
        onCancel: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder actions: @escaping () -> AnyView
    ) {
        self.title = title
        self.subtitle = subtitle
        self.contentMaxHeight = contentMaxHeight
        self.onCancel = onCancel
        self.content = content
        self.actions = actions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header section
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            // Scrollable content area
            ScrollView {
                content()
            }
            .frame(maxHeight: contentMaxHeight)

            // Action buttons
            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                actions()
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .underPageBackgroundColor))
        )
    }
}

// MARK: - Convenience Initializers

extension ReviewCard {
    /// Simple review card with single accept action
    init(
        title: String,
        subtitle: String? = nil,
        contentMaxHeight: CGFloat = 320,
        acceptButtonTitle: String = "Accept",
        onAccept: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) where Content: View {
        self.init(
            title: title,
            subtitle: subtitle,
            contentMaxHeight: contentMaxHeight,
            onCancel: onCancel,
            content: content,
            actions: {
                AnyView(
                    Button(acceptButtonTitle, action: onAccept)
                        .buttonStyle(.borderedProminent)
                )
            }
        )
    }
}
