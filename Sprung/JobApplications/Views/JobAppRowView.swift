//
//  JobAppRowView.swift
//  Sprung
//
//  Created by Christopher Culbreath on 1/31/25.
//
import SwiftUI
struct JobAppRowView: View {
    var jobApp: JobApp
    var deleteAction: () -> Void
    var body: some View {
        Text("\(jobApp.companyName): \(jobApp.jobPosition)")
            .tag(jobApp)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .contextMenu {
                Button(role: .destructive, action: deleteAction) {
                    Label("Delete", systemImage: "trash")
                }
            }
    }
    }
