import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SwiftyJSON

struct OnboardingInterviewView: View {
    @Environment(OnboardingInterviewService.self) private var interviewService
    @Environment(EnabledLLMStore.self) private var enabledLLMStore

    @State private var selectedModelId: String = ""
    @State private var selectedBackend: LLMFacade.Backend = .openRouter
    @State private var userInput: String = ""
    @State private var shouldAutoScroll = true
    @State private var linkedInURL: String = ""
    @State private var fileImportError: String?
    @State private var showImportError = false

    private let fallbackModelId = "gpt-4o"

    var body: some View {
        @Bindable var service = interviewService

        VStack(spacing: 0) {
            header(service: service)
                .padding(.horizontal)
                .padding(.top, 20)

            Divider()

            HStack(spacing: 0) {
                chatPanel(service: service)
                Divider()
                artifactPanel(service: service)
                    .frame(minWidth: 340)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1000, minHeight: 680)
        .task { initializeSelectionsIfNeeded() }
        .sheet(isPresented: Binding(get: { service.pendingExtraction != nil }, set: { newValue in
            if !newValue {
                interviewService.cancelPendingExtraction()
            }
        })) {
            if let pending = service.pendingExtraction {
                ExtractionReviewSheet(
                    extraction: pending,
                    onConfirm: { updated, notes in
                        Task { await interviewService.confirmPendingExtraction(updatedExtraction: updated, notes: notes) }
                    },
                    onCancel: {
                        interviewService.cancelPendingExtraction()
                    }
                )
            }
        }
        .alert("Import Failed", isPresented: $showImportError, presenting: fileImportError) { _ in
            Button("OK") { fileImportError = nil }
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Header

    private func header(service: OnboardingInterviewService) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                modelPicker
                backendPicker
                phasePicker(service: service)
                Spacer()
                Button(action: { Task { await interviewService.startInterview(modelId: currentModelId(), backend: selectedBackend) } }) {
                    if service.isProcessing && !service.isActive {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Start Interview", systemImage: "play.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(currentModelId().isEmpty || service.isProcessing)

                Button("Reset") {
                    interviewService.reset()
                    userInput = ""
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 12) {
                Button("Upload Résumé") { importResume() }
                Button("Import Artifact") { importArtifact() }
                Button("Import Writing Sample") { importWritingSample() }

                HStack(spacing: 4) {
                    TextField("LinkedIn URL", text: $linkedInURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 250)
                    Button("Add") { registerLinkedIn() }
                        .buttonStyle(.bordered)
                }

                Toggle("Enable Writing Analysis", isOn: Binding(
                    get: { service.allowWritingAnalysis },
                    set: { interviewService.setWritingAnalysisConsent($0) }
                ))
                .toggleStyle(.switch)

                Toggle("Allow Web Search", isOn: Binding(get: { service.allowWebSearch }, set: { interviewService.setWebSearchConsent($0) }))
                    .toggleStyle(.switch)
            }

            Text("Focus: \(service.currentPhase.focusSummary)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)

            if let error = service.lastError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.footnote)
            }
        }
    }

    private var modelPicker: some View {
        Picker("Model", selection: $selectedModelId) {
            ForEach(enabledLLMStore.enabledModels, id: \.modelId) { model in
                Text(model.displayName).tag(model.modelId)
            }
            if enabledLLMStore.enabledModels.isEmpty {
                Text(fallbackModelId).tag(fallbackModelId)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 220)
        .onChange(of: enabledLLMStore.enabledModels) { _, _ in
            initializeSelectionsIfNeeded()
        }
    }

    private var backendPicker: some View {
        let backends = interviewService.availableBackends()
        return Group {
            if backends.count > 1 {
                Picker("Backend", selection: $selectedBackend) {
                    ForEach(backends, id: \.self) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }
        }
    }

    private func phasePicker(service: OnboardingInterviewService) -> some View {
        Picker("Phase", selection: Binding(get: { service.currentPhase }, set: { service.setPhase($0) })) {
            ForEach(OnboardingPhase.allCases, id: \.self) { phase in
                Text(phase.displayName).tag(phase)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 460)
    }

    // MARK: - Chat Panel

    private func chatPanel(service: OnboardingInterviewService) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(service.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(20)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: service.messages.count) { _, _ in
                    if shouldAutoScroll, let lastId = service.messages.last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }

            if !service.nextQuestions.isEmpty {
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(service.nextQuestions) { question in
                            Button(action: { send(question.text) }) {
                                Text(question.text)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 12)
                                    .background(Color.accentColor.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }

            Divider()

            HStack(alignment: .center, spacing: 12) {
                TextField("Type your response…", text: $userInput, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .disabled(service.isProcessing || !service.isActive)
                    .onSubmit { send(userInput) }

                Button {
                    send(userInput)
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || service.isProcessing || !service.isActive)
            }
            .padding(.all, 16)
        }
        .frame(minWidth: 620)
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        userInput = ""
        Task { await interviewService.send(userMessage: trimmed) }
    }

    // MARK: - Artifact Panel

    private func artifactPanel(service: OnboardingInterviewService) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Artifacts")
                        .font(.title2)
                        .bold()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !service.schemaIssues.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Schema Alerts")
                            .font(.headline)
                            .foregroundColor(.orange)
                        ForEach(service.schemaIssues, id: \.self) { issue in
                            Label(issue, systemImage: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                        }
                    }
                }

                if let profileJSON = service.artifacts.applicantProfile {
                    ArtifactSection(title: "Applicant Profile", content: formattedJSON(profileJSON))
                }

               if let defaultsJSON = service.artifacts.defaultValues {
                    ArtifactSection(title: "Default Values", content: formattedJSON(defaultsJSON))
                }

                if !service.artifacts.knowledgeCards.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Knowledge Cards")
                            .font(.headline)
                        ForEach(Array(service.artifacts.knowledgeCards.enumerated()), id: \.offset) { index, card in
                            KnowledgeCardView(index: index + 1, card: card)
                                .padding(8)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }

                if !service.artifacts.factLedger.isEmpty {
                    FactLedgerListView(entries: service.artifacts.factLedger)
                }

                if let skillMap = service.artifacts.skillMap {
                    ArtifactSection(title: "Skill Evidence Map", content: formattedJSON(skillMap))
                }

                if let styleProfile = service.artifacts.styleProfile {
                    StyleProfileView(profile: styleProfile)
                }

                if !service.artifacts.writingSamples.isEmpty {
                    WritingSamplesListView(samples: service.artifacts.writingSamples)
                }

                if let context = service.artifacts.profileContext, !context.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Profile Context")
                            .font(.headline)
                        Text(context)
                            .font(.body)
                    }
                }

                if !service.artifacts.needsVerification.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Needs Verification")
                            .font(.headline)
                        ForEach(service.artifacts.needsVerification, id: \.self) { item in
                            Label(item, systemImage: "questionmark.diamond")
                                .foregroundColor(.orange)
                        }
                    }
                }

                if !service.uploadedItems.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Uploads")
                            .font(.headline)
                        ForEach(service.uploadedItems) { item in
                            Label("\(item.kind.rawValue.capitalized): \(item.name) (ID: \(item.id))", systemImage: "doc")
                                .font(.caption)
                        }
                    }
                }

                if service.isProcessing {
                    ProgressView("Processing…")
                        .progressViewStyle(.linear)
                }
            }
            .padding(20)
        }
    }

    // MARK: - Helpers

    private func currentModelId() -> String {
        if !selectedModelId.isEmpty {
            return selectedModelId
        }
        if let first = enabledLLMStore.enabledModels.first?.modelId {
            return first
        }
        return fallbackModelId
    }

    private func initializeSelectionsIfNeeded() {
        if selectedModelId.isEmpty {
            selectedModelId = enabledLLMStore.enabledModels.first?.modelId ?? fallbackModelId
        }
        let backends = interviewService.availableBackends()
        if !backends.contains(selectedBackend) {
            selectedBackend = backends.first ?? .openRouter
        }
    }

    private func formattedJSON(_ json: JSON) -> String {
        json.rawString(options: .prettyPrinted) ?? json.rawString() ?? ""
    }

    private func importResume() {
        openPanel(allowedTypes: [.pdf, .text, .plainText, .json]) { url in
            do {
                try interviewService.registerResume(fileURL: url)
            } catch {
                fileImportError = error.localizedDescription
                showImportError = true
            }
        }
    }

    private func importArtifact() {
        openPanel(allowedTypes: [.pdf, .text, .plainText, .json]) { url in
            do {
                let data = try Data(contentsOf: url)
                _ = interviewService.registerArtifact(data: data, suggestedName: url.lastPathComponent)
            } catch {
                fileImportError = error.localizedDescription
                showImportError = true
            }
        }
    }

    private func importWritingSample() {
        openPanel(allowedTypes: [.pdf, .text, .plainText, .json]) { url in
            do {
                let data = try Data(contentsOf: url)
                _ = interviewService.registerWritingSample(data: data, suggestedName: url.lastPathComponent)
            } catch {
                fileImportError = error.localizedDescription
                showImportError = true
            }
        }
    }

    private func registerLinkedIn() {
        guard let url = URL(string: linkedInURL.trimmingCharacters(in: .whitespacesAndNewlines)), !linkedInURL.isEmpty else {
            fileImportError = "Please enter a valid LinkedIn URL."
            showImportError = true
            return
        }
        _ = interviewService.registerLinkedInProfile(url: url)
        linkedInURL = ""
    }

    private func openPanel(allowedTypes: [UTType], completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = allowedTypes
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            completion(url)
        }
    }

    // MARK: - Supporting Types

}

