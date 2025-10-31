import SwiftUI

struct ExtractionProgressChecklistView: View {
    let items: [ExtractionProgressItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 12) {
                    icon(for: item.state)
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.stage.title)
                            .font(.subheadline)
                            .fontWeight(item.state == .completed ? .semibold : .regular)
                            .foregroundStyle(foregroundStyle(for: item.state))

                        if let detail = item.detail, !detail.isEmpty {
                            Text(detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: items)
    }

    @ViewBuilder
    private func icon(for state: ExtractionProgressStageState) -> some View {
        switch state {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
        case .active:
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(.accentColor)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private func foregroundStyle(for state: ExtractionProgressStageState) -> Color {
        switch state {
        case .pending:
            return .secondary
        case .active:
            return .primary
        case .completed:
            return .primary
        case .failed:
            return .red
        }
    }
}
