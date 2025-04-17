import AppKit
import SwiftUI

struct Cell: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore?
    @Environment(\.openURL) private var openURL
    var leading: String
    var trailingKeys: KeyPath<JobApp, String>
    var formTrailingKeys: WritableKeyPath<JobAppForm, String>
    @Binding var isEditing: Bool
    //    @State private var isHovered: Bool = false

    var body: some View {
        HStack {
            Text(leading)
            Spacer()
            if isEditing {
                if let store = jobAppStore {
                    TextField(
                        "",
                        text: Binding(
                            get: { store.form[keyPath: formTrailingKeys] },
                            set: { store.form[keyPath: formTrailingKeys] = $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                } else {
                    Text("Error: Store not available")
                }
            } else {
                HStack {
                    if let app = jobAppStore?.selectedApp {
                        let val = app[keyPath: trailingKeys]
                        Text(val.isEmpty ? "none listed" : val)
                            .foregroundColor(false ? .blue : .secondary)
                            .italic(val.isEmpty)
                            .lineLimit(1)

                        if isValidURL(val) {
                            Button(action: {
                                if let url = URL(string: val) {
                                    openURL(url)
                                } else {
                                    print("URL Problem")
                                }
                            }) {
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundColor(
                                        false ? .blue : .secondary)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                    } else {
                        Text("No app selected")
                            .foregroundColor(.red)
                    }
                }
                //                .onHover { hover in
                //                    if let app = jobAppStore?.selectedApp {
                //                        let trailing = app[keyPath: trailingKeys]
                //                        if isValidURL(trailing) {
                //                            isHovered = hover
                //                        } else {
                //                            isHovered = false
                //                        }
                //
                //                    }
                //                }
            }
        }
        .onAppear {
            // Debugging print statements, safely
        }
    }

    private func isValidURL(_ urlString: String) -> Bool {
        if let url = URL(string: urlString) {
            return NSWorkspace.shared.urlForApplication(toOpen: url) != nil
        }
        return false
    }
}
