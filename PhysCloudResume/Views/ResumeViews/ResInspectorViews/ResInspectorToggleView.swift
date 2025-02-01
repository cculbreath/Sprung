import AppKit // Import AppKit to use NSCursor
import SwiftUI

struct ResInspectorToggleView: View {
    // Access the ResRefStore from the environment.
    @Environment(ResRefStore.self) var resRefStore: ResRefStore
    // Bind to the Resume model.
    @Binding var res: Resume?

    // Define a grid layout with two flexible columns.
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
    ]

    var body: some View {
        if let res = res {
            VStack {
                // Centered headline
                Text("Enabled Background Sources")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 2)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 2) {
                    ForEach(resRefStore.resRefs, id: \.id) { resRef in
                        ResRefToggleCell(
                            resRef: resRef,
                            isEnabled: Binding<Bool>(
                                get: {
                                    // Check if this ResRef is in the resume’s enabledSources.
                                    res.enabledSources.contains { $0.id == resRef.id }
                                },
                                set: { newValue in
                                    if newValue {
                                        // Add the ResRef if it isn’t already present.
                                        if !res.enabledSources.contains(where: { $0.id == resRef.id }) {
                                            res.enabledSources.append(resRef)
                                        }
                                    } else {
                                        // Remove the ResRef if it is present.
                                        res.enabledSources.removeAll { $0.id == resRef.id }
                                    }
                                }
                            )
                        )
                    }
                }
            }
            .padding()
            .background(Color.white.opacity(0.3))
//            .overlay(
//              Rectangle()
//                .stroke(Color.white.opacity(0.5), lineWidth: 1)
//            )      .frame(alignment: .top)
        }
    }
}

struct ResRefToggleCell: View {
    var resRef: ResRef
    @Binding var isEnabled: Bool
    @State private var isHovered: Bool = false

    var body: some View {
        HStack {
            Toggle(resRef.name, isOn: $isEnabled)
                .toggleStyle(.checkbox) // macOS default checkbox style.
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(8)
        .background(isHovered ? Color.gray.opacity(0.2) : Color.clear)
        // Removed cornerRadius for a square appearance.
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
