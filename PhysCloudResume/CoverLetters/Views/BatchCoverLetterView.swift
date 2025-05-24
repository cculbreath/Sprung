import SwiftUI
import SwiftData

enum BatchMode {
    case generate
    case existing
}

struct BatchCoverLetterView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) var appState: AppState
    @Environment(JobAppStore.self) var jobAppStore: JobAppStore
    @Environment(CoverLetterStore.self) var coverLetterStore: CoverLetterStore
    
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
    
    // Get model service for fetching available models
    @EnvironmentObject private var modelService: ModelService
    
    let availableRevisions: [CoverLetterPrompts.EditorPrompts] = [.improve, .zissner, .mimic]
    
    var body: some View {
        VStack(spacing: 20) {
            headerSection
            modeSelector
            contentSection
            actionSection
        }
        .padding()
        .frame(width: 500, height: 600)
        .onAppear {
            // Set default revision model to the preferred model
            revisionModel = OpenAIModelFetcher.getPreferredModelString()
            
            // Check if we need to auto-fetch models on appear (exact same logic as ModelPickerView)
            let needsFetching = modelService.fetchStatus.values.allSatisfy { status in
                if case .notStarted = status { return true }
                return false
            }
            
            if needsFetching {
                fetchModels()
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
            revisionsBox
        }
    }
    
    private var modelSelectionBox: some View {
        GroupBox("Select Models") {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    let allModels = modelService.getAllModels()
                    let providers = [
                        AIModels.Provider.openai,
                        AIModels.Provider.claude,
                        AIModels.Provider.grok,
                        AIModels.Provider.gemini
                    ]
                    
                    ForEach(providers, id: \.self) { provider in
                        if let models = allModels[provider], !models.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(provider)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .textCase(.uppercase)
                                
                                ForEach(models, id: \.self) { model in
                                    let sanitizedModel = OpenAIModelFetcher.sanitizeModelName(model)
                                    HStack {
                                        Toggle(isOn: Binding(
                                            get: { selectedModels.contains(sanitizedModel) },
                                            set: { isSelected in
                                                if isSelected {
                                                    selectedModels.insert(sanitizedModel)
                                                } else {
                                                    selectedModels.remove(sanitizedModel)
                                                }
                                            }
                                        )) {
                                            Text(formatModelNameFromPicker(sanitizedModel))
                                                .font(.system(.body))
                                        }
                                        .toggleStyle(CheckboxToggleStyle())
                                    }
                                }
                            }
                            .padding(.bottom, 8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
        }
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
            
            // Model picker for revisions (using same logic as ModelPickerView)
            if !selectedRevisions.isEmpty {
                GroupBox("Revision Model") {
                    let allModels = modelService.getAllModels()
                    let providers = [
                        AIModels.Provider.openai,
                        AIModels.Provider.claude,
                        AIModels.Provider.grok,
                        AIModels.Provider.gemini
                    ]
                    
                    Picker("Select model for revisions", selection: $revisionModel) {
                        Text("Select a model").tag("")
                        Text("Same as generating model").tag("SAME_AS_GENERATING")
                        
                        ForEach(providers, id: \.self) { provider in
                            if let models = allModels[provider], !models.isEmpty {
                                Section(header: Text(provider)) {
                                    ForEach(models, id: \.self) { model in
                                        let sanitizedModel = OpenAIModelFetcher.sanitizeModelName(model)
                                        Text(formatModelNameFromPicker(sanitizedModel)).tag(sanitizedModel)
                                    }
                                }
                            }
                        }
                    }
                    .pickerStyle(DefaultPickerStyle())
                }
            }
        }
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
                                                       revisionModel.isEmpty || revisionModel == OpenAIModelFetcher.getPreferredModelString() {
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
                                                        Text("• \(AIModels.friendlyModelName(for: model) ?? model)")
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
            
            // Model picker for revisions (using same logic as ModelPickerView)
            GroupBox("Revision Model") {
                let allModels = modelService.getAllModels()
                let providers = [
                    AIModels.Provider.openai,
                    AIModels.Provider.claude,
                    AIModels.Provider.grok,
                    AIModels.Provider.gemini
                ]
                
                Picker("Select model for revisions", selection: $revisionModel) {
                    Text("Select a model").tag("")
                    Text("Same as generating model").tag("SAME_AS_GENERATING")
                    
                    ForEach(providers, id: \.self) { provider in
                        if let models = allModels[provider], !models.isEmpty {
                            Section(header: Text(provider)) {
                                ForEach(models, id: \.self) { model in
                                    let sanitizedModel = OpenAIModelFetcher.sanitizeModelName(model)
                                    Text(formatModelNameFromPicker(sanitizedModel)).tag(sanitizedModel)
                                }
                            }
                        }
                    }
                }
                .pickerStyle(DefaultPickerStyle())
            }
        }
    }
    
    private var actionSection: some View {
        VStack(spacing: 16) {
            // Summary
            GroupBox("Summary") {
                VStack(alignment: .leading, spacing: 4) {
                    if mode == .generate {
                        Text("Selected Models: \(selectedModels.count)")
                        Text("Selected Revisions: \(selectedRevisions.count)")
                        Text("Total Letters to Generate: \(calculateTotalLetters())")
                            .fontWeight(.semibold)
                    } else {
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
                .disabled(isGenerating || (mode == .generate ? selectedModels.isEmpty : (selectedLetters.isEmpty || selectedRevisions.isEmpty || revisionModel.isEmpty)))
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
            return AIModels.friendlyModelName(for: revisionModel) ?? revisionModel
        }
    }
    
    /// Formats a model name for display (exact same logic as ModelPickerView)
    /// - Parameter model: The raw model name
    /// - Returns: A formatted model name
    private func formatModelNameFromPicker(_ model: String) -> String {
        // Use the same formatting as MultiModelChooseBestCoverLetterSheet
        return AIModels.friendlyModelName(for: model) ?? model
    }
    
    /// Fetches all models from enabled providers (exact same logic as ModelPickerView)
    private func fetchModels() {
        Logger.debug("Fetching all model lists")
        
        // Get API keys from UserDefaults
        let apiKeys = [
            AIModels.Provider.openai: UserDefaults.standard.string(forKey: "openAiApiKey") ?? "none",
            AIModels.Provider.claude: UserDefaults.standard.string(forKey: "claudeApiKey") ?? "none",
            AIModels.Provider.grok: UserDefaults.standard.string(forKey: "grokApiKey") ?? "none",
            AIModels.Provider.gemini: UserDefaults.standard.string(forKey: "geminiApiKey") ?? "none"
        ]
        
        modelService.fetchAllModels(apiKeys: apiKeys)
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
                coverLetterStore: coverLetterStore
            )
            
            do {
                if mode == .generate {
                    // Generate mode - need resume and base cover letter
                    guard let selectedResume = app.selectedRes,
                          let baseCoverLetter = app.selectedCover else { 
                        await MainActor.run {
                            errorMessage = "Missing resume or base cover letter"
                            isGenerating = false
                        }
                        return
                    }
                    
                    // Generate cover letters with progress tracking
                    try await generator.generateBatch(
                        baseCoverLetter: baseCoverLetter,
                        resume: selectedResume,
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
                          let selectedResume = app.selectedRes else { 
                        await MainActor.run {
                            errorMessage = "Missing required selections"
                            isGenerating = false
                        }
                        return
                    }
                    
                    // Generate revisions for existing letters
                    try await generator.generateRevisionsForExistingLetters(
                        existingLetters: Array(selectedLetters),
                        resume: selectedResume,
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
}

// Checkbox toggle style
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .foregroundColor(configuration.isOn ? .accentColor : .secondary)
                .onTapGesture {
                    configuration.isOn.toggle()
                }
            configuration.label
        }
    }
}