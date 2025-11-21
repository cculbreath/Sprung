//
//  CoverLetterInspectorView.swift
//  Sprung
//
//  Created on 6/9/25.
//

import SwiftUI

/// A view showing metadata about the cover letter generation and committee feedback
struct CoverLetterInspectorView: View {
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(OpenRouterService.self) private var openRouterService: OpenRouterService

    @Binding var isEditing: Bool
    @Namespace private var namespace
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with glass effect
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cover Letter Details")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    if let coverLetter = coverLetterStore.cL {
                        Text(coverLetter.sequencedName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Navigation arrows for browsing cover letters
                if let coverLetter = coverLetterStore.cL {
                    CoverLetterNavigationButtons(
                        currentLetter: coverLetter,
                        namespace: namespace
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .rect(cornerRadius: 0))
            
            if let coverLetter = coverLetterStore.cL {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Action buttons
                        ActionButtonsView(
                            coverLetter: coverLetter,
                            isEditing: $isEditing,
                            namespace: namespace,
                            onToggleChosen: { toggleChosenSubmissionDraft(for: coverLetter) },
                            onDelete: { deleteCoverLetter(coverLetter) }
                        )
                        
                        // Generation metadata
                        GenerationInfoView(
                            coverLetter: coverLetter,
                            openRouterService: openRouterService
                        )
                        
                        // Sources used
                        SourcesUsedView(coverLetter: coverLetter)
                        
                        // Committee feedback (if available)
                        if coverLetter.hasBeenAssessed || coverLetter.committeeFeedback != nil {
                            CommitteeAnalysisView(
                                coverLetter: coverLetter,
                                openRouterService: openRouterService,
                                getTotalScore: getTotalScore,
                                getRanking: getRanking,
                                getMedalIndicator: getMedalIndicator,
                                getMedalColor: getMedalColor,
                                getScoreColor: getScoreColor,
                                getRankingText: getRankingText,
                                pointsColor: pointsColor
                            )
                        }
                    }
                    .padding(16)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                        .opacity(0.5)
                    
                    Text("No cover letter selected")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(alignment: .center)
                .padding()
                .glassEffect(.regular, in: .rect(cornerRadius: 8))
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func pointsColor(for points: Int) -> Color {
        switch points {
        case 8...10:
            return .green
        case 6...7:
            return .blue
        case 4...5:
            return .orange
        default:
            return .red
        }
    }
    
    // MARK: - Medal System Helper Functions
    private func getTotalScore(for coverLetter: CoverLetter) -> Int {
        return max(coverLetter.voteCount, coverLetter.scoreCount)
    }
    
    private func getRankedLetters() -> [CoverLetter] {
        guard let jobApp = jobAppStore.selectedApp else { return [] }
        
        return jobApp.coverLetters
            .filter { getTotalScore(for: $0) > 0 }
            .sorted { getTotalScore(for: $0) > getTotalScore(for: $1) }
    }
    
    private func getRanking(for coverLetter: CoverLetter) -> Int? {
        let rankedLetters = getRankedLetters()
        guard let index = rankedLetters.firstIndex(where: { $0.id == coverLetter.id }) else { return nil }
        let ranking = index + 1
        return ranking <= 5 ? ranking : nil
    }
    
    private func getMedalIndicator(for coverLetter: CoverLetter) -> String? {
        guard let ranking = getRanking(for: coverLetter) else { return nil }
        
        switch ranking {
        case 1...3:
            return "medal.fill"
        case 4, 5:
            return "star.circle.fill"
        default:
            return nil
        }
    }
    
    private func getMedalColor(for coverLetter: CoverLetter) -> Color {
        guard let ranking = getRanking(for: coverLetter) else { return .secondary }
        
        switch ranking {
        case 1:
            return Color(red: 1.0, green: 0.84, blue: 0) // Gold
        case 2:
            return Color(red: 0.75, green: 0.75, blue: 0.75) // Silver
        case 3:
            return Color(red: 0.8, green: 0.5, blue: 0.2) // Bronze
        case 4, 5:
            return .blue
        default:
            return .secondary
        }
    }
    
    private func getScoreColor(for score: Int) -> Color {
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
    
    private func getRankingText(for ranking: Int) -> String {
        switch ranking {
        case 1:
            return "First Place"
        case 2:
            return "Second Place"
        case 3:
            return "Third Place"
        case 4:
            return "Fourth Place"
        case 5:
            return "Fifth Place"
        default:
            return ""
        }
    }
    
    private func toggleChosenSubmissionDraft(for coverLetter: CoverLetter) {
        // Toggle chosen status - if already chosen, unmark it
        // If not chosen, mark it (which will automatically unmark others)
        if coverLetter.isChosenSubmissionDraft {
            // Unmark this one by setting selectedCover to nil
            if let jobApp = jobAppStore.selectedApp {
                jobApp.selectedCover = nil
            }
        } else {
            // Mark this one as chosen (automatically unmarks others)
            coverLetter.markAsChosenSubmissionDraft()
        }
    }
    
    private func deleteCoverLetter(_ coverLetter: CoverLetter) {
        guard let jobApp = jobAppStore.selectedApp else { return }
        
        coverLetterStore.deleteLetter(coverLetter)
        
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

// Helper view for consistent metadata rows
struct MetadataRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            
            Text(value)
                .font(.system(size: 11))
                .foregroundColor(.primary)
            
            Spacer()
        }
        .frame(height: 24)
    }
}

// Helper button components
struct EditToggleButton: View {
    @Binding var isEditing: Bool
    let namespace: Namespace.ID
    @State private var isHovering = false
    
    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                isEditing.toggle()
            }
        }) {
            Image(systemName: isEditing ? "doc.text.viewfinder" : "pencil")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(buttonColor)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(glassColor), in: .circle)
        .glassEffectID("edit", in: namespace)
        .help(isEditing ? "View Mode" : "Edit Mode")
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private var buttonColor: Color {
        if isEditing {
            return isHovering ? .orange : .blue
        } else {
            return isHovering ? .blue : .secondary
        }
    }
    
    private var glassColor: Color {
        if isEditing {
            return isHovering ? .orange.opacity(0.3) : .blue.opacity(0.3)
        } else {
            return isHovering ? .blue.opacity(0.3) : .secondary.opacity(0.1)
        }
    }
}

