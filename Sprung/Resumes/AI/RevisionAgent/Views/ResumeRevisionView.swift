import SwiftUI
import SwiftData
import PDFKit

/// Main container view for the resume revision agent session.
/// Presents a split layout: PDF preview on the left, chat stream on the right.
struct ResumeRevisionView: View {
    @Environment(LLMFacade.self) private var llmFacade
    @Environment(TemplateStore.self) private var templateStore
    @Environment(ApplicantProfileStore.self) private var applicantProfileStore
    @Environment(KnowledgeCardStore.self) private var knowledgeCardStore
    @Environment(SkillStore.self) private var skillStore
    @Environment(CoverRefStore.self) private var coverRefStore
    @Environment(TitleSetStore.self) private var titleSetStore
    @Environment(InferenceGuidanceStore.self) private var guidanceStore
    @Environment(CandidateDossierStore.self) private var candidateDossierStore
    @Environment(\.modelContext) private var modelContext

    let resume: Resume
    /// Hands the freshly created agent to SecondaryWindowService so window
    /// teardown can cancel it (the single cancellation choke point).
    let onAgentCreated: (ResumeRevisionAgent) -> Void
    /// Closes the hosting window via SecondaryWindowService. Teardown
    /// (agent cancellation) happens in the manager's windowWillClose handler.
    let onRequestClose: () -> Void

    @State private var agent: ResumeRevisionAgent?
    @State private var pdfData: Data?
    @State private var pdfController: PDFPreviewController = {
        let c = PDFPreviewController()
        c.fitWidth = true
        return c
    }()
    @State private var pdfLoadFailed = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        HSplitView {
            // Left pane: PDF preview
            pdfPreviewPane
                .frame(minWidth: 480, idealWidth: 620)

            // Right pane: Chat stream
            VStack(spacing: 0) {
                // Toolbar header
                if let agent = agent {
                    RevisionToolbar(
                        status: agent.status,
                        currentAction: agent.currentAction,
                        onCancel: { onRequestClose() },
                        onSave: { agent.acceptCurrentState() },
                        onClose: { onRequestClose() }
                    )
                }

                Divider()

                // Chat
                chatPane
            }
            .frame(minWidth: 380, idealWidth: 480)
        }
        .task {
            await startAgent()
        }
        .onChange(of: agent?.latestPDFData) { _, newData in
            if let newData {
                pdfData = newData
            }
        }
        // Status is the source of truth for failure: a session can end with
        // .failed(message) without run() throwing. Cancellation stays silent.
        .onChange(of: agent?.status) { _, newStatus in
            if case .failed(let message) = newStatus {
                errorMessage = message
                showError = true
            }
        }
        .alert("Revision Error", isPresented: $showError) {
            Button("OK") {
                // Startup failures (no agent yet) leave nothing to inspect, so
                // close the window. Mid-session failures keep the window open
                // so the user can review the transcript.
                if agent == nil { onRequestClose() }
            }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
    }

    // MARK: - PDF Preview

    @ViewBuilder
    private var pdfPreviewPane: some View {
        Group {
            if let pdfData = pdfData {
                PDFPreviewView(
                    pdfData: pdfData,
                    overlayDocument: nil,
                    overlayPageIndex: 0,
                    overlayOpacity: 0,
                    overlayColor: .clear,
                    controller: pdfController
                )
            } else if pdfLoadFailed {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Preview unavailable — PDF generation failed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading PDF...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Chat Pane

    @ViewBuilder
    private var chatPane: some View {
        if let agent = agent {
            RevisionChatView(
                messages: agent.messages,
                currentProposal: agent.currentProposal,
                currentQuestion: agent.currentQuestion,
                currentCompletionSummary: agent.currentCompletionSummary,
                currentAdvisoryReport: agent.currentAdvisoryReport,
                isRunning: agent.status == .running,
                sessionEnded: sessionEnded,
                onProposalResponse: { response in
                    agent.respondToProposal(response)
                },
                onQuestionResponse: { answer in
                    agent.respondToQuestion(answer)
                },
                onCompletionResponse: { accepted in
                    agent.respondToCompletion(accepted)
                },
                onUserMessage: { text in
                    agent.sendUserMessage(text)
                },
                onInterruptWithMessage: { text in
                    agent.interruptWithMessage(text)
                },
                onCancelStream: {
                    agent.cancelActiveStream()
                }
            )
        } else {
            VStack(spacing: 12) {
                ProgressView()
                Text("Initializing...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Agent Lifecycle

    /// True once the session has reached a terminal state.
    private var sessionEnded: Bool {
        guard let status = agent?.status else { return false }
        switch status {
        case .completed, .failed, .cancelled:
            return true
        case .idle, .running:
            return false
        }
    }

    private func startAgent() async {
        // A revision session is meaningless without a job description — the
        // agent would tailor the resume to nothing. Refuse to start and tell
        // the user exactly what to fix.
        let jobDescription = (resume.jobApp?.jobDescription ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !jobDescription.isEmpty else {
            errorMessage = "This job application has no job description. Add one to the job application before starting a Customize session."
            showError = true
            return
        }

        let pdfGenerator = NativePDFGenerator(
            templateStore: templateStore,
            profileProvider: applicantProfileStore
        )

        // Load initial PDF for preview
        do {
            let template = try pdfGenerator.resolveTemplate(for: resume)
            pdfData = try await pdfGenerator.generatePDF(for: resume, template: template.slug)
        } catch {
            Logger.error("ResumeRevisionView: Failed to load initial PDF: \(error)", category: .ai)
            pdfLoadFailed = true
        }

        // Resolve model ID
        guard let modelId = UserDefaults.standard.string(forKey: "resumeRevisionModelId"),
              !modelId.isEmpty else {
            errorMessage = "Resume revision model is not configured. Please select a model in Settings > Models."
            showError = true
            return
        }

        // Gather reference materials from stores
        let knowledgeCards = knowledgeCardStore.knowledgeCards
        let skills = skillStore.skills
        let coverRefs = coverRefStore.storedCoverRefs
        // Canonical voice context: the same block every other LLM surface uses.
        let writersVoice = coverRefStore.writersVoice
        // Explicitly banned phrases from the onboarding voice profile.
        let avoidPhrases = guidanceStore.voiceProfile()?.avoidPhrases ?? []
        // Strategic positioning (strengths/pitfalls) from the candidate dossier;
        // empty string when no dossier exists. Private fields are not included.
        let strategicGuidance = candidateDossierStore.exportForResumeCustomization() ?? ""

        let revisionAgent = ResumeRevisionAgent(
            resume: resume,
            llmFacade: llmFacade,
            modelId: modelId,
            pdfGenerator: pdfGenerator,
            modelContext: modelContext,
            titleSets: titleSetStore.allTitleSets,
            writersVoice: writersVoice,
            avoidPhrases: avoidPhrases,
            strategicGuidance: strategicGuidance
        )
        agent = revisionAgent
        onAgentCreated(revisionAgent)

        do {
            try await revisionAgent.run(
                jobDescription: jobDescription,
                knowledgeCards: knowledgeCards,
                skills: skills,
                coverRefs: coverRefs
            )
        } catch {
            switch revisionAgent.status {
            case .cancelled, .failed:
                // .cancelled stays silent; .failed is surfaced by the status
                // observer in `body` — avoid presenting a duplicate alert.
                break
            case .idle, .running, .completed:
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}
