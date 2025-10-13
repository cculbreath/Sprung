//
//  FormCellView.swift
//  Sprung
//
//  Created by Christopher Culbreath on 9/9/24.
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
                        Text(value.isEmpty ? "none listed" : value)
                            .foregroundColor(isLink ? .accentColor : .secondary)
                            .italic(value.isEmpty)
                            .lineLimit(1)

                        if isLink {
                            Button(action: {
                                if let url = URL(string: value) {
                                    openURL(url)
                                }
                            }) {
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(PlainButtonStyle())
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
        if let url = URL(string: urlString) {
            return NSWorkspace.shared.urlForApplication(toOpen: url) != nil
        }
        return false
    }
}
