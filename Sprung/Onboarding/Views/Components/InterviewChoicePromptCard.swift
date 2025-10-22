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

            VStack(alignment: .leading, spacing: 10) {
                ForEach(prompt.options) { option in
                    choiceRow(for: option)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
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
                .fill(Color(nsColor: .underPageBackgroundColor))
        )
        .onAppear {
            if isSingleSelection {
                singleSelection = prompt.options.first?.id
            }
        }
    }

    @ViewBuilder
    private func choiceRow(for option: OnboardingChoiceOption) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                selectionControl(for: option)
                Text(option.title)
                    .font(.headline)
            }
            if let detail = option.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 26)
            }
        }
    }

    @ViewBuilder
    private func selectionControl(for option: OnboardingChoiceOption) -> some View {
        switch prompt.selectionStyle {
        case .single:
            Button {
                singleSelection = option.id
            } label: {
                Image(systemName: singleSelection == option.id ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(singleSelection == option.id ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
        case .multiple:
            Toggle(isOn: Binding(
                get: { multiSelection.contains(option.id) },
                set: { newValue in
                    if newValue {
                        multiSelection.insert(option.id)
                    } else {
                        multiSelection.remove(option.id)
                    }
                }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
        }
    }
}
