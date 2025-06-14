//
//  SourcesUsedView.swift
//  PhysCloudResume
//
//  Created on 6/13/25.
//

import SwiftUI

struct SourcesUsedView: View {
    let coverLetter: CoverLetter
    
    var body: some View {
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
}