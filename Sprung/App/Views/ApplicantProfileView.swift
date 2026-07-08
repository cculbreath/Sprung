//
//  ApplicantProfileView.swift
//  Sprung
//
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
    // Viewer by default; the user opts into editing explicitly. Edits are made
    // against `draft` (and the live signature) and only committed on Save.
    @State private var isEditing = false
    @State private var signatureLoadError: String?
    var body: some View {
        VStack(spacing: 0) {
            header
            if isLoading {
                ProgressView("Loading profile…")
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if isEditing {
                            ApplicantProfileEditor(draft: $draft, showsSummary: true)
                                .onChange(of: draft) { _, _ in
                                    hasChanges = true
                                }
                            signatureSection
                        } else {
                            ProfileViewerContent(
                                draft: draft,
                                signatureImage: profile?.getSignatureImage()
                            )
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
        .alert("Couldn't Load Signature", isPresented: Binding(
            get: { signatureLoadError != nil },
            set: { if !$0 { signatureLoadError = nil } }
        )) {
            Button("OK") { signatureLoadError = nil }
        } message: {
            if let error = signatureLoadError {
                Text(error)
            }
        }
    }

    // MARK: - Header

    /// Single L1 header row: module identity plus the mode-dependent action
    /// slot (Edit, or Save/Cancel while editing). Replaces the old separate
    /// mode toolbar — there is only ever one header row.
    private var header: some View {
        ModuleHeader(
            title: "Profile",
            subtitle: "Manage your contact information and professional details"
        ) {
            headerActions
        }
    }

    @ViewBuilder
    private var headerActions: some View {
        if !isLoading {
            if isEditing {
                HStack(spacing: 12) {
                    Button("Cancel") { cancelEditing() }
                        .buttonStyle(.bordered)
                    Button("Save") { commitEditing() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!hasChanges)
                }
            } else {
                HStack(spacing: 12) {
                    if !successMessage.isEmpty {
                        Label(successMessage, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.callout)
                    }
                    Button {
                        successMessage = ""
                        isEditing = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func commitEditing() {
        saveProfile()
        isEditing = false
    }

    private func cancelEditing() {
        // Reload from the stored profile so in-flight text/photo edits are
        // discarded, then drop back to the viewer.
        loadProfile()
        isEditing = false
    }

    // MARK: - Signature (edit mode)

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
    private func presentSignaturePicker() {
        presentOpenPanel(allowedTypes: [.png, .jpeg, .pdf, .svg]) { url in
            do {
                let data = try Data(contentsOf: url)
                profile?.signatureData = data
                hasChanges = true
            } catch {
                Logger.error("ApplicantProfileView: Failed to load signature image: \(error)")
                signatureLoadError = "Couldn't load the signature image — \(error.localizedDescription)"
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
    }
    @MainActor
    private func saveProfile() {
        guard let profile else { return }
        draft.apply(to: profile)
        profileStore.save(profile)
        successMessage = "Profile saved"
        hasChanges = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            successMessage = ""
        }
    }
}

// MARK: - Read-only Viewer

/// Read-only presentation of the applicant profile shown when not editing.
/// Mirrors the editor's sections; empty fields are omitted, and values are
/// selectable so the user can copy an email/phone without entering edit mode.
private struct ProfileViewerContent: View {
    let draft: ApplicantProfileDraft
    let signatureImage: Image?

    var body: some View {
        if isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                if hasContact { contactSection }
                if !locationLine.isEmpty { locationSection }
                if !trimmed(draft.summary).isEmpty { summarySection }
                if signatureImage != nil { signatureViewSection }
                if !draft.socialProfiles.isEmpty { socialSection }
            }
        }
    }

    // MARK: Sections

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 16) {
            if let photo = draft.pictureImage {
                Image(nsImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(trimmed(draft.name).isEmpty ? "Unnamed" : draft.name)
                    .font(.title.weight(.semibold))
                    .textSelection(.enabled)
                if !trimmed(draft.label).isEmpty {
                    Text(draft.label)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var contactSection: some View {
        section("Contact") {
            infoRow(icon: "envelope", draft.email)
            infoRow(icon: "phone", draft.phone)
            infoRow(icon: "globe", draft.website)
        }
    }

    private var locationSection: some View {
        section("Location") {
            infoRow(icon: "mappin.and.ellipse", locationLine)
        }
    }

    private var summarySection: some View {
        section("Professional Summary") {
            Text(draft.summary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var signatureViewSection: some View {
        section("Signature") {
            signatureImage?
                .resizable()
                .scaledToFit()
                .frame(height: 100)
                .frame(maxWidth: .infinity, alignment: .leading)
                .border(Color.gray.opacity(0.2), width: 1)
                .background(Color.white)
        }
    }

    private var socialSection: some View {
        section("Social Links") {
            ForEach(draft.socialProfiles) { social in
                let handle = trimmed(social.username)
                let detail = trimmed(social.url).isEmpty ? handle : social.url
                HStack(spacing: 8) {
                    Text(trimmed(social.network).isEmpty ? "Profile" : social.network)
                        .fontWeight(.medium)
                    if !detail.isEmpty {
                        Text(detail)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No profile details yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Choose Edit to add your contact information and professional details.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: Helpers

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        } label: {
            Text(title)
                .font(.headline)
        }
    }

    @ViewBuilder
    private func infoRow(icon: String, _ value: String) -> some View {
        if !trimmed(value).isEmpty {
            Label {
                Text(value).textSelection(.enabled)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasContact: Bool {
        !trimmed(draft.email).isEmpty
            || !trimmed(draft.phone).isEmpty
            || !trimmed(draft.website).isEmpty
    }

    private var locationLine: String {
        let cityRegion = [draft.city, draft.state]
            .map(trimmed)
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        var parts = [trimmed(draft.address), cityRegion]
            .filter { !$0.isEmpty }
        let tail = [trimmed(draft.zip), trimmed(draft.countryCode)]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !tail.isEmpty { parts.append(tail) }
        return parts.joined(separator: ", ")
    }

    private var isEmpty: Bool {
        trimmed(draft.name).isEmpty
            && trimmed(draft.label).isEmpty
            && !hasContact
            && locationLine.isEmpty
            && trimmed(draft.summary).isEmpty
            && draft.socialProfiles.isEmpty
            && draft.pictureImage == nil
            && signatureImage == nil
    }
}
