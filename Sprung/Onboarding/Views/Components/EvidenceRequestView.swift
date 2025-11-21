import SwiftUI
import UniformTypeIdentifiers
struct EvidenceRequestView: View {
    let coordinator: OnboardingInterviewCoordinator
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Evidence Requests")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            if coordinator.ui.evidenceRequirements.isEmpty {
                ContentUnavailableView(
                    "No Requests Yet",
                    systemImage: "magnifyingglass",
                    description: Text("The Lead Investigator is analyzing your timeline...")
                )
                .frame(height: 150)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(coordinator.ui.evidenceRequirements) { req in
                            EvidenceRequestCard(req: req, coordinator: coordinator)
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}
struct EvidenceRequestCard: View {
    let req: EvidenceRequirement
    let coordinator: OnboardingInterviewCoordinator
    
    @State private var isTargeted = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Status Icon
            Image(systemName: statusIcon)
                .font(.title2)
                .foregroundStyle(statusColor)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(req.description)
                    .font(.body)
                    .fontWeight(.medium)
                
                HStack {
                    Text(req.category.rawValue.capitalized)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                    
                    if req.status == .fulfilled {
                        Text("Fulfilled")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Text("Drag file here")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(12)
        .background(isTargeted ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard req.status != .fulfilled else { return false }
            
            guard let provider = providers.first else { return false }
            
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                if let url = url {
                    Task { @MainActor in
                        await coordinator.handleEvidenceUpload(url: url, requirementId: req.id)
                    }
                }
            }
            return true
        }
    }
    
    var statusIcon: String {
        switch req.status {
        case .requested: return "doc.badge.arrow.up"
        case .fulfilled: return "checkmark.circle.fill"
        case .skipped: return "xmark.circle"
        }
    }
    
    var statusColor: Color {
        switch req.status {
        case .requested: return .blue
        case .fulfilled: return .green
        case .skipped: return .secondary
        }
    }
}
