import SwiftUI

enum apis: String, Identifiable, CaseIterable {
    var id: Self { self }
    case scrapingDog = "Scraping Dog"
    case brightData = "Bright Data"
    case proxycurl = "Proxycurl"
}

struct SettingsView: View {
    @AppStorage("scrapingDogApiKey") var scrapingDogApiKey: String = "none"
    @AppStorage("openAiApiKey") var openAiApiKey: String = "none"
    @AppStorage("brightDataApiKey") var brightDataApiKey: String = "none"
    @AppStorage("proxycurlApiKey") var proxycurlApiKey: String = "none"
    @AppStorage("preferredApi") var preferredApi: apis = .scrapingDog
    @AppStorage("preferredOpenAIModel") var preferredOpenAIModel: String = "gpt-4o-2024-08-06"

    // TTS Settings
    @AppStorage("ttsEnabled") var ttsEnabled: Bool = false
    @AppStorage("ttsVoice") var ttsVoice: String = "nova"
    @AppStorage("ttsInstructions") var ttsInstructions: String = "Voice Affect: Confident, composed, and respectful; project well-supported authority and confidence without hubris.\nTone: Sincere, empathetic, and authoritative—but not arrogant. Express genuine humility while conveying competence.\nPacing: Brisk and confident, but unrushed. Slow moderately for emphasis, demonstrating thoughtfulness while prioritizing efficiency and respect for your audience's time.\nEmotion: Engaged and confident; speak with warmth and charisma. Lean into rising pitch, confident resolution, and the identifiable rhythms of a skilled orator.\nPronunciation: Clear and precise, emphasizing understanding and fluency with technical concepts, and a deft handling of even the most stubborn aspects of the English language.\nPauses: Brief pauses for emphasis and gravitas, but with an overall cadence of efficiency and forward momentum."

    @AppStorage("availableStyles") private var availableStylesString: String = "Typewriter"
    @State private var availableStyles: [String] = []
    @State private var newStyle: String = ""

    @State private var isEditingScrapingDog = false
    @State private var isEditingBrightData = false
    @State private var isEditingOpenAI = false
    @State private var isEditingProxycurl = false

    @State private var editedScrapingDogApiKey = ""
    @State private var editedOpenAiApiKey = ""
    @State private var editedBrightDataApiKey = ""
    @State private var editedProxycurlApiKey = ""

    @State private var isHoveringCheckmark = false
    @State private var isHoveringXmark = false

    @State private var availableModels: [String] = []
    @State private var isLoadingModels: Bool = false
    @State private var modelError: String? = nil

    // TTS preview state
    @State private var ttsProvider: OpenAITTSProvider?
    @State private var isPreviewingVoice: Bool = false
    @State private var ttsError: String? = nil
    @State private var showTTSError: Bool = false