struct StarToggleButton: View {
    let coverLetter: CoverLetter
    let action: () -> Void
    let namespace: Namespace.ID
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(buttonColor)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(glassColor), in: .circle)
        .glassEffectID("star", in: namespace)
        .disabled(!coverLetter.generated)
        .opacity(coverLetter.generated ? 1.0 : 0.5)
        .help(coverLetter.isChosenSubmissionDraft ? "Unmark as Chosen" : "Mark as Chosen")
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private var iconName: String {
        if coverLetter.isChosenSubmissionDraft {
            return isHovering ? "star" : "star.fill"
        } else {
            return isHovering ? "star.fill" : "star"
        }
    }
    
    private var buttonColor: Color {
        if coverLetter.isChosenSubmissionDraft {
            return isHovering ? .secondary : .yellow
        } else {
            return isHovering ? .yellow : .secondary
        }
    }
    
    private var glassColor: Color {
        if coverLetter.isChosenSubmissionDraft {
            return isHovering ? .secondary.opacity(0.1) : .yellow.opacity(0.3)
        } else {
            return isHovering ? .yellow.opacity(0.3) : .secondary.opacity(0.1)
        }
    }
}

struct DeleteButton: View {
    let action: () -> Void
    let namespace: Namespace.ID
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isHovering ? .red : .secondary)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(isHovering ? .red.opacity(0.3) : .secondary.opacity(0.1)), in: .circle)
        .glassEffectID("delete", in: namespace)
        .help("Delete Cover Letter")
        .onHover { hovering in
            isHovering = hovering
        }
    }
}


struct CoverLetterNavigationButtons: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    
    let currentLetter: CoverLetter
    let namespace: Namespace.ID
    
    @State private var isHoveringPrev = false
    @State private var isHoveringNext = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Previous button
            Button(action: navigateToPrevious) {
                Image(systemName: "chevron.left.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(canNavigatePrevious ? (isHoveringPrev ? .accentColor : .secondary) : .secondary.opacity(0.3))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(isHoveringPrev && canNavigatePrevious ? .accentColor.opacity(0.3) : .clear), in: .circle)
            .glassEffectID("nav-prev", in: namespace)
            .disabled(!canNavigatePrevious)
            .help("Previous Cover Letter")
            .onHover { hovering in
                isHoveringPrev = hovering
            }
            
            // Next button
            Button(action: navigateToNext) {
                Image(systemName: "chevron.right.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(canNavigateNext ? (isHoveringNext ? .accentColor : .secondary) : .secondary.opacity(0.3))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(isHoveringNext && canNavigateNext ? .accentColor.opacity(0.3) : .clear), in: .circle)
            .glassEffectID("nav-next", in: namespace)
            .disabled(!canNavigateNext)
            .help("Next Cover Letter")
            .onHover { hovering in
                isHoveringNext = hovering
            }
        }
    }
    
    private var availableLetters: [CoverLetter] {
        guard let jobApp = jobAppStore.selectedApp else { return [] }
        return sortCoverLetters(jobApp.coverLetters)
    }
    
    /// Sort cover letters using the same logic as CoverLetterPicker
    private func sortCoverLetters(_ letters: [CoverLetter]) -> [CoverLetter] {
        return letters.sorted { letter1, letter2 in
            // First, separate assessed from unassessed
            if letter1.hasBeenAssessed != letter2.hasBeenAssessed {
                return letter1.hasBeenAssessed && !letter2.hasBeenAssessed
            }
            
            // If both are assessed, sort by vote/score count (descending)
            if letter1.hasBeenAssessed && letter2.hasBeenAssessed {
                let score1 = max(letter1.voteCount, letter1.scoreCount)
                let score2 = max(letter2.voteCount, letter2.scoreCount)
                if score1 != score2 {
                    return score1 > score2
                }
            }
            
            // Otherwise, sort by modification date (most recent first)
            return letter1.moddedDate > letter2.moddedDate
        }
    }
    
    private var currentIndex: Int? {
        availableLetters.firstIndex { $0.id == currentLetter.id }
    }
    
    private var canNavigatePrevious: Bool {
        guard let index = currentIndex else { return false }
        return index > 0
    }
    
    private var canNavigateNext: Bool {
        guard let index = currentIndex else { return false }
        return index < availableLetters.count - 1
    }
    
    private func navigateToPrevious() {
        guard let index = currentIndex, canNavigatePrevious else { return }
        let previousLetter = availableLetters[index - 1]
        navigateToLetter(previousLetter)
    }
    
    private func navigateToNext() {
        guard let index = currentIndex, canNavigateNext else { return }
        let nextLetter = availableLetters[index + 1]
        navigateToLetter(nextLetter)
    }
    
    private func navigateToLetter(_ letter: CoverLetter) {
        withAnimation(.easeInOut(duration: 0.3)) {
            jobAppStore.selectedApp?.selectedCover = letter
            coverLetterStore.cL = letter
        }
    }
}