private struct MessageBubble: View {
    let message: OnboardingMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer() }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .padding(12)
                    .background(backgroundColor)
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 520, alignment: message.role == .user ? .trailing : .leading)

            if message.role != .user { Spacer() }
        }
        .transition(.opacity)
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return Color.accentColor.opacity(0.2)
        case .assistant:
            return Color(nsColor: .controlBackgroundColor)
        case .system:
            return Color.gray.opacity(0.15)
        }
    }
}

private struct ArtifactSection: View {
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            ScrollView {
                Text(content.isEmpty ? "—" : content)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 180)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct KnowledgeCardView: View {
    let index: Int
    let card: JSON

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("#\(index) \(card["title"].stringValue)")
                .font(.headline)
            if let summary = card["summary"].string {
                Text(summary)
                    .font(.body)
            }
            if let source = card["source"].string, !source.isEmpty {
                Label(source, systemImage: "link")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            let metrics = card["metrics"].arrayValue.compactMap { $0.string }
            if !metrics.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Metrics")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(metrics, id: \.self) { metric in
                        Text("• \(metric)")
                            .font(.caption)
                    }
                }
            }
            let skills = card["skills"].arrayValue.compactMap { $0.string }
            if !skills.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Skills")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(skills.joined(separator: ", "))
                        .font(.caption)
                }
            }
        }
    }
}

