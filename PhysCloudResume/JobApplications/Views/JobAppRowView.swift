//
//  JobAppRowView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 1/30/25.
//

import SwiftUI

struct JobAppRowView: View {
    var jobApp: JobApp
    var deleteAction: () -> Void
    @Environment(\.appState) private var appState

    var body: some View {
        Text("\(jobApp.companyName): \(jobApp.jobPosition)")
            .tag(jobApp)
            .padding(.vertical, 4)
            .background(isRecommended ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(4)
            .animation(.easeInOut(duration: 0.3), value: isRecommended)
            .contextMenu {
                Button(role: .destructive, action: deleteAction) {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    private var isRecommended: Bool {
        appState.recommendedJobId == jobApp.id
    }
}
