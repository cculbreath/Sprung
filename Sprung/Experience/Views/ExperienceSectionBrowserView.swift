import SwiftUI

struct ExperienceSectionBrowserView: View {
    @Binding var draft: ExperienceDefaultsDraft
    @State private var expandedSections: Set<ExperienceSectionKey> = Set(ExperienceSectionKey.allCases)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sections")
                    .font(.headline)
                    .padding(.top, 12)

                ForEach(ExperienceSchema.sections) { section in
                    DisclosureGroup(isExpanded: binding(for: section.key)) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(section.nodes) { node in
                                nodeView(node, indentLevel: 1)
                            }
                        }
                        .padding(.leading, 4)
                        .padding(.bottom, 4)
                    } label: {
                        HStack {
                            Text(section.metadata.title)
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: sectionToggle(for: section))
                                .labelsHidden()
                                .toggleStyle(.checkbox)
                        }
                        .padding(.vertical, 4)
                    }
                    .disclosureGroupStyle(.automatic)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func nodeView(_ node: ExperienceSchemaNode, indentLevel: Int) -> some View {
        switch node.kind {
        case .field(let name):
            return AnyView(
                HStack(spacing: 6) {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, CGFloat(indentLevel) * 12)
            )
        case .group(let name, let children):
            return AnyView(
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("▸")
                            .foregroundStyle(.secondary)
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, CGFloat(indentLevel) * 12)

                    ForEach(children) { child in
                        nodeView(child, indentLevel: indentLevel + 1)
                    }
                }
            )
        }
    }

    private func binding(for key: ExperienceSectionKey) -> Binding<Bool> {
        Binding(
            get: { expandedSections.contains(key) },
            set: { isExpanded in
                if isExpanded {
                    expandedSections.insert(key)
                } else {
                    expandedSections.remove(key)
                }
            }
        )
    }

    private func sectionToggle(for section: ExperienceSchemaSection) -> Binding<Bool> {
        section.metadata.toggleBinding(in: $draft)
    }
}
