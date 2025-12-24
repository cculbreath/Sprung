import SwiftUI
import SwiftyJSON

/// Tab content showing timeline/experience cards collected during the interview.
struct TimelineTabContent: View {
    let coordinator: OnboardingInterviewCoordinator

    private var experiences: [JSON] {
        coordinator.ui.skeletonTimeline?["experiences"].array ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if experiences.isEmpty {
                emptyState
            } else {
                ForEach(Array(experiences.enumerated()), id: \.offset) { _, experience in
                    TimelineCardRow(experience: experience)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Timeline Cards",
            systemImage: "calendar.badge.clock",
            description: Text("Timeline cards will appear here as they're created during the interview.")
        )
        .frame(height: 180)
    }
}

struct TimelineCardRow: View {
    let experience: JSON

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(experience["title"].stringValue)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    Text(experience["organization"].stringValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                experienceTypeBadge
            }

            HStack(spacing: 6) {
                if let start = experience["start"].string {
                    Text(formatDate(start))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if experience["start"].string != nil {
                    Text("–")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                let end = experience["end"].string ?? ""
                Text(end.isEmpty ? "Present" : formatDate(end))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var experienceTypeBadge: some View {
        let type = experience["experience_type"].string ?? "work"
        let (color, label) = typeInfo(for: type)

        Text(label)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .cornerRadius(4)
    }

    private func typeInfo(for type: String) -> (Color, String) {
        switch type {
        case "education": return (.purple, "Education")
        case "volunteer": return (.orange, "Volunteer")
        case "project": return (.green, "Project")
        default: return (.blue, "Work")
        }
    }

    private func formatDate(_ dateString: String) -> String {
        // Handle various ISO formats: YYYY, YYYY-MM, YYYY-MM-DD
        let components = dateString.split(separator: "-")
        guard let year = components.first else { return dateString }

        if components.count >= 2, let month = Int(components[1]) {
            let monthNames = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                              "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            if month > 0, month < 13 {
                return "\(monthNames[month]) \(year)"
            }
        }

        return String(year)
    }
}
