//
//  FontNodeView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 2/27/25.
//

import SwiftData
import SwiftUI

struct FontNodeView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore

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
                            jobAppStore.selectedApp!.selectedRes!.debounceExport()
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
            if !isEditing { jobAppStore.selectedApp!.selectedRes!.debounceExport() }
        }

        .cornerRadius(5)
    }

    // MARK: - Actions
}
