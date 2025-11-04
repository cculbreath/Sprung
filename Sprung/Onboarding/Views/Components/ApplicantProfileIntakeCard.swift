import SwiftUI

struct ApplicantProfileIntakeCard: View {
    let state: OnboardingApplicantProfileIntakeState
    let service: OnboardingInterviewService
    let coordinator: OnboardingInterviewCoordinator

    @State private var draft: ApplicantProfileDraft
    @State private var urlString: String

    init(
        state: OnboardingApplicantProfileIntakeState,
        service: OnboardingInterviewService,
        coordinator: OnboardingInterviewCoordinator
    ) {
        self.state = state
        self.service = service
        self.coordinator = coordinator
        _draft = State(initialValue: state.draft)
        _urlString = State(initialValue: state.urlString)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 380, maxHeight: 520)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.05))
        )
        .shadow(color: .black.opacity(0.12), radius: 16, y: 10)
        .onChange(of: state) { _, newValue in
            draft = newValue.draft
            urlString = newValue.urlString
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.mode {
        case .options:
            intakeOptions
        case .loading(let message):
            loadingView(message: message)
        case .manual(let source):
            manualEntryView(source: source)
        case .urlEntry:
            urlEntryView
        }
    }

    private var intakeOptions: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How would you like to start building your profile?")
                .font(.headline)

            if let error = state.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 12) {
                optionButton(
                    title: "Upload Résumé",
                    subtitle: "Upload your resume PDF, DOCX, or text file",
                    icon: "arrow.up.doc"
                ) {
                    // TODO: Emit event instead
                    // service.beginApplicantProfileUpload()
                }

                optionButton(
                    title: "Paste Résumé URL",
                    subtitle: "Provide a link to your resume or LinkedIn profile",
                    icon: "link"
                ) {
                    // TODO: Emit event instead
                    // service.beginApplicantProfileURL()
                }

                optionButton(
                    title: "Use Contact Card",
                    subtitle: "Import details from your macOS Contacts or vCard",
                    icon: "person.crop.circle"
                ) {
                    // TODO: Emit event instead
                    // service.beginApplicantProfileContactsFetch()
                }

                optionButton(
                    title: "Enter Manually",
                    subtitle: "Fill in your contact details step by step",
                    icon: "square.and.pencil"
                ) {
                    // TODO: Emit event instead
                    // service.beginApplicantProfileManualEntry()
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func optionButton(title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .imageScale(.large)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
    }

    private func loadingView(message: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(message)
                .font(.body)
        }
    }

    private func manualEntryView(source: OnboardingApplicantProfileIntakeState.Source) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(source == .contacts ? "Review imported contact details" : "Enter your contact information")
                .font(.headline)

            ScrollView {
                ApplicantProfileEditor(
                    draft: $draft,
                    showPhotoSection: false,
                    showsSummary: false,
                    showsProfessionalLabel: false,
                    emailSuggestions: draft.suggestedEmails
                )
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 340)

            HStack {
                Button("Back") {
                    // TODO: Emit event instead
                    // service.resetApplicantProfileIntakeToOptions()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Save & Continue") {
                    // TODO: Emit event instead
                    // Task { await service.completeApplicantProfileDraft(draft, source: source) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var urlEntryView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paste a link to your resume or online profile")
                .font(.headline)

            TextField("https://…", text: $urlString)
                .textFieldStyle(.roundedBorder)

            if let error = state.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Back") {
                    // TODO: Emit event instead
                    // service.resetApplicantProfileIntakeToOptions()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Submit URL") {
                    // TODO: Emit event instead
                    // Task { await service.submitApplicantProfileURL(urlString) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
