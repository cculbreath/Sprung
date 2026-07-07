//
//  SubmittedPacketsView.swift
//  Sprung
//
//  Read-only record of what was actually submitted for a job application
//  (app-audit 2026-07-06, resume-editor #2). This is the apply-track payoff:
//  weeks after applying, at interview-prep time, the user can see exactly which
//  resume version they sent and open the frozen PDF. Packets are minted by the
//  submit / export path (`ExportFileService.renderAndRecordPacket`); this view
//  only reads them via `JobAppStore.submittedPackets(for:)` (already sorted
//  newest-first) and opens the snapshotted bytes in the system PDF viewer.
//
import AppKit
import SwiftUI

struct SubmittedPacketsSection: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore

    let jobApp: JobApp

    @State private var packets: [SubmittedPacket] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SUBMITTED PACKETS")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            if packets.isEmpty {
                Text("Nothing submitted yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(packets) { packet in
                        packetRow(packet)
                    }
                }
            }
        }
        // The accessor is not itself observable, so reload when the view first
        // appears and whenever the app switches or a submit stamps a new date.
        .onAppear { reload() }
        .onChange(of: jobApp.id) { _, _ in reload() }
        .onChange(of: jobApp.status) { _, _ in reload() }
        .onChange(of: jobApp.appliedDate) { _, _ in reload() }
    }

    // MARK: - Row

    private func packetRow(_ packet: SubmittedPacket) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(rowTitle(for: packet))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    Label(Self.dateFormatter.string(from: packet.submittedDate), systemImage: "calendar")
                        .foregroundStyle(.secondary)
                    if let cover = packet.coverLetterText, !cover.isEmpty {
                        Label("Cover letter included", systemImage: "doc.text")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }

            Spacer(minLength: 8)

            Button {
                openPacketPDF(packet)
            } label: {
                Label("Open PDF", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func reload() {
        packets = jobAppStore.submittedPackets(for: jobApp)
    }

    /// The packet carries its own provenance label (copied from `Resume.label`
    /// at submit). Fall back to the template slug, then a generic title, so a
    /// packet frozen from an unlabeled resume still reads sensibly.
    private func rowTitle(for packet: SubmittedPacket) -> String {
        if !packet.label.isEmpty { return packet.label }
        if !packet.templateSlug.isEmpty { return packet.templateSlug }
        return "Submitted resume"
    }

    /// Write the frozen PDF bytes to a temp file and hand it to the system
    /// viewer (Preview), so the user gets print / save-as for free without a
    /// new in-app PDF surface.
    private func openPacketPDF(_ packet: SubmittedPacket) {
        let baseName = sanitize("\(jobApp.companyName) \(jobApp.jobPosition) — submitted \(Self.fileStampFormatter.string(from: packet.submittedDate))")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(baseName)
            .appendingPathExtension("pdf")
        do {
            try packet.resumePdfData.write(to: url)
            NSWorkspace.shared.open(url)
        } catch {
            Logger.error("Failed to open submitted packet PDF: \(error.localizedDescription)", category: .storage)
        }
    }

    private func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*:|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "_")
        return cleaned.isEmpty ? "submitted-packet" : cleaned
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let fileStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
