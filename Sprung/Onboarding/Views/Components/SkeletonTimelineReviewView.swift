import SwiftUI
struct SkeletonTimelineReviewView: View {
    @Binding var draft: ExperienceDefaultsDraft
    @Binding var editingEntries: Set<UUID>
    var onChange: () -> Void
    private let renderers = ExperienceSectionRenderers.all
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(ExperienceSchema.sections) { section in
                        Toggle(isOn: binding(for: section)) {
                            Text(section.metadata.title)
                                .font(.subheadline)
                        }
                        .toggleStyle(.switch)
                    }
                }
                .padding(4)
            } label: {
                Text("Enabled Sections")
                    .font(.headline)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(renderers) { renderer in
                        if renderer.isEnabled(in: draft) {
                            renderer.render(in: $draft, callbacks: callbacks())
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                )
                                .padding(.horizontal, 4)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
    private func binding(for section: ExperienceSchemaSection) -> Binding<Bool> {
        let base = section.metadata.toggleBinding(in: $draft)
        return Binding(
            get: { base.wrappedValue },
            set: { newValue in
                base.wrappedValue = newValue
                onChange()
            }
        )
    }
    private func callbacks() -> ExperienceSectionViewCallbacks {
        ExperienceSectionViewCallbacks(
            isEditing: { id in editingEntries.contains(id) },
            beginEditing: { id in editingEntries.insert(id) },
            toggleEditing: { id in
                if editingEntries.contains(id) {
                    editingEntries.remove(id)
                } else {
                    editingEntries.insert(id)
                }
            },
            endEditing: { id in editingEntries.remove(id) },
            onChange: onChange
        )
    }
}