    var body: some View {
        VStack {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 15) {
                    Text("API Keys")
                        .font(.headline)
                        .padding(.bottom, 5)

                    VStack(spacing: 0) {
                        apiKeyRow(
                            label: "Scraping Dog",
                            icon: "dog.fill",
                            value: $scrapingDogApiKey,
                            isEditing: $isEditingScrapingDog,
                            editedValue: $editedScrapingDogApiKey,
                            isHoveringCheckmark: $isHoveringCheckmark,
                            isHoveringXmark: $isHoveringXmark
                        )
                        Divider()
                        apiKeyRow(
                            label: "OpenAI",
                            icon: "sparkles",
                            value: $openAiApiKey,
                            isEditing: $isEditingOpenAI,
                            editedValue: $editedOpenAiApiKey,
                            isHoveringCheckmark: $isHoveringCheckmark,
                            isHoveringXmark: $isHoveringXmark
                        )
                        Divider()
                        apiKeyRow(
                            label: "Bright Data",
                            icon: "sun.max",
                            value: $brightDataApiKey,
                            isEditing: $isEditingBrightData,
                            editedValue: $editedBrightDataApiKey,
                            isHoveringCheckmark: $isHoveringCheckmark,
                            isHoveringXmark: $isHoveringXmark
                        )
                        Divider()
                        apiKeyRow(
                            label: "Proxycurl",
                            icon: "link",
                            value: $proxycurlApiKey,
                            isEditing: $isEditingProxycurl,
                            editedValue: $editedProxycurlApiKey,
                            isHoveringCheckmark: $isHoveringCheckmark,
                            isHoveringXmark: $isHoveringXmark
                        )
                    }
                    .padding(10)
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.7), lineWidth: 1)
                    )

                    // OpenAI Model Selection Section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("OpenAI Model")
                            .font(.headline)

                        HStack {
                            Picker("Model", selection: $preferredOpenAIModel) {
                                ForEach(availableModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .onChange(of: preferredOpenAIModel) { oldValue, newValue in
                                print("Changed OpenAI model: \(oldValue) → \(newValue)")
                            }
                            .disabled(isLoadingModels || availableModels.isEmpty)
                            .frame(maxWidth: .infinity)

                            Button(action: fetchOpenAIModels) {
                                if isLoadingModels {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .disabled(openAiApiKey == "none")
                        }

                        if let error = modelError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        if availableModels.isEmpty && !isLoadingModels && modelError == nil {
                            Text("Click refresh to load available models")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(10)
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.7), lineWidth: 1)
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Available Styles")
                            .font(.headline)

                        ForEach(availableStyles, id: \.self) { style in
                            HStack {
                                Text(style)
                                Spacer()
                                if availableStyles.count > 1 {
                                    Button(action: { removeStyle(style) }) {
                                        Image(systemName: "minus.circle")
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                }
                            }
                        }
                        HStack {
                            TextField("New Style", text: $newStyle)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            Button(action: addNewStyle) {
                                Image(systemName: "plus.circle")
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                    .padding(10)
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.7), lineWidth: 1)
                    )

                    // Text-to-Speech Settings
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Text-to-Speech")
                            .font(.headline)

                        // Enable TTS Toggle
                        Toggle("Enable Text-to-Speech", isOn: $ttsEnabled)
                            .toggleStyle(.switch)
                            .disabled(openAiApiKey == "none")
                            .onChange(of: ttsEnabled) { oldValue, newValue in
                                print("TTS enabled changed: \(oldValue) → \(newValue)")
                            }

                        if openAiApiKey == "none" {
                            Text("Add OpenAI API key to enable TTS")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Voice Selection
                        if ttsEnabled {
                            Divider()
                                .padding(.vertical, 5)

                            Text("Voice")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Picker("TTS Voice", selection: $ttsVoice) {
                                Group {
                                    Text("Alloy (Neutral)").tag("alloy")
                                    Text("Echo (Male)").tag("echo")
                                    Text("Fable (British)").tag("fable")
                                    Text("Nova (Female)").tag("nova")
                                    Text("Onyx (Deep Male)").tag("onyx")
                                    Text("Shimmer (Soft Female)").tag("shimmer")
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            // Voice Preview
                            HStack {
                                Spacer()
                                Button(action: previewVoice) {
                                    Label(isPreviewingVoice ? "Stop Preview" : "Preview Voice",
                                          systemImage: isPreviewingVoice ? "speaker.wave.3.fill" : "speaker.wave.2")
                                }
                                .disabled(openAiApiKey == "none")
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help(isPreviewingVoice ? "Stop voice preview" : "Preview the selected voice")
                                Spacer()
                            }
                            .padding(.top, 5)

                            // Voice Instructions
                            Divider()
                                .padding(.vertical, 5)

                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text("Voice Instructions")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)

                                    Spacer()

                                    Button("Reset to Default") {
                                        resetToDefaultInstructions()
                                    }
                                    .buttonStyle(.borderless)
                                    .controlSize(.small)
                                    .font(.caption)
                                }

                                TextEditor(text: $ttsInstructions)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(minHeight: 100, idealHeight: 150, maxHeight: .infinity)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                    )

                                Text("Instructions tell the AI how to style the voice. Changes apply to all TTS operations.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.7), lineWidth: 1)
                    )

                    // Preferred API Selection
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Preferred API")
                            .font(.headline)
                        
                        Picker("Preferred API", selection: $preferredApi) {
                            ForEach(apis.allCases) { api in
                                Text(api.rawValue)
                            }
                        }
                        .pickerStyle(.radioGroup)
                    }
                    .padding(10)
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.7), lineWidth: 1)
                    )
