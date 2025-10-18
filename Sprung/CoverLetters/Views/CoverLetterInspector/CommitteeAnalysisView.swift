//
//  CommitteeAnalysisView.swift
//  Sprung
//
//  Created on 6/13/25.
//

import SwiftUI

struct CommitteeAnalysisView: View {
    let coverLetter: CoverLetter
    let openRouterService: OpenRouterService
    let getTotalScore: (CoverLetter) -> Int
    let getRanking: (CoverLetter) -> Int?
    let getMedalIndicator: (CoverLetter) -> String?
    let getMedalColor: (CoverLetter) -> Color
    let getScoreColor: (Int) -> Color
    let getRankingText: (Int) -> String
    let pointsColor: (Int) -> Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Committee Analysis")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            
            VStack(alignment: .leading, spacing: 12) {
                // Total score/votes with medal indicator
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        let totalScore = getTotalScore(coverLetter)
                        if totalScore > 0 {
                            VStack(spacing: 2) {
                                Text("\(totalScore)")
                                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                                    .foregroundColor(getScoreColor(totalScore))
                                Text(coverLetter.voteCount > 0 ? "votes" : "points")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .glassEffect(.regular.tint(getScoreColor(totalScore).opacity(0.2)), in: .rect(cornerRadius: 8))
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
                    if let ranking = getRanking(coverLetter) {
                        VStack(spacing: 8) {
                            // Medal indicator with glass effect
                            if let medalImage = getMedalIndicator(coverLetter) {
                                Image(systemName: medalImage)
                                    .foregroundColor(.primary)
                                    .font(.system(size: 28, weight: .medium))
                                    .padding(10)
                                    .glassEffect(.regular.tint(getMedalColor(coverLetter).opacity(0.3)), in: .circle)
                            }
                            
                            Text(getRankingText(ranking))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                                .fixedSize()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .glassEffect(.regular.tint(getMedalColor(coverLetter).opacity(0.15)), in: .capsule)
                        }
                    }
                }
                
                // Detailed committee feedback if available
                if let feedback = coverLetter.committeeFeedback {
                    Divider()
                        .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        if !feedback.summaryOfModelAnalysis.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Analysis Summary")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                                if let jobApp = coverLetter.jobApp {
                                    Text(jobApp.replaceUUIDsWithLetterNames(in: feedback.summaryOfModelAnalysis))
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
                                                .foregroundColor(pointsColor(award.points))
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
                                            .foregroundColor(pointsColor(totalPoints))
                                        Text("pts")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        
                        // Vote-by-vote breakdown if available
                        if !feedback.modelVotes.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Vote-by-Vote Breakdown")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                                
                                VStack(spacing: 2) {
                                    ForEach(feedback.modelVotes, id: \.model) { vote in
                                        if let jobApp = coverLetter.jobApp,
                                           let votedLetter = jobApp.coverLetters.first(where: { $0.id.uuidString == vote.votedForLetterId }) {
                                            HStack {
                                                Text(openRouterService.friendlyModelName(for: vote.model))
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.secondary)
                                                
                                                Spacer()
                                                
                                                Image(systemName: "arrow.right")
                                                    .font(.system(size: 8))
                                                    .foregroundColor(.secondary)
                                                
                                                Text(votedLetter.sequencedName)
                                                    .font(.system(size: 10, weight: .medium))
                                                    .foregroundColor(.primary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else if coverLetter.hasBeenAssessed {
                    Logger.warning(
                        "CommitteeAnalysisView: cover letter assessed without committee feedback",
                        category: .ai,
                        metadata: ["coverLetterID": coverLetter.id.uuidString]
                    )
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
}
