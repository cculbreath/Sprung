//
//  MultiModelChooseBestCoverLetterSheet.swift
//  Sprung
//
//  Created by Christopher Culbreath on 5/23/25.
//

import SwiftUI
import SwiftData

struct MultiModelChooseBestCoverLetterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) var appState: AppState
    @Environment(OpenRouterService.self) private var openRouterService: OpenRouterService

    @State private var selectedModels: Set<String> = []
    @State private var selectedVotingScheme: VotingScheme = .firstPastThePost
    @State private var showProgressSheet = false

    @Binding var coverLetter: CoverLetter
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                votingSchemeSection
                modelSelectionSection
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            actionSection
                .padding()
                .background(.regularMaterial)
        }
        .frame(width: 600, height: 500)
        .onAppear {
            // Load previously selected models
            selectedModels = appState.settings.multiModelSelectedModels
            
            // Fetch OpenRouter models if we don't have any and have a valid API key
            if appState.hasValidOpenRouterKey && openRouterService.availableModels.isEmpty {
                Task {
                    await openRouterService.fetchModels()
                }
            }
        }
        .onChange(of: selectedModels) { _, newValue in
            // Save selected models whenever they change
            appState.settings.multiModelSelectedModels = newValue
        }
        .sheet(isPresented: $showProgressSheet) {
            MultiModelProgressSheet(
                coverLetter: $coverLetter,
                selectedModels: selectedModels,
                selectedVotingScheme: selectedVotingScheme,
                onCompletion: {
                    dismiss() // Dismiss the original sheet when progress is complete
                }
            )
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Multi-Model Cover Letter Selection")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Select multiple models to vote on the best cover letter")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var votingSchemeSection: some View {
        GroupBox("Voting Method") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Voting Scheme", selection: $selectedVotingScheme) {
                    ForEach(VotingScheme.allCases, id: \.self) { scheme in
                        Text(scheme.rawValue)
                            .tag(scheme)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                
                Text(selectedVotingScheme.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private var modelSelectionSection: some View {
        CheckboxModelPicker(
            selectedModels: $selectedModels,
            title: "Select Models"
        )
    }
    
    private var actionSection: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            
            Spacer()
            
            Button("Choose Best Cover Letter") {
                showProgressSheet = true
            }
            .disabled(selectedModels.isEmpty)
            .buttonStyle(.borderedProminent)
        }
    }
}