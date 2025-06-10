//
//  CoverLetterMetadataView.swift
//  PhysCloudResume
//
//  Created on 6/9/25.
//

import SwiftUI

/// A view showing metadata about the cover letter generation and committee feedback
struct CoverLetterMetadataView: View {
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(AppState.self) private var appState: AppState
    
    @Binding var isEditing: Bool
    
    @State private var isHoveringDelete = false
    @State private var isHoveringStar = false
    
    private var openRouterService: OpenRouterService {
        appState.openRouterService
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cover Letter Details")
                .font(.headline)
                .padding(.horizontal, 12)
            
            if let coverLetter = coverLetterStore.cL {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Action buttons
                        actionButtonsSection(for: coverLetter)
                        
                        // Generation metadata
                        generationMetadataSection(for: coverLetter)
                        
                        // Sources used
                        sourcesUsedSection(for: coverLetter)
                        
                        // Committee feedback (if available)
                        if coverLetter.hasBeenAssessed || coverLetter.committeeFeedback != nil {
                            committeeFeedbackSection(for: coverLetter)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.title)
                        .foregroundColor(.secondary)
                    
                    Text("No cover letter selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(alignment: .center)
            }
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private func actionButtonsSection(for coverLetter: CoverLetter) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                // Edit toggle button
                Button(action: {
                    isEditing.toggle()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: isEditing ? "doc.text.viewfinder" : "pencil")
                            .font(.caption)
                        Text(isEditing ? "View" : "Edit")
                            .font(.caption)
                    }
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                // Star toggle button
                Button(action: {
                    toggleChosenSubmissionDraft(for: coverLetter)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: coverLetter.isChosenSubmissionDraft ? "star.fill" : "star")
                            .font(.caption)
                        Text(coverLetter.isChosenSubmissionDraft ? "Chosen" : "Choose")
                            .font(.caption)
                    }
                    .foregroundColor(isHoveringStar ? .primary : (coverLetter.isChosenSubmissionDraft ? .yellow : .secondary))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(coverLetter.isChosenSubmissionDraft ? Color.yellow.opacity(0.2) : Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .onHover { hovering in isHoveringStar = hovering }
                .disabled(!coverLetter.generated)
                
                Spacer()
                
                // Delete button
                Button(action: {
                    deleteCoverLetter(coverLetter)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.caption)
                        Text("Delete")
                            .font(.caption)
                    }
                    .foregroundColor(isHoveringDelete ? .red : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isHoveringDelete ? Color.red.opacity(0.1) : Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .onHover { hovering in isHoveringDelete = hovering }
            }
        }
    }
    
    @ViewBuilder
    private func generationMetadataSection(for coverLetter: CoverLetter) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Generation Info")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 4) {
                if let model = coverLetter.generationModel {
                    HStack {
                        Text("Model:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(openRouterService.friendlyModelName(for: model))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                
                HStack {
                    Text("Created:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(coverLetter.createdDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                }
                
                if coverLetter.moddedDate != coverLetter.createdDate {
                    HStack {
                        Text("Modified:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(coverLetter.moddedDate.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                    }
                }
                
                HStack {
                    Text("Status:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(coverLetter.generated ? "Generated" : "Draft")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(coverLetter.generated ? .green : .orange)
                }
                
                if coverLetter.isChosenSubmissionDraft {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                        Text("Chosen for submission")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    @ViewBuilder
    private func sourcesUsedSection(for coverLetter: CoverLetter) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sources Used")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                // Resume background toggle status (use generation metadata if available)
                let usedResumeRefs = coverLetter.generated ? coverLetter.generationUsedResumeRefs : coverLetter.includeResumeRefs
                HStack {
                    Image(systemName: usedResumeRefs ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(usedResumeRefs ? .green : .secondary)
                        .font(.caption)
                    Text("Resume Background")
                        .font(.caption)
                        .foregroundColor(usedResumeRefs ? .primary : .secondary)
                }
                
                // Background facts (use generation metadata if available)
                let sourcesToShow = coverLetter.generated ? coverLetter.generationSources : coverLetter.enabledRefs
                let backgroundFacts = sourcesToShow.filter { $0.type == .backgroundFact }
                if !backgroundFacts.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Background Facts (\(backgroundFacts.count))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fontWeight(.medium)
                        
                        ForEach(backgroundFacts, id: \.id) { ref in
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "circle.fill")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 6))
                                    .padding(.top, 4)
                                
                                Text(ref.name)
                                    .font(.caption2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                
                // Writing samples (use generation metadata if available)
                let writingSamples = sourcesToShow.filter { $0.type == .writingSample }
                if !writingSamples.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Writing Samples (\(writingSamples.count))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fontWeight(.medium)
                        
                        ForEach(writingSamples, id: \.id) { ref in
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "circle.fill")
                                    .foregroundColor(.purple)
                                    .font(.system(size: 6))
                                    .padding(.top, 4)
                                
                                Text(ref.name)
                                    .font(.caption2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                
                if backgroundFacts.isEmpty && writingSamples.isEmpty && !usedResumeRefs {
                    Text("No additional sources used")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    @ViewBuilder
    private func committeeFeedbackSection(for coverLetter: CoverLetter) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Committee Analysis")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                // Prominent total score/votes with medal indicator
                HStack {
                    // Medal indicator for top 5 performers
                    if let medalImage = getMedalIndicator(for: coverLetter) {
                        Image(systemName: medalImage)
                            .foregroundColor(getMedalColor(for: coverLetter))
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        // Total score/votes prominently displayed
                        let totalScore = getTotalScore(for: coverLetter)
                        if totalScore > 0 {
                            HStack {
                                Text("Total Score:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(totalScore)")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(getScoreColor(for: totalScore))
                                Text(coverLetter.voteCount > 0 ? "votes" : "points")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            // Ranking indicator if this letter is in top 5
                            if let ranking = getRanking(for: coverLetter) {
                                Text(getRankingText(for: ranking))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(getMedalColor(for: coverLetter))
                            }
                        } else {
                            // Fallback to individual vote/score counts
                            HStack {
                                HStack {
                                    Text("Votes:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(coverLetter.voteCount)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                
                                Spacer()
                                
                                HStack {
                                    Text("Points:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(coverLetter.scoreCount)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                            }
                        }
                    }
                    
                    Spacer()
                }
                
                // Detailed committee feedback if available
                if let feedback = coverLetter.committeeFeedback {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Analysis Summary")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        
                        Text(feedback.summaryOfModelAnalysis)
                            .font(.caption2)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        if !feedback.pointsAwarded.isEmpty {
                            Text("Points Breakdown")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                            
                            ForEach(feedback.pointsAwarded, id: \.model) { award in
                                HStack {
                                    Text(openRouterService.friendlyModelName(for: award.model))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    Text("\(award.points) pts")
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .foregroundColor(pointsColor(for: award.points))
                                }
                            }
                            
                            // Total points
                            let totalPoints = feedback.pointsAwarded.reduce(0) { $0 + $1.points }
                            HStack {
                                Text("Total")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                
                                Spacer()
                                
                                Text("\(totalPoints) pts")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(pointsColor(for: totalPoints))
                            }
                            .padding(.top, 2)
                        }
                    }
                } else if coverLetter.hasBeenAssessed {
                    Text("Assessment completed, detailed analysis pending...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    private func pointsColor(for points: Int) -> Color {
        switch points {
        case 8...10:
            return .green
        case 6...7:
            return .orange
        case 4...5:
            return .yellow
        default:
            return .red
        }
    }
    
    // MARK: - Medal System Helper Functions
    
    /// Get the total score for a cover letter (votes or points)
    private func getTotalScore(for coverLetter: CoverLetter) -> Int {
        return max(coverLetter.voteCount, coverLetter.scoreCount)
    }
    
    /// Get all cover letters ranked by their total scores
    private func getRankedLetters() -> [CoverLetter] {
        guard let jobApp = jobAppStore.selectedApp else { return [] }
        
        return jobApp.coverLetters
            .filter { getTotalScore(for: $0) > 0 } // Only include letters with scores
            .sorted { getTotalScore(for: $0) > getTotalScore(for: $1) }
    }
    
    /// Get the ranking (1-5) of a cover letter, or nil if not in top 5
    private func getRanking(for coverLetter: CoverLetter) -> Int? {
        let rankedLetters = getRankedLetters()
        guard let index = rankedLetters.firstIndex(where: { $0.id == coverLetter.id }) else { return nil }
        let ranking = index + 1
        return ranking <= 5 ? ranking : nil
    }
    
    /// Get the medal system image for a cover letter
    private func getMedalIndicator(for coverLetter: CoverLetter) -> String? {
        guard let ranking = getRanking(for: coverLetter) else { return nil }
        
        switch ranking {
        case 1:
            return "medal.fill" // Gold medal
        case 2:
            return "medal.fill" // Silver medal (will be colored differently)
        case 3:
            return "medal.fill" // Bronze medal (will be colored differently)
        case 4, 5:
            return "star.circle.fill" // Star for 4th and 5th place
        default:
            return nil
        }
    }
    
    /// Get the color for medal indicators
    private func getMedalColor(for coverLetter: CoverLetter) -> Color {
        guard let ranking = getRanking(for: coverLetter) else { return .secondary }
        
        switch ranking {
        case 1:
            return .yellow // Gold
        case 2:
            return .gray // Silver
        case 3:
            return .orange // Bronze
        case 4, 5:
            return .blue // Star blue
        default:
            return .secondary
        }
    }
    
    /// Get the color for score display based on ranking
    private func getScoreColor(for score: Int) -> Color {
        // Use a dynamic color based on score magnitude
        switch score {
        case 15...Int.max:
            return .green
        case 10...14:
            return .blue
        case 5...9:
            return .orange
        case 1...4:
            return .red
        default:
            return .secondary
        }
    }
    
    /// Get descriptive text for ranking
    private func getRankingText(for ranking: Int) -> String {
        switch ranking {
        case 1:
            return "🥇 First Place"
        case 2:
            return "🥈 Second Place"
        case 3:
            return "🥉 Third Place"
        case 4:
            return "⭐ Fourth Place"
        case 5:
            return "⭐ Fifth Place"
        default:
            return ""
        }
    }
    
    private func toggleChosenSubmissionDraft(for coverLetter: CoverLetter) {
        coverLetter.markAsChosenSubmissionDraft()
    }
    
    private func deleteCoverLetter(_ coverLetter: CoverLetter) {
        guard let jobApp = jobAppStore.selectedApp else { return }
        
        // Delete the cover letter
        coverLetterStore.deleteLetter(coverLetter)
        
        // Set selected cover to the most recent generated letter or nil
        if let mostRecentGenerated = jobApp.coverLetters
            .filter({ $0.generated })
            .sorted(by: { $0.moddedDate > $1.moddedDate })
            .first {
            jobApp.selectedCover = mostRecentGenerated
            coverLetterStore.cL = mostRecentGenerated
        } else {
            jobApp.selectedCover = nil
            coverLetterStore.cL = nil
        }
    }
}