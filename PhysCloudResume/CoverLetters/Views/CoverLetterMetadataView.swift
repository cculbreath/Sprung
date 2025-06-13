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
    @Namespace private var namespace
    
    private var openRouterService: OpenRouterService {
        appState.openRouterService
    }
    
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
    
    @ViewBuilder
    private func actionButtonsSection(for coverLetter: CoverLetter) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Actions")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            
            HStack(spacing: 12) {
                // Edit toggle button - blue when editing, orange on hover
                EditToggleButton(isEditing: $isEditing, namespace: namespace)
                
                // Star toggle button - yellow when chosen, can toggle on/off
                StarToggleButton(
                    coverLetter: coverLetter, 
                    action: { toggleChosenSubmissionDraft(for: coverLetter) },
                    namespace: namespace
                )
                
                Spacer()
                
                // Delete button - red on hover only
                DeleteButton(
                    action: { deleteCoverLetter(coverLetter) },
                    namespace: namespace
                )
            }
        }
    }
    
    @ViewBuilder
    private func generationMetadataSection(for coverLetter: CoverLetter) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Generation Info")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            
            VStack(alignment: .leading, spacing: 0) {
                if let model = coverLetter.generationModel {
                    MetadataRow(
                        label: "Model",
                        value: openRouterService.friendlyModelName(for: model)
                    )
                }
                
                MetadataRow(
                    label: "Created",
                    value: coverLetter.createdDate.formatted(date: .abbreviated, time: .shortened)
                )
                
                if coverLetter.moddedDate != coverLetter.createdDate {
                    MetadataRow(
                        label: "Modified",
                        value: coverLetter.moddedDate.formatted(date: .abbreviated, time: .shortened)
                    )
                }
                
                HStack(spacing: 0) {
                    Text("Status")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(coverLetter.generated ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                            .glassEffect(.regular.tint(coverLetter.generated ? .green : .orange), in: .circle)
                        Text(coverLetter.generated ? "Generated" : "Draft")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(coverLetter.generated ? .green : .orange)
                    }
                    
                    Spacer()
                }
                .frame(height: 24)
                
                if coverLetter.isChosenSubmissionDraft {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.system(size: 10))
                            .glassEffect(.regular.tint(.yellow), in: .circle)
                        Text("Chosen for submission")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .glassEffect(.regular.tint(.yellow.opacity(0.3)), in: .rect(cornerRadius: 12))
                }
            }
            .padding(10)
            .glassEffect(.regular, in: .rect(cornerRadius: 6))
        }
    }
    
    @ViewBuilder
    private func sourcesUsedSection(for coverLetter: CoverLetter) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sources Used")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            
            VStack(alignment: .leading, spacing: 12) {
                // Resume background toggle status
                let usedResumeRefs = coverLetter.generated ? coverLetter.generationUsedResumeRefs : coverLetter.includeResumeRefs
                HStack(spacing: 8) {
                    Image(systemName: usedResumeRefs ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(usedResumeRefs ? .green : .secondary)
                        .font(.system(size: 12))
                        .glassEffect(.regular.tint(usedResumeRefs ? .green.opacity(0.3) : .clear), in: .circle)
                    Text("Resume Background")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                }
                
                // Background facts
                let sourcesToShow = coverLetter.generated ? coverLetter.generationSources : coverLetter.enabledRefs
                let backgroundFacts = sourcesToShow.filter { $0.type == .backgroundFact }
                if !backgroundFacts.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Background Facts")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primary)
                            Text("(\(backgroundFacts.count))")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(backgroundFacts, id: \.id) { ref in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 4, height: 4)
                                        .padding(.top, 5)
                                        .glassEffect(.regular.tint(.blue), in: .circle)
                                    
                                    Text(ref.name)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        .padding(.leading, 8)
                    }
                }
                
                // Writing samples
                let writingSamples = sourcesToShow.filter { $0.type == .writingSample }
                if !writingSamples.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Writing Samples")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primary)
                            Text("(\(writingSamples.count))")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(writingSamples, id: \.id) { ref in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(Color.purple)
                                        .frame(width: 4, height: 4)
                                        .padding(.top, 5)
                                        .glassEffect(.regular.tint(.purple), in: .circle)
                                    
                                    Text(ref.name)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        .padding(.leading, 8)
                    }
                }
                
                if backgroundFacts.isEmpty && writingSamples.isEmpty && !usedResumeRefs {
                    Text("No additional sources used")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            .padding(10)
            .glassEffect(.regular, in: .rect(cornerRadius: 6))
        }
    }
    
    @ViewBuilder
    private func committeeFeedbackSection(for coverLetter: CoverLetter) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Committee Analysis")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            
            VStack(alignment: .leading, spacing: 12) {
                // Total score/votes with medal indicator
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        let totalScore = getTotalScore(for: coverLetter)
                        if totalScore > 0 {
                            VStack(spacing: 2) {
                                Text("\(totalScore)")
                                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                                    .foregroundColor(getScoreColor(for: totalScore))
                                Text(coverLetter.voteCount > 0 ? "votes" : "points")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .glassEffect(.regular.tint(getScoreColor(for: totalScore).opacity(0.2)), in: .rect(cornerRadius: 8))
                        } else {
                            HStack(spacing: 16) {
                                HStack(spacing: 4) {
                                    Text("Votes:")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    Text("\(coverLetter.voteCount)")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                
                                HStack(spacing: 4) {
                                    Text("Points:")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    Text("\(coverLetter.scoreCount)")
                                        .font(.system(size: 11, weight: .medium))
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .glassEffect(.regular, in: .rect(cornerRadius: 6))
                        }
                    }
                    
                    Spacer()
                    
                    // Medal and ranking on the right
                    if let ranking = getRanking(for: coverLetter) {
                        VStack(spacing: 8) {
                            // Medal indicator with glass effect
                            if let medalImage = getMedalIndicator(for: coverLetter) {
                                Image(systemName: medalImage)
                                    .foregroundColor(.primary)
                                    .font(.system(size: 28, weight: .medium))
                                    .padding(10)
                                    .glassEffect(.regular.tint(getMedalColor(for: coverLetter).opacity(0.3)), in: .circle)
                            }
                            
                            Text(getRankingText(for: ranking))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                                .fixedSize()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .glassEffect(.regular.tint(getMedalColor(for: coverLetter).opacity(0.15)), in: .capsule)
                        }
                    }
                }
                
                // Detailed committee feedback if available
                if let feedback =  coverLetter.committeeFeedback {
                    Divider()
                        .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        if !feedback.summaryOfModelAnalysis.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Analysis Summary")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                                if let jobApp = coverLetter.jobApp {
                                    Text(jobApp.replaceUUIDsWithLetterNames(in:feedback.summaryOfModelAnalysis))
                                        .font(.system(size: 11))
                                        .foregroundColor(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        
                        if !feedback.pointsAwarded.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Points Breakdown")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                                
                                VStack(spacing: 2) {
                                    ForEach(feedback.pointsAwarded, id: \.model) { award in
                                        HStack {
                                            Text(openRouterService.friendlyModelName(for: award.model))
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                            
                                            Spacer()
                                            
                                            Text("\(award.points)")
                                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                                .foregroundColor(pointsColor(for: award.points))
                                            Text("pts")
                                                .font(.system(size: 9))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    Divider()
                                        .padding(.vertical, 2)
                                    
                                    let totalPoints = feedback.pointsAwarded.reduce(0) { $0 + $1.points }
                                    HStack {
                                        Text("Total")
                                            .font(.system(size: 10, weight: .semibold))
                                        
                                        Spacer()
                                        
                                        Text("\(totalPoints)")
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundColor(pointsColor(for: totalPoints))
                                        Text("pts")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } else if coverLetter.hasBeenAssessed {
                    Text("Assessment completed, detailed analysis pending...")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            .padding(10)
            .glassEffect(.regular, in: .rect(cornerRadius: 6))
        }
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

