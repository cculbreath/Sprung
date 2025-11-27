import AppKit
import SwiftUI
import UniformTypeIdentifiers
struct ApplicantProfileEditor: View {
    @Binding var draft: ApplicantProfileDraft
    var showPhotoSection: Bool = true
    var showsSummary: Bool = true
    var showsProfessionalLabel: Bool = true
    var emailSuggestions: [String] = []
    @State private var selectedProfileID: UUID?
    @State private var hoveredProfileID: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Name", text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                    if showsProfessionalLabel {
                        TextField("Professional Label", text: $draft.label)
                            .textFieldStyle(.roundedBorder)
                    }
                    emailEntry
                    TextField("Phone", text: $draft.phone)
                        .textFieldStyle(.roundedBorder)
                    TextField("Website", text: $draft.website)
                        .textFieldStyle(.roundedBorder)
                }
            } label: {
                Text("Personal Information")
                    .font(.headline)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Street Address", text: $draft.address)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        TextField("City", text: $draft.city)
                            .textFieldStyle(.roundedBorder)
                        TextField("State / Region", text: $draft.state)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        TextField("Postal Code", text: $draft.zip)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                        TextField("Country Code", text: $draft.countryCode)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }
                }
            } label: {
                Text("Location")
                    .font(.headline)
            }
            if showsSummary {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Summary")
                            .font(.subheadline.weight(.medium))
                        Text("Use a succinct 2–3 sentence summary that highlights your focus areas.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $draft.summary)
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
            }
            if showPhotoSection {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Profile photo appears on generated resumes where supported.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            if let image = draft.pictureImage {
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 140, height: 140)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                    )
                            } else {
                                Text("No profile photo")
                                    .foregroundColor(.secondary)
                                    .frame(width: 140, height: 140)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                    )
                            }
                        }
                        HStack(spacing: 12) {
                            Button("Choose Photo…") {
                                presentPicturePicker()
                            }
                            .buttonStyle(.bordered)
                            Button("Choose from Photos…") {
                                presentPhotoLibraryPicker()
                            }
                            .buttonStyle(.bordered)
                            if draft.pictureData != nil {
                                Button("Remove Photo") {
                                    draft.updatePicture(data: nil, mimeType: nil)
                                }
                                .buttonStyle(.bordered)
                                .foregroundColor(.red)
                            }
                            Spacer()
                        }
                    }
                } label: {
                    Text("Profile Photo")
                        .font(.headline)
                }
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    if draft.socialProfiles.isEmpty {
                        VStack(spacing: 8) {
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
                            ForEach(draft.socialProfiles) { social in
                                ApplicantSocialProfileRow(
                                    profile: social,
                                    isSelected: selectedProfileID == social.id,
                                    isHovered: hoveredProfileID == social.id,
                                    onSelect: { selectedProfileID = social.id },
                                    onHover: { hovering in
                                        hoveredProfileID = hovering ? social.id : nil
                                    },
                                    onDelete: { removeProfile(social) },
                                    onUpdate: { updated in
                                        replaceProfile(updated)
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

        }
    }
    private func addProfile() {
        let newProfile = ApplicantSocialProfileDraft()
        draft.socialProfiles.append(newProfile)
        selectedProfileID = newProfile.id
    }
    private func removeProfile(_ profile: ApplicantSocialProfileDraft) {
        draft.socialProfiles.removeAll { $0.id == profile.id }
    }
    private func replaceProfile(_ profile: ApplicantSocialProfileDraft) {
        if let index = draft.socialProfiles.firstIndex(where: { $0.id == profile.id }) {
            draft.socialProfiles[index] = profile
        }
    }
    private func removeSelectedProfile() {
        guard let id = selectedProfileID else { return }
        draft.socialProfiles.removeAll { $0.id == id }
        selectedProfileID = nil
    }
    private func presentPicturePicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let data = try? Data(contentsOf: url) else { return }
            draft.updatePicture(data: data, mimeType: url.mimeTypeHint())
        }
    }
    private func presentPhotoLibraryPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Pictures")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let data = try? Data(contentsOf: url) else { return }
            draft.updatePicture(data: data, mimeType: url.mimeTypeHint())
        }
    }
    private var emailEntry: some View {
        HStack(spacing: 8) {
            TextField("Email", text: $draft.email)
                .textFieldStyle(.roundedBorder)
            if !emailSuggestions.isEmpty {
                Menu {
                    ForEach(emailSuggestions, id: \.self) { email in
                        Button(email) {
                            draft.email = email
                        }
                    }
                } label: {
                    Label("Choose Email", systemImage: "chevron.down.circle")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Choose from suggested email addresses")
                }
            }
        }
    }
}
private struct ApplicantSocialProfileRow: View {
    @State private var draft: ApplicantSocialProfileDraft
    let isSelected: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void
    let onDelete: () -> Void
    let onUpdate: (ApplicantSocialProfileDraft) -> Void
    init(
        profile: ApplicantSocialProfileDraft,
        isSelected: Bool,
        isHovered: Bool,
        onSelect: @escaping () -> Void,
        onHover: @escaping (Bool) -> Void,
        onDelete: @escaping () -> Void,
        onUpdate: @escaping (ApplicantSocialProfileDraft) -> Void
    ) {
        self._draft = State(initialValue: profile)
        self.isSelected = isSelected
        self.isHovered = isHovered
        self.onSelect = onSelect
        self.onHover = onHover
        self.onDelete = onDelete
        self.onUpdate = onUpdate
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Network (e.g. LinkedIn)", text: $draft.network)
                    .textFieldStyle(.roundedBorder)
                TextField("Username / Handle", text: $draft.username)
                    .textFieldStyle(.roundedBorder)
            }
            TextField("URL", text: $draft.url)
                .textFieldStyle(.roundedBorder)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.15), lineWidth: isSelected ? 2 : 1)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isHovered ? Color.gray.opacity(0.05) : Color.clear)
                )
        )
        .onHover { hovering in
            onHover(hovering)
        }
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button("Delete") {
                onDelete()
            }
        }
        .onChange(of: draft) { _, newValue in
            onUpdate(newValue)
        }
    }
}
private extension URL {
    func mimeTypeHint() -> String? {
        if let type = try? resourceValues(forKeys: [.contentTypeKey]).contentType {
            return type.preferredMIMEType
        }
        return nil
    }
}
