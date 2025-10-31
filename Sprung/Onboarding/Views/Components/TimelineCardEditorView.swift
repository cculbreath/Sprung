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
                Text("Edit experiences directly, reorder them with the arrow controls, and save to share updates with the assistant.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                withAnimation { cards.append(TimelineCard()) }
            } label: {
                Label("Add Card", systemImage: "plus")
            }
        }
    }

    private var cardList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    TimelineCardForm(
                        card: Binding(
                            get: { cards[index] },
                            set: { cards[index] = $0 }
                        ),
                        index: index,
                        totalCount: cards.count,
                        onMoveUp: { moveCard(at: index, offset: -1) },
                        onMoveDown: { moveCard(at: index, offset: 1) },
                        onRemove: { remove(at: index) }
                    )
                    .id(card.id)
                }
            }
            .padding(.vertical, 4)
        }
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
    }

    private func remove(at index: Int) {
        guard cards.indices.contains(index) else { return }
        withAnimation {
            cards.remove(at: index)
        }
    }

    private func moveCard(at index: Int, offset: Int) {
        let newIndex = max(0, min(cards.count - 1, index + offset))
        guard cards.indices.contains(index), index != newIndex else { return }
        withAnimation {
            let card = cards.remove(at: index)
            cards.insert(card, at: newIndex)
        }
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
    let index: Int
    let totalCount: Int
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                reorderControls

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

                ForEach(Array(card.highlights.enumerated()), id: \.offset) { highlightIndex, _ in
                    HStack(alignment: .top, spacing: 8) {
                        TextField("Highlight", text: Binding(
                            get: { card.highlights[highlightIndex] },
                            set: { card.highlights[highlightIndex] = $0 }
                        ), axis: .vertical)
                        .textFieldStyle(.roundedBorder)

                        Button(role: .destructive) {
                            card.highlights.remove(at: highlightIndex)
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

    private var reorderControls: some View {
        VStack(spacing: 6) {
            Button(action: onMoveUp) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .disabled(index == 0)

            Button(action: onMoveDown) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .disabled(index >= totalCount - 1)
        }
        .padding(.top, 4)
    }
}