private struct FactLedgerListView: View {
    let entries: [JSON]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fact Ledger")
                .font(.headline)

            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry["title"].string ?? "Entry #\(index + 1)")
                        .font(.subheadline)
                        .bold()
                    if let summary = entry["summary"].string {
                        Text(summary)
                            .font(.body)
                    }

                    let value = entry["value"]
                    if let valueArray = value.array {
                        ForEach(Array(valueArray.enumerated()), id: \.offset) { valueIndex, item in
                            if let text = item["summary"].string ?? item["value"].string {
                                Text("• \(text)")
                                    .font(.caption)
                            } else if let string = item.string {
                                Text("• \(string)")
                                    .font(.caption)
                            }
                        }
                    } else if let string = value.string {
                        Text(string)
                            .font(.caption)
                    } else if let raw = value.rawString(options: .prettyPrinted) {
                        Text(raw)
                            .font(.system(.caption, design: .monospaced))
                    }

                    if let confidence = entry["confidence"].double {
                        Text("Confidence: \(String(format: "%.2f", confidence))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

private struct StyleProfileView: View {
    let profile: JSON

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Style Profile")
                .font(.headline)

            let vector = profile["style_vector"]
            VStack(alignment: .leading, spacing: 4) {
                if let tone = vector["tone"].string {
                    Label("Tone: \(tone)", systemImage: "waveform.path.ecg")
                        .font(.subheadline)
                }
                if let avg = vector["avg_sentence_len"].double {
                    Text("Average sentence length: \(String(format: "%.1f words", avg))")
                        .font(.caption)
                }
                if let activeRatio = vector["active_voice_ratio"].double {
                    Text("Active voice ratio: \(String(format: "%.0f%%", activeRatio * 100))")
                        .font(.caption)
                }
                if let quant = vector["quant_density_per_100w"].double {
                    Text("Quant density per 100 words: \(String(format: "%.2f", quant))")
                        .font(.caption)
                }
            }

            let samples = profile["samples"].arrayValue
            if !samples.isEmpty {
                Text("Samples (\(samples.count))")
                    .font(.subheadline)
                ForEach(samples.compactMap { $0["sample_id"].string ?? $0["id"].string }, id: \.self) { sampleId in
                    Text("• \(sampleId)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct WritingSamplesListView: View {
    let samples: [JSON]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Writing Samples")
                .font(.headline)
            ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                VStack(alignment: .leading, spacing: 4) {
                    Text(sample["title"].string ?? sample["name"].string ?? "Sample #\(index + 1)")
                        .font(.subheadline)
                        .bold()
                    if let summary = sample["summary"].string {
                        Text(summary)
                            .font(.caption)
                    }
                    let tone = sample["tone"].string ?? "—"
                    let words = sample["word_count"].int ?? 0
                    let avg = sample["avg_sentence_len"].double ?? 0
                    let active = sample["active_voice_ratio"].double ?? 0
                    let quant = sample["quant_density_per_100w"].double ?? 0

                    Text("Tone: \(tone) • \(words) words • Avg sentence: \(String(format: "%.1f", avg)) words")
                        .font(.caption)
                    Text("Active voice: \(String(format: "%.0f%%", active * 100)) • Quant density: \(String(format: "%.2f", quant)) per 100 words")
                        .font(.caption)

                    let notable = sample["notable_phrases"].arrayValue.compactMap { $0.string }
                    if !notable.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Notable phrases")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            ForEach(notable.prefix(3), id: \.self) { phrase in
                                Text("• \(phrase)")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

private struct ExtractionReviewSheet: View {
    let extraction: OnboardingPendingExtraction
    let onConfirm: (JSON, String?) -> Void
    let onCancel: () -> Void

    @State private var jsonText: String
    @State private var notes: String = ""
    @State private var errorMessage: String?

    init(
        extraction: OnboardingPendingExtraction,
        onConfirm: @escaping (JSON, String?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.extraction = extraction
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self._jsonText = State(initialValue: extraction.rawExtraction.rawString(options: .prettyPrinted) ?? extraction.rawExtraction.description)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review Résumé Extraction")
                .font(.title2)
                .bold()

            if !extraction.uncertainties.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Uncertain Fields")
                        .font(.headline)
                        .foregroundColor(.orange)
                    ForEach(extraction.uncertainties, id: \.self) { item in
                        Label(item, systemImage: "questionmark.circle")
                            .foregroundColor(.orange)
                    }
                }
            }

            Text("Raw Extraction (editable JSON)")
                .font(.headline)

            TextEditor(text: $jsonText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 240)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2))
                )

            TextField("Notes for the assistant (optional)", text: $notes)
                .textFieldStyle(.roundedBorder)

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                Button("Confirm") {
                    guard let data = jsonText.data(using: .utf8),
                          let json = try? JSON(data: data) else {
                        errorMessage = "JSON is invalid. Please correct it before confirming."
                        return
                    }
                    onConfirm(json, notes.isEmpty ? nil : notes)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 480)
    }
}
