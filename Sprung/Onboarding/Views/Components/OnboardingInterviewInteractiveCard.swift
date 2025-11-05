import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct OnboardingInterviewInteractiveCard: View {
    @Bindable var coordinator: OnboardingInterviewCoordinator
    @Bindable var router: ToolHandler
    @Bindable var state: OnboardingInterviewViewModel
    let modelStatusDescription: String
    let onOpenSettings: () -> Void
    @State private var isToolPaneOccupied = false

    var body: some View {
        let cornerRadius: CGFloat = 28  // Reduced for more natural appearance
        let statusMap: [OnboardingToolIdentifier: OnboardingToolStatus] = {
            var map = router.statusSnapshot.statuses
            map[.extractDocument] = coordinator.pendingExtractionSync == nil ? .ready : .processing
            return map
        }()

        return VStack(spacing: 18) {
            HStack(spacing: 0) {
                OnboardingInterviewToolPane(
                    coordinator: coordinator,
                    isOccupied: $isToolPaneOccupied
                )
                .frame(minWidth: 340, maxWidth: 420)
                .frame(maxHeight: .infinity, alignment: .topLeading)

                Divider()

                OnboardingInterviewChatPanel(
                    coordinator: coordinator,
                    state: state,
                    modelStatusDescription: modelStatusDescription,
                    onOpenSettings: onOpenSettings
                )
            }

            ToolStatusBar(statuses: statusMap)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 32)
        .frame(minHeight: 560)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.65))
                .shadow(color: Color.black.opacity(0.16), radius: 24, y: 18)
        )
        .padding(.horizontal, 64)
    }
}

private struct ToolStatusBar: View {
    let statuses: [OnboardingToolIdentifier: OnboardingToolStatus]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(displayEntries, id: \.identifier) { entry in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(indicatorColor(for: entry.status))
                            .frame(width: 8, height: 8)
                        Text(entry.title)
                            .font(.caption.weight(.semibold))
                        Text(statusText(for: entry.status))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        Capsule()
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))
        )
    }

    private typealias Entry = (identifier: OnboardingToolIdentifier, title: String, status: OnboardingToolStatus)

    private var displayEntries: [Entry] {
        displayOrder.compactMap { identifier in
            let status = statuses[identifier] ?? .ready
            return (identifier, displayName(for: identifier), status)
        }
    }

    private var displayOrder: [OnboardingToolIdentifier] {
        [
            .getUserOption,
            .getUserUpload,
            .getMacOSContactCard,
            .getApplicantProfile,
            .extractDocument,
            .submitForValidation
        ]
    }

    private func displayName(for identifier: OnboardingToolIdentifier) -> String {
        switch identifier {
        case .getUserOption:
            return "Choices"
        case .getUserUpload:
            return "Uploads"
        case .getMacOSContactCard:
            return "Contacts"
        case .getApplicantProfile:
            return "Profile"
        case .extractDocument:
            return "Extraction"
        case .submitForValidation:
            return "Validation"
        }
    }

    private func statusText(for status: OnboardingToolStatus) -> String {
        switch status {
        case .ready:
            return "Ready"
        case .waitingForUser:
            return "Waiting"
        case .processing:
            return "Processing"
        case .locked:
            return "Locked"
        }
    }

    private func indicatorColor(for status: OnboardingToolStatus) -> Color {
        switch status {
        case .ready:
            return .green
        case .waitingForUser:
            return .yellow
        case .processing:
            return .blue
        case .locked:
            return .gray
        }
    }
}
