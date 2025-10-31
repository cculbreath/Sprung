import SwiftUI
import SwiftyJSON

struct TimelineCardEditorView: View {
    @Bindable var service: OnboardingInterviewService
    let timeline: JSON

    @State private var cards: [TimelineCard] = []
    @State private var baselineCards: [TimelineCard] = []
    @State private var meta: JSON?
    @State private var hasChanges = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var editMode: EditMode = .inactive

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            cardList
            footerButtons
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .onAppear { load(from: timeline) }
        .onChange(of: timeline) { _, newValue in
            load(from: newValue)
        }
        .onChange(of: cards) { _, newCards in
            hasChanges = newCards != baselineCards
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Timeline Cards")
                    .font(.title3.weight(.semibold))
                Text("Drag to reorder, edit in place, or add new experiences. Changes are shared with the assistant when you save.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    withAnimation { cards.append(TimelineCard()) }
                } label: {
                    Label("Add Card", systemImage: "plus")
                }

                ToggleEditModeButton(editMode: $editMode)
                    .disabled(cards.count < 2)
            }
        }
    }

    private var cardList: some View {
        List {
            ForEach($cards) { $card in
                TimelineCardForm(card: $card, onRemove: { remove(cardID: card.id) })
                    .listRowSeparator(.hidden)
                    .padding(.vertical, 6)
            }
            .onMove(perform: move)
        }
        .environment(\.editMode, $editMode)
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .frame(minHeight: 260)
    }

    private var footerButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button {
                    discardChanges()
                } label: {
                    Label("Discard Changes", systemImage: "arrow.uturn.backward")
                }
                .disabled(!hasChanges || isSaving)

                Button {
                    saveChanges()
                } label: {
                    Label(isSaving ? "Saving…" : "Save Timeline", systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasChanges || isSaving)
            }
        }
    }

    private func load(from timeline: JSON) {
        let state = TimelineCardAdapter.cards(from: timeline)
        cards = state.cards
        baselineCards = state.cards
        meta = state.meta
        hasChanges = false
        errorMessage = nil
        editMode = .inactive
    }

    private func remove(cardID: String) {
        if let index = cards.firstIndex(where: { $0.id == cardID }) {
            withAnimation {
                cards.remove(at: index)
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        cards.move(fromOffsets: source, toOffset: destination)
    }

    private func discardChanges() {
        withAnimation {
            cards = baselineCards
            hasChanges = false
        }
        errorMessage = nil
    }

    private func saveChanges() {
        guard hasChanges, isSaving == false else { return }
        let diff = TimelineDiffBuilder.diff(original: baselineCards, updated: cards)
        guard diff.isEmpty == false else {
            hasChanges = false
            errorMessage = nil
            return
        }

        isSaving = true
        errorMessage = nil

        Task {
            let updatedTimeline = await service.applyUserTimelineUpdate(cards: cards, meta: meta, diff: diff)
            await MainActor.run {
                load(from: updatedTimeline)
                isSaving = false
            }
        }
    }
}

private struct TimelineCardForm: View {
    @Binding var card: TimelineCard
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Title", text: $card.title, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...2)

                    TextField("Organization", text: $card.organization, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...2)

                    TextField("Location", text: $card.location, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...2)
                }

                VStack(alignment: .leading, spacing: 6) {
                    TextField("Start (e.g., 2018-05)", text: $card.start)
                        .textFieldStyle(.roundedBorder)

                    TextField("End (e.g., 2022-11 or present)", text: $card.end)
                        .textFieldStyle(.roundedBorder)

                    Button(role: .destructive, action: onRemove) {
                        Label("Remove Card", systemImage: "trash")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Summary")
                    .font(.subheadline.weight(.semibold))
                TextEditor(text: $card.summary)
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Highlights")
                    .font(.subheadline.weight(.semibold))

                ForEach(Array(card.highlights.enumerated()), id: \.offset) { index, _ in
                    HStack(alignment: .top, spacing: 8) {
                        TextField("Highlight", text: Binding(
                            get: { card.highlights[index] },
                            set: { card.highlights[index] = $0 }
                        ), axis: .vertical)
                        .textFieldStyle(.roundedBorder)

                        Button(role: .destructive) {
                            card.highlights.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Button {
                    card.highlights.append("")
                } label: {
                    Label("Add Highlight", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct ToggleEditModeButton: View {
    @Binding var editMode: EditMode

    var body: some View {
        Button {
            editMode = editMode == .active ? .inactive : .active
        } label: {
            Label(
                editMode == .active ? "Stop Reordering" : "Reorder",
                systemImage: editMode == .active ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle"
            )
        }
    }
}
