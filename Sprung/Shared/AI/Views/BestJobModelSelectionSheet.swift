//
//  BestJobModelSelectionSheet.swift
//  Sprung
//
//  Model selection sheet for Choose Best Jobs operation.
//  Remembers the last explicit selection; no substitute default otherwise.
//
import SwiftUI

/// Pre-flight model selection sheet for the Choose Best Jobs operation.
struct ChooseBestJobsSheet: View {
    @Binding var isPresented: Bool
    let onModelSelected: (String) -> Void

    @State private var selectedModel: String = ""
    @AppStorage("lastSelectedModel_best_job") private var lastSelectedModel: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Choose Model for Job Recommendations")
                    .font(.headline)
                    .padding(.top)

                DropdownModelPicker(
                    selectedModel: $selectedModel,
                    title: "AI Model"
                )

                Text("Selects the top 5 job matches from your identified applications using your knowledge cards and dossier.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                HStack(spacing: 12) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .buttonStyle(.bordered)

                    Button("Continue") {
                        lastSelectedModel = selectedModel
                        isPresented = false
                        onModelSelected(selectedModel)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedModel.isEmpty)
                }

                Spacer()
            }
            .padding()
            .frame(width: 450, height: 260)
            .onAppear {
                if !lastSelectedModel.isEmpty {
                    selectedModel = lastSelectedModel
                }
            }
        }
    }
}
