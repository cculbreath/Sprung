//
//  GenerationInfoView.swift
//  PhysCloudResume
//
//  Created on 6/13/25.
//

import SwiftUI

struct GenerationInfoView: View {
    let coverLetter: CoverLetter
    let openRouterService: OpenRouterService
    
    var body: some View {
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
}