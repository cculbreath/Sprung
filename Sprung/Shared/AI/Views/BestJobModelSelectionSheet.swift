//
//  BestJobModelSelectionSheet.swift
//  Sprung
//
//  Model selection sheet for Choose Best Jobs operation.
//  Defaults to the Discovery settings model but allows override.
//
import SwiftUI

/// Pre-flight model selection sheet for the Choose Best Jobs operation.
/// Defaults to the Discovery settings model if no previous selection exists.
struct ChooseBestJobsSheet: View {
    @Binding var isPresented: Bool
    let onModelSelected: (String) -> Void

    @Environment(DiscoveryCoordinator.self) private var coordinator

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
                } else {
                    // Default to Discovery settings model
                    let discoveryModel = coordinator.settingsStore.current().llmModelId
                    if !discoveryModel.isEmpty {
                        selectedModel = discoveryModel
                    }
                }
            }
        }
    }
}
