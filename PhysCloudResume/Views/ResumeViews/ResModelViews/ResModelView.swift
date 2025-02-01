import SwiftData
import SwiftUI

// A hover wrapper for each résumé model row
struct HoverableResModelRowView: View {
    var sourceNode: ResModel // Replace with your actual model type
    @State private var isHovering: Bool = false

    var body: some View {
        ResModelRowView(sourceNode: sourceNode)
            .padding(.horizontal, 25)
            .padding(.vertical, 5)
            // Change background color when hovering
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

struct ResModelView: View {
    @Binding var refresh: Bool
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(ResModelStore.self) private var resModelStore: ResModelStore
    @State var isModelSheetPresented: Bool = false
    @State private var isAddButtonHovering: Bool = false

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Résumé Models")
                    .font(.headline)
                Spacer()
            }
            .padding(10)
            .padding(.horizontal, 20)
            .contentShape(Rectangle()) // Makes the entire header tappable if needed

            VStack(alignment: .leading, spacing: 0) {
                ForEach(resModelStore.resModels) { child in
                    Divider()
                    HoverableResModelRowView(sourceNode: child)
                        .transition(.move(edge: .top))
                        .contextMenu {
                            Button(role: .destructive) {
                                resModelStore.deleteResModel(child)
                                if let selApp = jobAppStore.selectedApp {
                                    if selApp.resumes.isEmpty {
                                        $refresh.wrappedValue = false
                                    } else if selApp.selectedRes == nil {
                                        selApp.selectedRes = selApp.resumes.first
                                        $refresh.wrappedValue = true
                                    }
                                }
                                print("Button Tab is now \($refresh.wrappedValue ? "true" : "false")")
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                Divider()

                Button(action: { isModelSheetPresented = true }) {
                    HStack(spacing: 3) {
                        Image(systemName: "plus.circle")
                        Text("Add Résumé Model")
                    }
                    .padding(8)
                    .background(isAddButtonHovering ? Color(nsColor: .controlAccentColor).opacity(0.15) : Color.black.opacity(0.1))
                    .cornerRadius(8)
                    .foregroundColor(isAddButtonHovering ? .accentColor : .primary)
                    .animation(.easeInOut(duration: 0.1), value: isAddButtonHovering)
                }
                .buttonStyle(BorderlessButtonStyle())
                .onHover { isHovering in
                    withAnimation {
                        isAddButtonHovering = isHovering
                    }
                }
                .padding()
                Spacer()

                    .frame(maxWidth: .infinity)
                    .sheet(isPresented: $isModelSheetPresented) {
                        ResModelFormView(sheetPresented: $isModelSheetPresented)
                    }
            }
        }
    }
}
