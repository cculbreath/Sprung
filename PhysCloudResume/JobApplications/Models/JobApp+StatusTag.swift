//
//  JobApp+StatusTag.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/16/25.
//

import SwiftUI

// MARK: – UI helpers for JobApp (kept outside the core model)

extension JobApp {
    /// Small colored pill used throughout the UI to visualise the current
    /// application status.  Declared in a SwiftUI‑only extension so that the
    /// JobApp data model itself stays free of any UI framework imports.
    @ViewBuilder
    var statusTag: some View {
        switch status {
        case .new:
            RoundedTagView(tagText: "New", backgroundColor: .green, foregroundColor: .white)
        case .inProgress:
            RoundedTagView(tagText: "In Progress", backgroundColor: .mint, foregroundColor: .white)
        case .unsubmitted:
            RoundedTagView(tagText: "Unsubmitted", backgroundColor: .cyan, foregroundColor: .white)
        case .submitted:
            RoundedTagView(tagText: "Submitted", backgroundColor: .indigo, foregroundColor: .white)
        case .interview:
            RoundedTagView(tagText: "Interview", backgroundColor: .pink, foregroundColor: .white)
        case .closed:
            RoundedTagView(tagText: "Closed", backgroundColor: .purple, foregroundColor: .white)
        case .followUp:
            RoundedTagView(tagText: "Follow Up", backgroundColor: .yellow, foregroundColor: .white)
        case .abandonned:
            RoundedTagView(tagText: "Abandoned", backgroundColor: .secondary, foregroundColor: .white)
        case .rejected:
            RoundedTagView(tagText: "Rejected", backgroundColor: .black, foregroundColor: .white)
        }
    }
}
