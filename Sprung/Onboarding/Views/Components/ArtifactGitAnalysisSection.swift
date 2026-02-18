import SwiftUI
import SwiftyJSON

/// Renders structured git repository analysis data: repository summary, technical skills,
/// notable achievements, AI collaboration profile, and keyword cloud.
struct ArtifactGitAnalysisSection: View {
    let analysis: JSON

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Repository summary
            if let repoSummary = analysis["repositorySummary"].dictionary {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.blue)
                        Text(analysis["repositorySummary"]["name"].stringValue)
                            .font(.caption.weight(.semibold))
                    }
                    Text(analysis["repositorySummary"]["description"].stringValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        if let domain = repoSummary["primaryDomain"]?.stringValue, !domain.isEmpty {
                            artifactBadgePill(domain, color: .blue)
                        }
                        if let projectType = repoSummary["projectType"]?.stringValue, !projectType.isEmpty {
                            artifactBadgePill(projectType, color: .purple)
                        }
                    }
                }
                .padding(8)
                .background(Color.blue.opacity(0.08))
                .cornerRadius(6)
            }

            // Technical skills
            if let skills = analysis["technicalSkills"].array, !skills.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Technical Skills (\(skills.count))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    FlowStack(spacing: 4) {
                        ForEach(skills.prefix(20).indices, id: \.self) { index in
                            let skill = skills[index]
                            let proficiency = skill["proficiencyLevel"].stringValue
                            let color = gitProficiencyColor(proficiency)
                            artifactBadgePill(skill["skillName"].stringValue, color: color)
                        }
                    }
                }
            }

            // Notable achievements
            if let achievements = analysis["notableAchievements"].array, !achievements.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notable Achievements (\(achievements.count))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(achievements.prefix(5).indices, id: \.self) { index in
                            let achievement = achievements[index]
                            HStack(alignment: .top, spacing: 4) {
                                Text("\u{2022}")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                                Text(achievement["resumeBullet"].stringValue)
                                    .font(.caption2)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }

            // AI collaboration profile
            if analysis["aiCollaborationProfile"]["detectedAiUsage"].exists() {
                let aiProfile = analysis["aiCollaborationProfile"]
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "brain")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                        Text("AI Collaboration")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        let detected = aiProfile["detectedAiUsage"].boolValue
                        artifactBadgePill(detected ? "AI Usage Detected" : "No AI Detected",
                                  color: detected ? .purple : .gray)
                        if let rating = aiProfile["collaborationQualityRating"].string {
                            artifactBadgePill(rating.replacingOccurrences(of: "_", with: " ").capitalized,
                                      color: .orange)
                        }
                    }
                }
            }

            // Keyword cloud
            if let keywords = analysis["keywordCloud"]["primary"].array, !keywords.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keywords")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    FlowStack(spacing: 4) {
                        ForEach(keywords.prefix(15).indices, id: \.self) { index in
                            artifactBadgePill(keywords[index].stringValue, color: .teal)
                        }
                    }
                }
            }
        }
    }
}

/// Maps a raw JSON proficiency string to a display color.
/// Local to this file since the string values only appear in git analysis payloads.
private func gitProficiencyColor(_ level: String) -> Color {
    switch level.lowercased() {
    case "expert": return .green
    case "proficient": return .blue
    case "competent": return .orange
    case "familiar": return .gray
    default: return .secondary
    }
}
