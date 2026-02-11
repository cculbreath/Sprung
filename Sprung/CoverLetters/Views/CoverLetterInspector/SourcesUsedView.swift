//
//  SourcesUsedView.swift
//  Sprung
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
                // Knowledge card inclusion status
                let kcInclusion = coverLetter.knowledgeCardInclusion
                HStack(spacing: 8) {
                    Image(systemName: kcInclusion != .none ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(kcInclusion != .none ? .green : .secondary)
                        .font(.system(size: 12))
                        .glassEffect(.regular.tint(kcInclusion != .none ? .green.opacity(0.3) : .clear), in: .circle)
                    Text("Knowledge Cards (\(kcInclusion.rawValue))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                }
                // Writing samples
                let sourcesToShow = coverLetter.generated ? coverLetter.generationSources : coverLetter.enabledRefs
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
                if writingSamples.isEmpty && kcInclusion == .none {
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
