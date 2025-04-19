//
//  JobAppRowView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 1/30/25.
//

// JobAppRowView.swift

import SwiftUI

struct JobAppRowView: View {
    var jobApp: JobApp
    var deleteAction: () -> Void

    var body: some View {
        Text("\(jobApp.companyName): \(jobApp.jobPosition)")
            .tag(jobApp)
            .contextMenu {
                Button(role: .destructive, action: deleteAction) {
                    Label("Delete", systemImage: "trash")
                }
            }
    }
}
