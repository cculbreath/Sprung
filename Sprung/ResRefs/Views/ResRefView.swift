//
//  ResRefView.swift
//  Sprung
//
//  Created by Christopher Culbreath on 1/31/25.
//
import SwiftData
import SwiftUI
// A hover wrapper for each résumé reference row
struct HoverableResRefRowView: View {
    var sourceNode: ResRef
    @State private var isHovering: Bool = false
    var body: some View {
        ResRefRowView(sourceNode: sourceNode)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isHovering ? Color.gray.opacity(0.2) : Color.clear)
            .cornerRadius(5)
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}
struct ResRefView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(ResRefStore.self) private var resRefStore: ResRefStore
    // Live SwiftData list of references
    @Query(sort: \ResRef.name) private var resRefs: [ResRef]
    @State var isRefSheetPresented: Bool = false
    @State private var isHovering: Bool = false
    var body: some View {
        // Using @Bindable for jobAppStore if needed
        @Bindable var jobAppStore = jobAppStore
        VStack(alignment: .leading) {
            HStack {
                Text("Résumé Source Documents")
                    .font(.headline)
                Spacer()
            }
            .padding(10)
            .padding(.top, 10)
            .contentShape(Rectangle())
            VStack(alignment: .leading, spacing: 0) {
                ForEach(resRefs) { child in
                    Divider()
                    HoverableResRefRowView(sourceNode: child)
                        .transition(.move(edge: .top))
                        .contextMenu {
                            Button(role: .destructive) {
                                resRefStore.deleteResRef(child)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                Divider()
                HStack {
                    Button(action: { isRefSheetPresented = true }) {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text("Add Background Document")
                        }
                        .padding(8)
                        .background(isHovering ? Color(nsColor: .controlAccentColor).opacity(0.15) : Color.black.opacity(0.1))
                        .cornerRadius(8)
                        .foregroundColor(isHovering ? .accentColor : .primary)
                        .animation(.easeInOut(duration: 0.1), value: isHovering)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .padding()
                    .onHover { hovering in
                        withAnimation {
                            isHovering = hovering
                        }
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .sheet(isPresented: $isRefSheetPresented) {
                    ResRefFormView(isSheetPresented: $isRefSheetPresented)
                }
            }
        }
    }
}
