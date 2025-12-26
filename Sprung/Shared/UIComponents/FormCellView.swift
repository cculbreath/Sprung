//
//  FormCellView.swift
//  Sprung
//
//
import AppKit
import SwiftUI
struct Cell: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore?
    @Environment(\.openURL) private var openURL
    var leading: String
    var trailingKeys: KeyPath<JobApp, String>
    var formTrailingKeys: WritableKeyPath<JobAppForm, String>
    @Binding var isEditing: Bool
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
                        let value = app[keyPath: trailingKeys]
                        let isLink = isValidURL(value)
                        if isLink {
                            // Clickable link text
                            Button(action: {
                                if let url = URL(string: value) {
                                    openURL(url)
                                }
                            }) {
                                Text(value)
                                    .foregroundColor(.accentColor)
                                    .lineLimit(1)
                                    .underline()
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Click to open in browser, right-click to copy")
                            .contextMenu {
                                Button("Copy URL") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(value, forType: .string)
                                }
                                Button("Open in Browser") {
                                    if let url = URL(string: value) {
                                        openURL(url)
                                    }
                                }
                            }
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.accentColor)
                                .font(.caption)
                        } else {
                            Text(value.isEmpty ? "none listed" : value)
                                .foregroundColor(.secondary)
                                .italic(value.isEmpty)
                                .lineLimit(1)
                                .textSelection(.enabled)
                        }
                    } else {
                        Text("No app selected")
                            .foregroundColor(.red)
                    }
                }
            }
        }
    }
    private func isValidURL(_ urlString: String) -> Bool {
        guard !urlString.isEmpty,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }
}
