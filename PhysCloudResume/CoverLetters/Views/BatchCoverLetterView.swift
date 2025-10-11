import SwiftUI
import SwiftData

enum BatchMode {
    case generate
    case existing
}

struct BatchCoverLetterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) var appState: AppState
    @Environment(JobAppStore.self) var jobAppStore: JobAppStore
    @Environment(CoverLetterStore.self) var coverLetterStore: CoverLetterStore
    @Environment(CoverRefStore.self) var coverRefStore: CoverRefStore
    @Environment(EnabledLLMStore.self) private var enabledLLMStore: EnabledLLMStore
    @Environment(LLMFacade.self) private var llmFacade: LLMFacade
    @Environment(CoverLetterService.self) private var coverLetterService: CoverLetterService
    @Environment(AppEnvironment.self) private var appEnvironment: AppEnvironment
    @Environment(OpenRouterService.self) private var openRouterService: OpenRouterService
    @Environment(\.modelContext) private var modelContext

    // Live SwiftData query to automatically refresh on model changes
    @Query(sort: \CoverRef.name) private var allCoverRefs: [CoverRef]

    @State private var mode: BatchMode = .generate
    @State private var selectedModels: Set<String> = []
    @State private var selectedLetters: Set<CoverLetter> = []
    @State private var selectedRevisions: Set<CoverLetterPrompts.EditorPrompts> = []
    @State private var revisionModel: String = "" // Model to use for revisions
    @State private var isGenerating = false
    @State private var progress: Double = 0
    @State private var totalOperations: Int = 0
    @State private var completedOperations: Int = 0
    @State private var errorMessage: String?

    // Source management states
    @State private var includeResumeRefs: Bool = true
    @State private var selectedBackgroundFacts: Set<String> = []
    @State private var selectedWritingSamples: Set<String> = []
    @State private var showAddSheet = false
    @State private var newRefType: CoverRefType = .backgroundFact
    
    let availableRevisions: [CoverLetterPrompts.EditorPrompts] = [.improve, .zissner, .mimic]
    
    var body: some View {
        VStack(spacing: 0) {
            // Scrollable content area
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    modeSelector
                    contentSection
                }
                .padding()
                .padding(.bottom, 8) // Extra space before action section
            }
            
            // Fixed action section at bottom
            Divider()
            actionSection
                .padding()
                .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
        }
        .frame(width: 550, height: 600)
        .onAppear {
            // Load persisted model selection
            selectedModels = appState.settings.batchCoverLetterModels
            
            // Load default reference selections
            loadDefaultSelections()
            
            // Fetch OpenRouter models if we don't have any and have a valid API key
            if appState.hasValidOpenRouterKey && openRouterService.availableModels.isEmpty {
                Task {
                    await openRouterService.fetchModels()
                }
            }
        }
        .onChange(of: selectedModels) { _, newValue in
            // Save model selection whenever it changes
            appState.settings.batchCoverLetterModels = newValue
        }
        .onChange(of: selectedRevisions) { _, newValue in
            // Set default revision model to "Same as generating" when revisions are first selected
            if !newValue.isEmpty && revisionModel.isEmpty {
                revisionModel = "SAME_AS_GENERATING"
            }
        }
    }
    
    private var headerSection: some View {
        Text("Batch Cover Letter Operations")
            .font(.title2)
            .fontWeight(.semibold)
    }
    
    private var modeSelector: some View {
        Picker("Mode", selection: $mode) {
            Text("Generate New").tag(BatchMode.generate)
            Text("Revise Existing").tag(BatchMode.existing)
        }
        .pickerStyle(SegmentedPickerStyle())
        .padding(.horizontal)
    }
    
    private var contentSection: some View {
        Group {
            if mode == .generate {
                generateModeContent
            } else {
                existingModeContent
            }
        }
    }
    
    private var generateModeContent: some View {
        VStack(spacing: 16) {
            modelSelectionBox
            sourceManagementSection
            revisionsBox
        }
    }
    
    
    private var modelSelectionBox: some View {
        CheckboxModelPicker(
            selectedModels: $selectedModels,
            title: "Select Models"
        )
    }
    
    private var revisionsBox: some View {
        VStack(spacing: 16) {
            // Revision Selection
            GroupBox("Select Revisions (Optional)") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(availableRevisions, id: \.self) { revision in
                        HStack {
                            Toggle(isOn: Binding(
                                get: { selectedRevisions.contains(revision) },
                                set: { isSelected in
                                    if isSelected {
                                        selectedRevisions.insert(revision)
                                    } else {
                                        selectedRevisions.remove(revision)
                                    }
                                }
                            )) {
                                Text(revision.rawValue.capitalized)
                                    .font(.system(.body))
                            }
                            .toggleStyle(CheckboxToggleStyle())
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Model picker for revisions
            if !selectedRevisions.isEmpty {
                GroupBox("Revision Model") {
                    DropdownModelPicker(
                        selectedModel: $revisionModel,
                        title: "Select Revision Model",
                        showInGroupBox: false,
                        includeSpecialOption: ("Same as generating model", "SAME_AS_GENERATING")
                    )
                }
            }
        }
    }
    
    private var sourceManagementSection: some View {
        CoverRefSelectionManagerView(
            includeResumeRefs: $includeResumeRefs,
            selectedBackgroundFacts: $selectedBackgroundFacts,
            selectedWritingSamples: $selectedWritingSamples,
            showGroupBox: true
        )
    }
    
    private var existingModeContent: some View {
        VStack(spacing: 16) {
            // Existing letter selection
            GroupBox("Select Cover Letters") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if let app = jobAppStore.selectedApp {
                                ForEach(app.coverLetters.sorted(by: { $0.moddedDate > $1.moddedDate }), id: \.self) { letter in
                                    HStack {
                                        Toggle(isOn: Binding(
                                            get: { selectedLetters.contains(letter) },
                                            set: { isSelected in
                                                if isSelected {
                                                    selectedLetters.insert(letter)
                                                    // If this is the first letter selected and it has a generation model,
                                                    // use it as the default revision model
                                                    if selectedLetters.count == 1, 
                                                       let model = letter.generationModel,
                                                       revisionModel.isEmpty {
                                                        revisionModel = model
                                                    }
                                                } else {
                                                    selectedLetters.remove(letter)
                                                }
                                            }
                                        )) {
                                            VStack(alignment: .leading) {
                                                Text(letter.name)
                                                    .font(.system(.body))
                                                HStack {
                                                    Text("Modified: \(letter.moddedDate.formatted())")
                                                    if let model = letter.generationModel {
                                                        Text("• \(openRouterService.friendlyModelName(for: model))")
                                                    }
                                                }
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            }
                                        }
                                        .toggleStyle(CheckboxToggleStyle())
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                }
            
            // Revision Selection
            GroupBox("Select Revisions") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(availableRevisions, id: \.self) { revision in
                        Toggle(isOn: Binding(
                            get: { selectedRevisions.contains(revision) },
                            set: { isSelected in
                                if isSelected {
                                    selectedRevisions.insert(revision)
                                } else {
                                    selectedRevisions.remove(revision)
                                }
                            }
                        )) {
                            Text(revision.rawValue.capitalized)
                        }
                        .toggleStyle(CheckboxToggleStyle())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Model picker for revisions using OpenRouter
            DropdownModelPicker(
                selectedModel: $revisionModel,
                title: "Revision Model"
            )
        }
    }
    
    private var actionSection: some View {
        VStack(spacing: 16) {
            // Summary
            GroupBox("Summary") {
                VStack(alignment: .leading, spacing: 4) {
                    if mode == .generate {
                        if let app = jobAppStore.selectedApp {
                            Text("Selected Resume: \(app.selectedRes?.template?.name ?? app.selectedRes?.template?.slug.capitalized ?? "None")")
                        }
                        Text("Selected Models: \(selectedModels.count)")
                        Text("Selected Revisions: \(selectedRevisions.count)")
                        if selectedRevisions.isEmpty {
                            Text("Total Letters to Generate: \(calculateTotalLetters())")
                                .fontWeight(.semibold)
                        } else {
                            Text("Base Letters: \(selectedModels.count)")
                            Text("Revisions: \(selectedModels.count * selectedRevisions.count)")
                            Text("Total Letters: \(calculateTotalLetters())")
                                .fontWeight(.semibold)
                        }
                    } else {
                        if let app = jobAppStore.selectedApp {
                            Text("Selected Resume: \(app.selectedRes?.template?.name ?? app.selectedRes?.template?.slug.capitalized ?? "None")")
                        }
                        Text("Selected Letters: \(selectedLetters.count)")
                        Text("Selected Revisions: \(selectedRevisions.count)")
                        Text("Model for Revisions: \(getRevisionModelDisplayText())")
                        Text("Total Revisions to Create: \(calculateTotalLetters())")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Progress
            if isGenerating {
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle())
                    Text("\(completedOperations) of \(totalOperations) operations completed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Error Message
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            // Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button(mode == .generate ? "Start Generation" : "Start Revisions") {
                    startBatchGeneration()
                }
                .keyboardShortcut(.return)
                .disabled(isGenerating || !canStartGeneration())
            }
        }
    }
    
    private func calculateTotalLetters() -> Int {
        if mode == .generate {
            let baseLetters = selectedModels.count
            let revisionLetters = selectedModels.count * selectedRevisions.count
            return baseLetters + revisionLetters
        } else {
            // For existing mode, just multiply selected letters by selected revisions
            return selectedLetters.count * selectedRevisions.count
        }
    }
    
    private func getRevisionModelDisplayText() -> String {
        if revisionModel == "SAME_AS_GENERATING" {
            return "Same as generating model"
        } else if revisionModel.isEmpty {
            return "Not selected"
        } else {
            return openRouterService.friendlyModelName(for: revisionModel)
        }
    }
    
    
    private func startBatchGeneration() {
        guard let app = jobAppStore.selectedApp else { return }
        
        isGenerating = true
        errorMessage = nil
        
        // Calculate total operations
        totalOperations = calculateTotalLetters()
        completedOperations = 0
        progress = 0
        
        Task {
            let generator = BatchCoverLetterGenerator(
                appState: appState,
                jobAppStore: jobAppStore,
                coverLetterStore: coverLetterStore,
                llmFacade: llmFacade,
                coverLetterService: coverLetterService,
                exportCoordinator: appEnvironment.resumeExportCoordinator
            )
            
            do {
                if mode == .generate {
                    // Generate mode - need resume
                    guard let resume = app.selectedRes else { 
                        await MainActor.run {
                            errorMessage = "Please select a resume in the Resume tab"
                            isGenerating = false
                        }
                        return
                    }
                    
                    // Create a base cover letter with the selected sources
                    let baseCoverLetter = CoverLetter(
                        enabledRefs: getSelectedCoverRefs(),
                        jobApp: app
                    )
                    baseCoverLetter.includeResumeRefs = includeResumeRefs
                    baseCoverLetter.content = "" // Will be generated
                    
                    // Debug: Verify jobApp relationship is set
                    Logger.debug("🔍 Created baseCoverLetter with jobApp: \(baseCoverLetter.jobApp?.id.uuidString ?? "nil")")
                    
                    // Generate cover letters with progress tracking
                    try await generator.generateBatch(
                        baseCoverLetter: baseCoverLetter,
                        jobApp: app,
                        resume: resume,
                        models: Array(selectedModels),
                        revisions: Array(selectedRevisions),
                        revisionModel: revisionModel,
                        onProgress: { completed, total in
                            await MainActor.run {
                                completedOperations = completed
                                totalOperations = total
                                progress = Double(completed) / Double(total)
                            }
                        }
                    )
                } else {
                    // Revision mode - need selected letters and revision model
                    guard !selectedLetters.isEmpty,
                          !revisionModel.isEmpty,
                          let resume = app.selectedRes else { 
                        await MainActor.run {
                            errorMessage = "Missing required selections or resume not selected"
                            isGenerating = false
                        }
                        return
                    }
                    
                    // Generate revisions for existing letters
                    try await generator.generateRevisionsForExistingLetters(
                        existingLetters: Array(selectedLetters),
                        resume: resume,
                        revisionModel: revisionModel,
                        revisions: Array(selectedRevisions),
                        onProgress: { completed, total in
                            await MainActor.run {
                                completedOperations = completed
                                totalOperations = total
                                progress = Double(completed) / Double(total)
                            }
                        }
                    )
                }
                
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Error: \(error.localizedDescription)"
                    isGenerating = false
                }
            }
        }
    }
    
    private func loadDefaultSelections() {
        // Pre-select enabled by default refs
        let backgroundFacts = allCoverRefs.filter { $0.type == .backgroundFact }
        let writingSamples = allCoverRefs.filter { $0.type == .writingSample }
        
        for ref in backgroundFacts where ref.enabledByDefault {
            selectedBackgroundFacts.insert(ref.id.description)
        }
        
        for ref in writingSamples where ref.enabledByDefault {
            selectedWritingSamples.insert(ref.id.description)
        }
    }
    
    private func canStartGeneration() -> Bool {
        guard let app = jobAppStore.selectedApp else { return false }
        
        if mode == .generate {
            return !selectedModels.isEmpty && app.selectedRes != nil
        } else {
            return !selectedLetters.isEmpty && !selectedRevisions.isEmpty && !revisionModel.isEmpty && app.selectedRes != nil
        }
    }
    
    private func getSelectedCoverRefs() -> [CoverRef] {
        var refs: [CoverRef] = []
        
        // Add selected background facts
        let backgroundFacts = allCoverRefs.filter { $0.type == .backgroundFact }
        for ref in backgroundFacts where selectedBackgroundFacts.contains(ref.id.description) {
            refs.append(ref)
        }
        
        // Add selected writing samples
        let writingSamples = allCoverRefs.filter { $0.type == .writingSample }
        for ref in writingSamples where selectedWritingSamples.contains(ref.id.description) {
            refs.append(ref)
        }
        
        return refs
    }
}
