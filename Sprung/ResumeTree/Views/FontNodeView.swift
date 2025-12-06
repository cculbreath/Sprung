//
//  FontNodeView.swift
//  Sprung
//
//
import SwiftData
import SwiftUI
struct FontNodeView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(AppEnvironment.self) private var appEnvironment: AppEnvironment
    @State var node: FontSizeNode
    // State variables for editing and hover actions.
    @State private var isEditing: Bool = false
    var body: some View {
        Stepper {
            HStack {
                Text(node.key)
                Spacer()
                if !isEditing {
                    Text(node.fontString).onTapGesture { isEditing = true }
                } else {
                    HStack(spacing: 0) {
                        TextField(
                            "",
                            value: $node.fontValue,
                            formatter: NumberFormatter()
                        )
                        .frame(width: 50, alignment: .trailing).multilineTextAlignment(.trailing)
                        .onSubmit {
                            isEditing = false
                            if let res = jobAppStore.selectedApp?.selectedRes {
                                appEnvironment.resumeExportCoordinator.debounceExport(resume: res)
                            } else {
                                Logger.debug("FontNodeView: No selected resume to export after edit submission")
                            }
                        }.padding(.trailing, 0)
                        Text("pt") // Postfix text (unit)
                            .foregroundColor(.secondary).padding(.leading, 0)
                    }
                }
            }.frame(maxWidth: .infinity)
        } onIncrement: {
            node.fontValue += 0.5
        } onDecrement: {
            node.fontValue -= 0.5
        }
        .padding(.horizontal, 5)
        .onChange(of: node.fontValue) {
            if !isEditing {
                if let res = jobAppStore.selectedApp?.selectedRes {
                    appEnvironment.resumeExportCoordinator.debounceExport(resume: res)
                } else {
                    Logger.debug("FontNodeView: No selected resume to export on value change")
                }
            }
        }
        .cornerRadius(5)
    }
}
