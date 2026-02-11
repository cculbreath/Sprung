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
    @Environment(\.modelContext) private var modelContext

    let resume: Resume

    @State private var agent: ResumeRevisionAgent?
    @State private var pdfData: Data?
    @State private var pdfController = PDFPreviewController()
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
                        onCancel: { handleCancel() },
                        onAccept: { closeWindow() }
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
        .alert("Revision Error", isPresented: $showError) {
            Button("OK") { closeWindow() }
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
                isRunning: agent.status == .running,
                onProposalResponse: { response in
                    agent.respondToProposal(response)
                },
                onQuestionResponse: { answer in
                    agent.respondToQuestion(answer)
                },
                onUserMessage: { text in
                    agent.sendUserMessage(text)
                },
                onAcceptCurrentState: {
                    agent.acceptCurrentState()
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

    private func startAgent() async {
        let pdfGenerator = NativePDFGenerator(
            templateStore: templateStore,
            profileProvider: applicantProfileStore
        )

        // Load initial PDF for preview
        do {
            let slug = resume.template?.slug ?? "default"
            pdfData = try await pdfGenerator.generatePDF(for: resume, template: slug)
        } catch {
            Logger.error("ResumeRevisionView: Failed to load initial PDF: \(error)", category: .ai)
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
        let jobDescription = resume.jobApp?.jobDescription ?? ""

        let revisionAgent = ResumeRevisionAgent(
            resume: resume,
            llmFacade: llmFacade,
            modelId: modelId,
            pdfGenerator: pdfGenerator,
            modelContext: modelContext
        )
        agent = revisionAgent

        do {
            try await revisionAgent.run(
                jobDescription: jobDescription,
                knowledgeCards: knowledgeCards,
                skills: skills,
                coverRefs: coverRefs
            )
        } catch {
            if revisionAgent.status != .cancelled {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func handleCancel() {
        agent?.cancel()
        closeWindow()
    }

    private func closeWindow() {
        NSApp.keyWindow?.performClose(nil)
    }
}
