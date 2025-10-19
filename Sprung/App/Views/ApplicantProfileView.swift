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
    @State private var profile: ApplicantProfile
    @State private var successMessage = ""
    @State private var hasChanges = false
    @State private var isLoading = true
    @State private var selectedProfileID: UUID?
    @State private var hoveredProfileID: UUID?

    init() {
        // Initialize with a default profile, then update it in onAppear
        _profile = State(initialValue: ApplicantProfile())
    }

    var body: some View {
        VStack {
            if isLoading {
                ProgressView("Loading profile...")
                    .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                TextField("Name", text: $profile.name)
                                    .onChange(of: profile.name) { _, _ in hasChanges = true }
                                    .textFieldStyle(.roundedBorder)

                                TextField("Professional Label", text: $profile.label)
                                    .onChange(of: profile.label) { _, _ in hasChanges = true }
                                    .textFieldStyle(.roundedBorder)

                                TextField("Email", text: $profile.email)
                                    .onChange(of: profile.email) { _, _ in hasChanges = true }
                                    .textFieldStyle(.roundedBorder)

                                TextField("Phone", text: $profile.phone)
                                    .onChange(of: profile.phone) { _, _ in hasChanges = true }
                                    .textFieldStyle(.roundedBorder)

                                TextField("Websites", text: $profile.websites)
                                    .onChange(of: profile.websites) { _, _ in hasChanges = true }
                                    .textFieldStyle(.roundedBorder)
                            }
                        } label: {
                            Text("Personal Information")
                                .font(.headline)
                        }

                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Summary")
                                    .font(.subheadline.weight(.medium))
                                Text("Use a succinct 2–3 sentence summary that highlights your focus areas.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                TextEditor(text: $profile.summary)
                                    .onChange(of: profile.summary) { _, _ in hasChanges = true }
                                    .frame(minHeight: 120)
                                    .padding(6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                                    )
                            }
                        } label: {
                            Text("Professional Summary")
                                .font(.headline)
                        }

                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Profile photo appears on generated resumes where supported")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                HStack {
                                    if let image = profile.getPictureImage() {
                                        image
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 140, height: 140)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                            )
                                    } else {
                                        Text("No profile photo uploaded")
                                            .foregroundColor(.secondary)
                                            .frame(width: 140, height: 140)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                            )
                                    }
                                }

                                HStack {
                                    Button("Choose Photo...") {
                                        presentPicturePicker()
                                    }
                                    .buttonStyle(.bordered)

                                    if profile.pictureData != nil {
                                        Button("Remove Photo") {
                                            profile.updatePicture(data: nil, mimeType: nil)
                                            hasChanges = true
                                        }
                                        .buttonStyle(.bordered)
                                        .foregroundStyle(Color.red)
                                    }

                                    Spacer()
                                }
                            }
                        } label: {
                            Text("Profile Photo")
                                .font(.headline)
                        }

                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                if profile.profiles.isEmpty {
                                    VStack(alignment: .center, spacing: 8) {
                                        Text("No profiles added yet.")
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(Color.gray.opacity(0.15), lineWidth: 1)
                                    )
                                } else {
                                    VStack(spacing: 8) {
                                        ForEach(profile.profiles) { social in
                                            ApplicantSocialProfileRow(
                                                socialProfile: social,
                                                isSelected: selectedProfileID == social.id,
                                                isHovered: hoveredProfileID == social.id,
                                                onSelect: {
                                                    selectedProfileID = social.id
                                                },
                                                onHoverChange: { hovering in
                                                    hoveredProfileID = hovering ? social.id : nil
                                                },
                                                onDelete: {
                                                    removeProfile(social)
                                                },
                                                onEdit: {
                                                    hasChanges = true
                                                }
                                            )
                                        }
                                    }
                                }

                                HStack(spacing: 8) {
                                    Button {
                                        addProfile()
                                    } label: {
                                        Label("Add Profile", systemImage: "plus")
                                    }
                                    .buttonStyle(.bordered)

                                    Button {
                                        removeSelectedProfile()
                                    } label: {
                                        Label("Remove Selected", systemImage: "minus")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(selectedProfileID == nil)

                                    Spacer()
                                }
                            }
                        } label: {
                            Text("Social Links")
                                .font(.headline)
                        }

                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                TextField("Street Address", text: $profile.address)
                                    .onChange(of: profile.address) { _, _ in hasChanges = true }
                                    .textFieldStyle(.roundedBorder)

                                TextField("City", text: $profile.city)
                                    .onChange(of: profile.city) { _, _ in hasChanges = true }
                                    .textFieldStyle(.roundedBorder)

                                TextField("State", text: $profile.state)
                                    .onChange(of: profile.state) { _, _ in hasChanges = true }
                                    .textFieldStyle(.roundedBorder)

                                TextField("ZIP Code", text: $profile.zip)
                                    .onChange(of: profile.zip) { _, _ in hasChanges = true }
                                    .textFieldStyle(.roundedBorder)

                                TextField("Country Code", text: $profile.countryCode)
                                    .onChange(of: profile.countryCode) { _, _ in hasChanges = true }
                                    .textFieldStyle(.roundedBorder)
                            }
                        } label: {
                            Text("Mailing Address")
                                .font(.headline)
                        }

                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Signature image will be used on cover letters and official documents")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                HStack {
                                    if let image = profile.getSignatureImage() {
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

                                HStack {
                                    Button("Choose Image...") {
                                        presentSignaturePicker()
                                    }
                                    .buttonStyle(.bordered)

                                    if profile.signatureData != nil {
                                        Button("Remove") {
                                            profile.signatureData = nil
                                            hasChanges = true
                                        }
                                        .buttonStyle(.bordered)
                                        .foregroundStyle(Color.red)
                                    }

                                    Spacer()
                                }
                            }
                        } label: {
                            Text("Signature")
                                .font(.headline)
                        }

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

    private func presentSignaturePicker() {
        presentOpenPanel(allowedTypes: [.png, .jpeg, .pdf, .svg]) { url in
            do {
                let data = try Data(contentsOf: url)
                profile.signatureData = data
                hasChanges = true
            } catch {
                Logger.error("ApplicantProfileView: Failed to load signature image: \(error)")
            }
        }
    }

    private func presentPicturePicker() {
        presentOpenPanel(allowedTypes: [.png, .jpeg, .heic, .heif, .gif, .bmp, .tiff]) { url in
            do {
                let data = try Data(contentsOf: url)
                let resourceValues = try url.resourceValues(forKeys: [.contentTypeKey])
                let mimeType = resourceValues.contentType?.preferredMIMEType ?? "image/png"
                profile.updatePicture(data: data, mimeType: mimeType)
                hasChanges = true
            } catch {
                Logger.error("ApplicantProfileView: Failed to load profile photo: \(error)")
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
        profile = profileStore.currentProfile()
    }

    @MainActor
    private func saveProfile() {
        profileStore.save(profile)
        successMessage = "Profile saved successfully"
        hasChanges = false
        selectedProfileID = nil
        hoveredProfileID = nil

        // Clear success message after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            successMessage = ""
        }
    }

    private func addProfile() {
        let newProfile = ApplicantSocialProfile()
        newProfile.applicant = profile
        profile.profiles.append(newProfile)
        selectedProfileID = newProfile.id
        hoveredProfileID = newProfile.id
        hasChanges = true
    }

    private func removeSelectedProfile() {
        guard let selectedProfileID else { return }
        guard let target = profile.profiles.first(where: { $0.id == selectedProfileID }) else { return }
        removeProfile(target)
    }

    private func removeProfile(_ target: ApplicantSocialProfile) {
        guard let index = profile.profiles.firstIndex(where: { $0.id == target.id }) else { return }
        let removed = profile.profiles.remove(at: index)
        selectedProfileID = nil
        hoveredProfileID = nil
        removed.applicant = nil
        if let context = profile.modelContext {
            context.delete(removed)
        }
        hasChanges = true
    }
}

private struct ApplicantSocialProfileRow: View {
    @Bindable var socialProfile: ApplicantSocialProfile
    var isSelected: Bool
    var isHovered: Bool
    var onSelect: () -> Void
    var onHoverChange: (Bool) -> Void
    var onDelete: () -> Void
    var onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("Network", text: $socialProfile.network)
                .textFieldStyle(.roundedBorder)
                .onChange(of: socialProfile.network) { _, _ in onEdit() }

            TextField("Username", text: $socialProfile.username)
                .textFieldStyle(.roundedBorder)
                .onChange(of: socialProfile.username) { _, _ in onEdit() }

            TextField("URL", text: $socialProfile.url)
                .textFieldStyle(.roundedBorder)
                .onChange(of: socialProfile.url) { _, _ in onEdit() }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.15), lineWidth: isSelected ? 2 : 1)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                )
        )
        .overlay(alignment: .topTrailing) {
            if isHovered {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            onHoverChange(hovering)
        }
    }
}
