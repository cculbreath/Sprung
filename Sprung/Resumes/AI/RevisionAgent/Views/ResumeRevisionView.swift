import SwiftUI
import SwiftData

/// Main container view for the resume revision agent session.
/// Presents a split layout: PDF preview on the left, chat stream on the right.
struct ResumeRevisionView: View {
    @Environment(\.dismiss) private var dismiss
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
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            if let agent = agent {
                RevisionToolbar(
                    status: agent.status,
                    currentAction: agent.currentAction,
                    onCancel: { handleCancel() },
                    onAccept: { dismiss() }
                )
                Divider()
            }

            // Main content
            HStack(spacing: 0) {
                // Left pane: PDF preview
                pdfPreviewPane
                    .frame(minWidth: 400, idealWidth: 500, maxWidth: 600)

                Divider()

                // Right pane: Chat stream
                chatPane
                    .frame(minWidth: 400, maxWidth: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .task {
            await startAgent()
        }
        .alert("Revision Error", isPresented: $showError) {
            Button("OK") { dismiss() }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
    }

    // MARK: - PDF Preview

    @ViewBuilder
    private var pdfPreviewPane: some View {
        Group {
            if let pdfData = pdfData {
                PDFPreviewView(data: pdfData)
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
        dismiss()
    }
}

// MARK: - PDF Preview (NSView wrapper)

private struct PDFPreviewView: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignTop
        scrollView.documentView = imageView

        updateImage(imageView)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let imageView = nsView.documentView as? NSImageView {
            updateImage(imageView)
        }
    }

    private func updateImage(_ imageView: NSImageView) {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider),
              let page = document.page(at: 1) else {
            return
        }

        let pageRect = page.getBoxRect(.mediaBox)
        let scale: CGFloat = 2.0
        let width = pageRect.width * scale
        let height = pageRect.height * scale

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(width),
            height: Int(height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.drawPDFPage(page)

        if let cgImage = context.makeImage() {
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: pageRect.width, height: pageRect.height))
            imageView.image = nsImage
            imageView.frame = NSRect(x: 0, y: 0, width: pageRect.width, height: pageRect.height)
        }
    }
}
