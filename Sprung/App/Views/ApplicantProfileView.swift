//
//  ApplicantProfileView.swift
//  Sprung
//
//  Created by Christopher Culbreath on 4/21/25.
//

import AppKit
import Observation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ApplicantProfileView: View {
    @Environment(ApplicantProfileStore.self) private var profileStore: ApplicantProfileStore

    @State private var profile: ApplicantProfile?
    @State private var draft = ApplicantProfileDraft()
    @State private var successMessage = ""
    @State private var hasChanges = false
    @State private var isLoading = true

    var body: some View {
        VStack {
            if isLoading {
                ProgressView("Loading profile…")
                    .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ApplicantProfileEditor(draft: $draft)
                            .onChange(of: draft) { _, _ in
                                hasChanges = true
                            }

                        signatureSection
                        actionsSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 750)
        .task {
            loadProfile()
            isLoading = false
        }
    }

    private var signatureSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Signature image will be used on cover letters and official documents.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    if let image = profile?.getSignatureImage() {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(height: 100)
                            .border(Color.gray.opacity(0.2), width: 1)
                            .background(Color.white)
                    } else {
                        Text("No signature uploaded")
                            .foregroundColor(.secondary)
                            .frame(height: 100)
                            .frame(maxWidth: .infinity)
                            .border(Color.gray.opacity(0.2), width: 1)
                            .background(Color.white)
                    }
                }

                HStack(spacing: 12) {
                    Button("Choose Image…") {
                        presentSignaturePicker()
                    }
                    .buttonStyle(.bordered)

                    if profile?.signatureData != nil {
                        Button("Remove") {
                            profile?.signatureData = nil
                            hasChanges = true
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.red)
                    }

                    Spacer()
                }
            }
        } label: {
            Text("Signature")
                .font(.headline)
        }
    }

    private var actionsSection: some View {
        GroupBox {
            HStack(alignment: .center, spacing: 12) {
                Button("Save Profile") {
                    Task {
                        await MainActor.run {
                            saveProfile()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasChanges)

                if !successMessage.isEmpty {
                    Text(successMessage)
                        .foregroundColor(.green)
                        .font(.callout)
                }

                Spacer()
            }
        } label: {
            Text("Actions")
                .font(.headline)
        }
    }

    private func presentSignaturePicker() {
        presentOpenPanel(allowedTypes: [.png, .jpeg, .pdf, .svg]) { url in
            do {
                let data = try Data(contentsOf: url)
                profile?.signatureData = data
                hasChanges = true
            } catch {
                Logger.error("ApplicantProfileView: Failed to load signature image: \(error)")
            }
        }
    }

    private func presentOpenPanel(allowedTypes: [UTType], completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = allowedTypes
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsOtherFileTypes = false
        panel.begin { response in
            guard response == .OK, let url = panel.urls.first else { return }
            Task { @MainActor in
                completion(url)
            }
        }
    }

    @MainActor
    private func loadProfile() {
        let current = profileStore.currentProfile()
        profile = current
        draft = ApplicantProfileDraft(profile: current)
        hasChanges = false
        successMessage = ""
    }

    @MainActor
    private func saveProfile() {
        guard let profile else { return }
        draft.apply(to: profile)
        profileStore.save(profile)
        successMessage = "Profile saved successfully"
        hasChanges = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            successMessage = ""
        }
    }
}
