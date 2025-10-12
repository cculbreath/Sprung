import AppKit
import SwiftUI
import SwiftyJSON

struct OnboardingInterviewView: View {
    @Environment(OnboardingInterviewService.self) private var interviewService
    @Environment(EnabledLLMStore.self) private var enabledLLMStore
    @Environment(AppEnvironment.self) private var appEnvironment

    @State private var selectedModelId: String = ""
    @State private var selectedBackend: OnboardingInterviewService.Backend = .openRouter
    @State private var userInput: String = ""
    @State private var shouldAutoScroll = true

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
                    .frame(minWidth: 320)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 960, minHeight: 640)
        .task { initializeModelSelectionIfNeeded() }
    }

    // MARK: - Header

    private func header(service: OnboardingInterviewService) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Picker("Model", selection: $selectedModelId) {
                    ForEach(enabledLLMStore.enabledModels, id: \.modelId) { model in
                        Text(model.displayName).tag(model.modelId)
                    }
                    if enabledLLMStore.enabledModels.isEmpty {
                        Text("gpt-4o").tag(fallbackModelId)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 220)
                .onChange(of: enabledLLMStore.enabledModels) { _, _ in
                    initializeModelSelectionIfNeeded()
                }

                Picker("Backend", selection: $selectedBackend) {
                    ForEach(OnboardingInterviewService.Backend.allCases, id: \.self) { backend in
                        Text(backend.displayName)
                            .tag(backend)
                            .disabled(!backend.isAvailable)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                Picker("Phase", selection: Binding(get: { service.currentPhase }, set: { service.setPhase($0) })) {
                    ForEach(OnboardingPhase.allCases, id: \.self) { phase in
                        Text(phase.displayName).tag(phase)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)

                Spacer()

                Button {
                    Task { await interviewService.startInterview(modelId: currentModelId(), backend: selectedBackend) }
                } label: {
                    if service.isProcessing && !service.isActive {
                        ProgressView()
                            .controlSize(.small)
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

            if let error = service.lastError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.footnote)
            }
        }
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
        .frame(minWidth: 600)
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
                    Spacer()
                    Button("Open in Finder") {
                        let url = FileHandler.artifactsDirectory()
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .buttonStyle(.bordered)
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

                if let skillMap = service.artifacts.skillMap {
                    ArtifactSection(title: "Skill Evidence Map", content: formattedJSON(skillMap))
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

    private func initializeModelSelectionIfNeeded() {
        if selectedModelId.isEmpty {
            if let first = enabledLLMStore.enabledModels.first?.modelId {
                selectedModelId = first
            } else {
                selectedModelId = fallbackModelId
            }
        }
    }

    private func formattedJSON(_ json: JSON) -> String {
        json.rawString(options: [.prettyPrinted]) ?? json.rawString() ?? ""
    }

    private func formattedJSON(_ json: JSON?) -> String {
        guard let json else { return "—" }
        return formattedJSON(json)
    }

    private func formattedJSON(_ jsonString: String) -> String {
        jsonString
    }
}

// MARK: - Subviews

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
            .frame(maxWidth: 480, alignment: message.role == .user ? .trailing : .leading)

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
                Text(content)
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
            let metrics = card["metrics"].arrayValue
            if !metrics.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Metrics")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(metrics.compactMap { $0.string }, id: \.self) { metric in
                        Text("• \(metric)")
                            .font(.caption)
                    }
                }
            }
            let skills = card["skills"].arrayValue
            if !skills.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Skills")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(skills.compactMap { $0.string }.joined(separator: ", "))
                        .font(.caption)
                }
            }
            let quotes = card["quotes"].arrayValue
            if !quotes.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quotes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(quotes.compactMap { $0.string }, id: \.self) { quote in
                        Text("“\(quote)”")
                            .font(.caption)
                    }
                }
            }
        }
    }
}
