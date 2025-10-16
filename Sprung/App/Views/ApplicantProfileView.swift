//
//  ApplicantProfileView.swift
//  Sprung
//
//  Created by Christopher Culbreath on 4/21/25.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ApplicantProfileView: View {
    @Environment(ApplicantProfileStore.self) private var profileStore: ApplicantProfileStore
    @State private var profile: ApplicantProfile
    @State private var showImagePicker = false
    @State private var successMessage = ""
    @State private var hasChanges = false
    @State private var isLoading = true

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
                Form {
                    Section("Personal Information") {
                        TextField("Name", text: $profile.name)
                            .onChange(of: profile.name) { _, _ in hasChanges = true }
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

                        TextField("Picture URL or file path", text: $profile.picture)
                            .onChange(of: profile.picture) { _, _ in hasChanges = true }
                            .textFieldStyle(.roundedBorder)
                    }

                    Section("Mailing Address") {
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

                    Section("Signature") {
                        VStack(alignment: .leading, spacing: 10) {
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
                                    showImagePicker = true
                                }
                                .buttonStyle(.bordered)

                                if profile.signatureData != nil {
                                    Button("Remove") {
                                        profile.signatureData = nil
                                        hasChanges = true
                                    }
                                    .buttonStyle(.bordered)
                                    .foregroundColor(.red)
                                }

                                Spacer()
                            }
                        }
                    }

                    Section {
                        HStack {
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
                                    .padding(.leading)
                            }

                            Spacer()
                        }
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .fileImporter(
            isPresented: $showImagePicker,
            allowedContentTypes: [.png, .jpeg, .svg],
            allowsMultipleSelection: false
        ) { result in
            handleSignatureSelection(result)
        }
        .task {
            loadProfile()
            isLoading = false
        }
    }

    private func handleSignatureSelection(_ result: Result<[URL], Error>) {
        do {
            let selectedFile = try result.get().first

            guard let selectedFile = selectedFile else {
                return
            }

            if selectedFile.startAccessingSecurityScopedResource() {
                defer { selectedFile.stopAccessingSecurityScopedResource() }

                let data = try Data(contentsOf: selectedFile)
                profile.signatureData = data
                hasChanges = true
            } else {}
        } catch {}
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

        // Clear success message after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            successMessage = ""
        }
    }
}

#Preview {
    ApplicantProfileView()
}
