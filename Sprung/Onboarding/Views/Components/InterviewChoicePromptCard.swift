import SwiftUI

struct InterviewChoicePromptCard: View {
    let prompt: OnboardingChoicePrompt
    let onSubmit: ([String]) -> Void
    let onCancel: () -> Void

    @State private var singleSelection: String?
    @State private var multiSelection: Set<String> = []

    private var isSingleSelection: Bool {
        prompt.selectionStyle == .single
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(prompt.prompt)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(prompt.options) { option in
                    choiceRow(for: option)
                }
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)

                Spacer()

                Button("Continue") {
                    let selections = isSingleSelection ? [singleSelection].compactMap { $0 } : Array(multiSelection)
                    guard !selections.isEmpty else { return }
                    onSubmit(selections)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSingleSelection ? singleSelection == nil : multiSelection.isEmpty)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.05))
        )
        .shadow(color: .black.opacity(0.12), radius: 16, y: 10)
        .onAppear {
            if isSingleSelection {
                singleSelection = prompt.options.first?.id
            }
        }
    }

    @ViewBuilder
    private func choiceRow(for option: OnboardingChoiceOption) -> some View {
        let isSelected = selectionState(for: option.id)
        Button {
            toggleSelection(for: option.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Image(systemName: iconName(isSelected: isSelected))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .imageScale(.large)
                    Text(option.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                if let detail = option.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 32)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityAddTraits(.isButton)
    }

    private func selectionState(for optionId: String) -> Bool {
        switch prompt.selectionStyle {
        case .single:
            return singleSelection == optionId
        case .multiple:
            return multiSelection.contains(optionId)
        }
    }

    private func toggleSelection(for optionId: String) {
        switch prompt.selectionStyle {
        case .single:
            singleSelection = optionId
        case .multiple:
            if multiSelection.contains(optionId) {
                multiSelection.remove(optionId)
            } else {
                multiSelection.insert(optionId)
            }
        }
    }

    private func iconName(isSelected: Bool) -> String {
        switch prompt.selectionStyle {
        case .single:
            return isSelected ? "largecircle.fill.circle" : "circle"
        case .multiple:
            return isSelected ? "checkmark.square.fill" : "square"
        }
    }
}