//                    DatabaseBackupView()
                }
                .padding()
            }
        }
        .frame(minWidth: 450, idealWidth: 600, maxWidth: .infinity,
               minHeight: 500, idealHeight: 600, maxHeight: .infinity)
        .padding(.vertical)
        // Allow the sheet to be resized
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            loadAvailableStyles()
            if openAiApiKey != "none" {
                fetchOpenAIModels()
                // Initialize TTS provider if not already initialized
                if ttsProvider == nil {
                    ttsProvider = OpenAITTSProvider(apiKey: openAiApiKey)
                }
            }
        }
        .alert("TTS Error", isPresented: $showTTSError) {
            Button("OK") { showTTSError = false }
        } message: {
            Text(ttsError ?? "An error occurred with text-to-speech")
        }
    }

    private func fetchOpenAIModels() {
        guard openAiApiKey != "none" else {
            modelError = "API key is required to fetch models"
            return
        }

        isLoadingModels = true
        modelError = nil

        Task {
            let models = await OpenAIModelFetcher.fetchAvailableModels(apiKey: openAiApiKey)

            await MainActor.run {
                if models.isEmpty {
                    modelError = "Failed to fetch models or no models available"
                } else {
                    availableModels = models

                    // Set default model if current selection isn't in the list
                    if !models.contains(preferredOpenAIModel) && !models.isEmpty {
                        preferredOpenAIModel = models.first!
                    }
                }
                isLoadingModels = false
            }
        }
    }

    @ViewBuilder
    private func apiKeyRow(
        label: String, icon: String, value: Binding<String>, isEditing: Binding<Bool>,
        editedValue: Binding<String>, isHoveringCheckmark: Binding<Bool>, isHoveringXmark: Binding<Bool>
    ) -> some View {
        HStack {
            HStack {
                Image(systemName: icon)
                Text(label)
                    .fontWeight(.medium)
                    .foregroundColor(.black)
            }
            Spacer()
            if isEditing.wrappedValue {
                HStack {
                    TextField("Enter API Key", text: editedValue)
                        .textFieldStyle(PlainTextFieldStyle())
                        .foregroundColor(.gray)
                    Button(action: {
                        value.wrappedValue = editedValue.wrappedValue
                        isEditing.wrappedValue = false
                        if label == "OpenAI", !editedValue.wrappedValue.isEmpty, editedValue.wrappedValue != "none" {
                            fetchOpenAIModels()
                        }
                    }) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(isHoveringCheckmark.wrappedValue ? .green : .gray)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .onHover { hovering in
                        isHoveringCheckmark.wrappedValue = hovering
                    }
                    Button(action: {
                        isEditing.wrappedValue = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(isHoveringXmark.wrappedValue ? .red : .gray)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .onHover { hovering in
                        isHoveringXmark.wrappedValue = hovering
                    }
                }
                .frame(maxWidth: 200)
            } else {
                HStack {
                    Text(value.wrappedValue)
                        .italic()
                        .foregroundColor(.gray)
                        .fontWeight(.light)
                    Image(systemName: "square.and.pencil")
                        .onTapGesture {
                            editedValue.wrappedValue = value.wrappedValue
                            isEditing.wrappedValue = true
                        }
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func loadAvailableStyles() {
        availableStyles = availableStylesString
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func addNewStyle() {
        let trimmed = newStyle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !availableStyles.contains(trimmed) else { return }
        availableStyles.append(trimmed)
        availableStylesString = availableStyles.joined(separator: ", ")
        newStyle = ""
    }

    private func removeStyle(_ style: String) {
        availableStyles.removeAll { $0 == style }
        if availableStyles.isEmpty {
            availableStyles = ["Typewriter"]
        }
        availableStylesString = availableStyles.joined(separator: ", ")
    }

    /// Preview the currently selected TTS voice
    private func previewVoice() {
        // If already previewing, stop the current preview
        if isPreviewingVoice {
            ttsProvider?.stopSpeaking()
            isPreviewingVoice = false
            return
        }

        // Make sure we have a provider and API key
        guard openAiApiKey != "none" else {
            ttsError = "OpenAI API key is required for TTS"
            showTTSError = true
            return
        }

        // Initialize provider if needed
        if ttsProvider == nil {
            ttsProvider = OpenAITTSProvider(apiKey: openAiApiKey)
        }

        // Sample text for preview
        let sampleText = "This is a preview of the \(ttsVoice) voice with custom instructions. It can be used to read your resumes and cover letters aloud."

        // Set preview state
        isPreviewingVoice = true

        // Get the selected voice
        let voice = OpenAITTSProvider.Voice(rawValue: ttsVoice) ?? .nova

        // Get voice instructions (if any)
        let instructions = ttsInstructions.isEmpty ? nil : ttsInstructions

        // Speak the sample text with instructions
        ttsProvider?.speakText(sampleText, voice: voice, instructions: instructions) { error in
            DispatchQueue.main.async {
                // Reset preview state
                self.isPreviewingVoice = false

                // Handle any errors
                if let error = error {
                    self.ttsError = error.localizedDescription
                    self.showTTSError = true
                    print("TTS preview error: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Reset voice instructions to the default value
    private func resetToDefaultInstructions() {
        ttsInstructions = "Voice Affect: Confident, composed, and respectful; project well-supported authority and confidence without hubris.\nTone: Sincere, empathetic, and authoritative—but not arrogant. Express genuine humility while conveying competence.\nPacing: Brisk and confident, but unrushed. Slow moderately for emphasis, demonstrating thoughtfulness while prioritizing efficiency and respect for your audience's time.\nEmotion: Engaged and confident; speak with warmth and charisma. Lean into rising pitch, confident resolution, and the identifiable rhythms of a skilled orator.\nPronunciation: Clear and precise, emphasizing understanding and fluency with technical concepts, and a deft handling of even the most stubborn aspects of the English language.\nPauses: Brief pauses for emphasis and gravitas, but with an overall cadence of efficiency and forward momentum."
    }
}
