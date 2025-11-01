import SwiftUI

struct ExtractionProgressChecklistView: View {
    let items: [ExtractionProgressItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(items) { item in
                ExtractionProgressRowView(item: item)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: items)
    }
}

private struct ExtractionProgressRowView: View {
    let item: ExtractionProgressItem

    @State private var isPulsing = false
    @State private var showCheckmark = false
    @State private var highlightStrength: CGFloat = 0
    @State private var detailText: String = ""
    @State private var showDetail = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            iconView
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.stage.title)
                    .font(.subheadline)
                    .fontWeight(item.state == .completed ? .semibold : .regular)
                    .foregroundStyle(titleColor(for: item.state))
                    .transition(.opacity.combined(with: .scale))

                if showDetail {
                    Text(detailText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accentColor.opacity(0.1))
                .opacity(highlightStrength)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
                .opacity(highlightStrength)
        )
        .animation(.easeInOut(duration: 0.3), value: highlightStrength)
        .onChange(of: item.state, initial: true) { _, newState in
            handleStateChange(newState)
        }
        .onChange(of: item.detail, initial: true) { _, newDetail in
            handleDetailChange(newDetail)
        }
    }

    private var iconView: some View {
        ZStack {
            if item.state == .active {
                Circle()
                    .stroke(Color.accentColor.opacity(0.25), lineWidth: 3)
                    .scaleEffect(isPulsing ? 1.35 : 0.85)
                    .opacity(isPulsing ? 0.4 : 0.1)
                    .animation(
                        isPulsing ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default,
                        value: isPulsing
                    )
            }

            switch item.state {
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
                    .foregroundStyle(.accentColor)
                    .scaleEffect(showCheckmark ? 1.0 : 0.45)
                    .rotationEffect(.degrees(showCheckmark ? 0 : -35))
                    .opacity(showCheckmark ? 1 : 0)
                    .shadow(color: showCheckmark ? Color.accentColor.opacity(0.35) : .clear, radius: 10, y: 3)
                    .animation(.spring(response: 0.42, dampingFraction: 0.68), value: showCheckmark)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private func handleStateChange(_ state: ExtractionProgressStageState) {
        switch state {
        case .pending:
            isPulsing = false
            withAnimation(.easeInOut(duration: 0.25)) {
                highlightStrength = 0
                showCheckmark = false
            }
        case .active:
            withAnimation(.easeInOut(duration: 0.25)) {
                highlightStrength = 1
                showCheckmark = false
            }
            DispatchQueue.main.async {
                isPulsing = true
            }
        case .completed:
            isPulsing = false
            withAnimation(.easeInOut(duration: 0.25)) {
                highlightStrength = 0
            }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.65).delay(0.05)) {
                showCheckmark = true
            }
        case .failed:
            isPulsing = false
            withAnimation(.easeInOut(duration: 0.25)) {
                highlightStrength = 0
                showCheckmark = false
            }
        }
    }

    private func handleDetailChange(_ detail: String?) {
        let trimmed = detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            withAnimation(.easeInOut(duration: 0.2)) {
                showDetail = false
            }
            detailText = ""
        } else {
            detailText = trimmed
            withAnimation(.easeInOut(duration: 0.25)) {
                showDetail = true
            }
        }
    }

    private func titleColor(for state: ExtractionProgressStageState) -> Color {
        switch state {
        case .pending:
            return .secondary
        case .active, .completed:
            return .primary
        case .failed:
            return .red
        }
    }
}
