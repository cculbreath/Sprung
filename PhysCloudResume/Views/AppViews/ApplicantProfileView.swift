//
//  ApplicantProfileView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/21/25.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ApplicantProfileView: View {
    @State private var profile: ApplicantProfile
    @State private var showImagePicker = false
    @State private var successMessage = ""
    @State private var hasChanges = false
    
    init() {
        // Initialize with a default profile, then update it in onAppear
        _profile = State(initialValue: ApplicantProfile())
    }
    
    var body: some View {
        Form {
            Section("Personal Information") {
                TextField("Name", text: $profile.name)
                    .onChange(of: profile.name) { _, _ in hasChanges = true }
                TextField("Email", text: $profile.email)
                    .onChange(of: profile.email) { _, _ in hasChanges = true }
                TextField("Phone", text: $profile.phone)
                    .onChange(of: profile.phone) { _, _ in hasChanges = true }
                TextField("Websites", text: $profile.websites)
                    .onChange(of: profile.websites) { _, _ in hasChanges = true }
            }
            
            Section("Address") {
                TextField("Street Address", text: $profile.address)
                    .onChange(of: profile.address) { _, _ in hasChanges = true }
                TextField("City", text: $profile.city)
                    .onChange(of: profile.city) { _, _ in hasChanges = true }
                TextField("State", text: $profile.state)
                    .onChange(of: profile.state) { _, _ in hasChanges = true }
                TextField("ZIP Code", text: $profile.zip)
                    .onChange(of: profile.zip) { _, _ in hasChanges = true }
            }
            
            Section("Signature") {
                HStack {
                    if let image = profile.getSignatureImage() {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(height: 100)
                    } else {
                        Text("No signature uploaded")
                            .foregroundColor(.secondary)
                            .frame(height: 100)
                    }
                    
                    Spacer()
                    
                    Button("Choose Signature...") {
                        showImagePicker = true
                    }
                    
                    if profile.signatureData != nil {
                        Button("Remove") {
                            profile.signatureData = nil
                            hasChanges = true
                        }
                    }
                }
            }
            
            Section {
                Button("Save Profile") {
                    Task {
                        await MainActor.run {
                            saveProfile()
                        }
                    }
                }
                .disabled(!hasChanges)
                
                if !successMessage.isEmpty {
                    Text(successMessage)
                        .foregroundColor(.green)
                }
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
        .fileImporter(
            isPresented: $showImagePicker,
            allowedContentTypes: [.png, .jpeg, .svg],
            allowsMultipleSelection: false
        ) { result in
            handleSignatureSelection(result)
        }
        .task {
            // Load profile from manager
            await loadProfile()
        }
    }
    
    private func handleSignatureSelection(_ result: Result<[URL], Error>) {
        do {
            let selectedFile = try result.get().first
            
            guard let selectedFile = selectedFile else {
                print("No file selected")
                return
            }
            
            if selectedFile.startAccessingSecurityScopedResource() {
                defer { selectedFile.stopAccessingSecurityScopedResource() }
                
                let data = try Data(contentsOf: selectedFile)
                profile.signatureData = data
                hasChanges = true
            } else {
                print("Failed to access file")
            }
        } catch {
            print("Error selecting signature: \(error)")
        }
    }
    
    @MainActor
    private func loadProfile() async {
        profile = ApplicantProfileManager.shared.getProfile()
    }
    
    @MainActor
    private func saveProfile() {
        ApplicantProfileManager.shared.saveProfile(profile)
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