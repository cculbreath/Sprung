//
//  MultiModelProgressSheet.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 6/10/25.
//

import SwiftUI
import SwiftData

struct MultiModelProgressSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) var appState: AppState
    @Environment(JobAppStore.self) var jobAppStore: JobAppStore
    @Environment(CoverLetterStore.self) var coverLetterStore: CoverLetterStore
    @Environment(EnabledLLMStore.self) var enabledLLMStore: EnabledLLMStore
    @Environment(LLMFacade.self) var llmFacade: LLMFacade
    
    @Binding var coverLetter: CoverLetter
    let selectedModels: Set<String>
    let selectedVotingScheme: VotingScheme
    let onCompletion: () -> Void
    
    @State private var service = MultiModelCoverLetterService()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                
                if service.isProcessing {
                    progressSection
                }
                
                if !service.voteTally.isEmpty || !service.scoreTally.isEmpty || service.isProcessing {
                    resultsSection
                }
                
                if !service.failedModels.isEmpty {
                    failedModelsSection
                }
                
                if !service.modelReasonings.isEmpty || service.reasoningSummary != nil || service.isGeneratingSummary {
                    reasoningsSection
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            actionSection
                .padding()
                .background(.regularMaterial)
        }
        .frame(width: 700, height: 600)
        .onAppear {
            service.configure(
                appState: appState,
                jobAppStore: jobAppStore,
                coverLetterStore: coverLetterStore,
                enabledLLMStore: enabledLLMStore,
                llmFacade: llmFacade
            )
            service.startMultiModelSelection(
                coverLetter: coverLetter,
                selectedModels: selectedModels,
                selectedVotingScheme: selectedVotingScheme
            )
        }
        .onDisappear {
            service.cleanup()
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Multi-Model Cover Letter Analysis")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Running \(selectedVotingScheme.rawValue) with \(selectedModels.count) models")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var progressSection: some View {
        VStack(spacing: 12) {
            ProgressView(value: service.progress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle())
            
            Text("Processing \(service.completedOperations) of \(service.totalOperations) models...")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Show pending models when down to last few
            if service.pendingModels.count <= 3 && service.pendingModels.count > 0 && !service.isCompleted {
                let modelNames = Array(service.pendingModels).sorted()
                let formattedNames = service.formatModelNames(modelNames)
                Text("Awaiting response from \(formattedNames)")
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .italic()
            }
            
            if service.isGeneratingSummary {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Generating analysis summary...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var resultsSection: some View {
        GroupBox(selectedVotingScheme == .firstPastThePost ? "Live Vote Tally" : "Live Score Tally") {
            if let jobApp = jobAppStore.selectedApp {
                VStack(alignment: .leading, spacing: 8) {
                    if service.isProcessing && service.voteTally.isEmpty && service.scoreTally.isEmpty {
                        Text("Waiting for first results...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                    
                    ForEach(jobApp.coverLetters.sorted(by: { $0.sequencedName < $1.sequencedName }), id: \.id) { letter in
                        HStack {
                            Text(letter.sequencedName)
                                .fontWeight(service.getWinningLetter(for: selectedVotingScheme)?.id == letter.id ? .bold : .regular)
                            Spacer()
                            if selectedVotingScheme == .firstPastThePost {
                                let votes = service.voteTally[letter.id] ?? 0
                                Text("\(votes) vote\(votes == 1 ? "" : "s")")
                                    .foregroundColor(service.getWinningLetter(for: selectedVotingScheme)?.id == letter.id ? .green : .primary)
                                    .animation(.easeInOut(duration: 0.3), value: votes)
                            } else {
                                let points = service.scoreTally[letter.id] ?? 0
                                Text("\(points) point\(points == 1 ? "" : "s")")
                                    .foregroundColor(service.getWinningLetter(for: selectedVotingScheme)?.id == letter.id ? .green : .primary)
                                    .animation(.easeInOut(duration: 0.3), value: points)
                            }
                        }
                    }
                    
                    // Delete 0-vote letters button
                    if service.isCompleted && service.hasZeroVoteLetters(for: selectedVotingScheme) {
                        Divider()
                            .padding(.vertical, 4)
                        
                        Button(action: { service.deleteZeroVoteLetters(for: selectedVotingScheme) }) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete letters with 0 \(selectedVotingScheme == .firstPastThePost ? "votes" : "points")")
                            }
                            .foregroundColor(.red)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    private var failedModelsSection: some View {
        GroupBox("Failed Models") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(service.failedModels.sorted(by: { $0.key < $1.key }), id: \.key) { modelId, errorReason in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(modelId)
                                .font(.caption)
                                .fontWeight(.medium)
                            Spacer()
                        }
                        
                        Text(errorReason)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 2)
                    
                    if modelId != service.failedModels.keys.sorted().last {
                        Divider()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private var reasoningsSection: some View {
        GroupBox("Analysis Summary") {
            if service.isGeneratingSummary {
                VStack {
                    ProgressView("Generating summary...")
                        .progressViewStyle(CircularProgressViewStyle())
                        .padding()
                }
                .frame(maxHeight: 200)
            } else if let summary = service.reasoningSummary {
                ScrollView {
                    if let jobApp = coverLetter.jobApp {
                        Text(jobApp.replaceUUIDsWithLetterNames(in: summary))
                            .font(.system(.body))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(summary)
                            .font(.system(.body))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxHeight: 200)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(service.modelReasonings, id: \.model) { reasoning in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(reasoning.model)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                
                                if selectedVotingScheme == .firstPastThePost {
                                    if let bestUuid = reasoning.response.bestLetterUuid {
                                        Text("Selected: \(service.getLetterName(for: bestUuid) ?? "Unknown")")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                } else if let scoreAllocations = reasoning.response.scoreAllocations {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Score Allocations:")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                        ForEach(scoreAllocations, id: \.letterUuid) { allocation in
                                            HStack {
                                                Text("\(service.getLetterName(for: allocation.letterUuid) ?? "Unknown"):")
                                                Text("\(allocation.score) pts")
                                                    .fontWeight(.semibold)
                                                if let reasoning = allocation.reasoning {
                                                    Text("- \(reasoning)")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                        .lineLimit(2)
                                                }
                                            }
                                            .font(.caption2)
                                        }
                                    }
                                }
                                
                                // Replace UUIDs with letter names in the verdict text
                                if let jobApp = coverLetter.jobApp {
                                    Text(jobApp.replaceUUIDsWithLetterNames(in: reasoning.response.verdict))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text(reasoning.response.verdict)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Divider()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
            }
        }
    }
    
    private var actionSection: some View {
        HStack {
            if let errorMessage = service.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            Spacer()
            
            if service.isProcessing {
                Button("Cancel") {
                    service.cancelSelection()
                    dismiss()
                    onCompletion()
                }
                .disabled(false)
            } else {
                Button("Close") {
                    // Select the winning letter before dismissing
                    if let winningLetter = service.getWinningLetter(for: selectedVotingScheme) {
                        jobAppStore.selectedApp?.selectedCover = winningLetter
                    }
                    dismiss()
                    onCompletion()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
