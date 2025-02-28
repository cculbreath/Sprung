import SwiftUI

enum apis: String, Identifiable, CaseIterable {
    var id: Self { self }
    case scrapingDog = "Scraping Dog"
    case brightData = "Bright Data"
}

struct SettingsView: View {
    @AppStorage("scrapingDogApiKey") var scrapingDogApiKey: String = "none"
    @AppStorage("openAiApiKey") var openAiApiKey: String = "none"
    @AppStorage("brightDataApiKey") var brightDataApiKey: String = "none"
    @AppStorage("preferredApi") var preferredApi: apis = .scrapingDog

    @AppStorage("availableStyles") private var availableStylesString: String = "Typewriter"
    @State private var availableStyles: [String] = []
    @State private var newStyle: String = ""

    @State private var isEditingScrapingDog = false
    @State private var isEditingBrightData = false
    @State private var isEditingOpenAI = false

    @State private var editedScrapingDogApiKey = ""
    @State private var editedOpenAiApiKey = ""
    @State private var editedBrightDataApiKey = ""

    @State private var isHoveringCheckmark = false
    @State private var isHoveringXmark = false

    var body: some View {
        VStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
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

                    Picker("Preferred API", selection: $preferredApi) {
                        ForEach(apis.allCases) { api in
                            Text(api.rawValue)
                        }
                    }
                    .pickerStyle(.radioGroup)
//                    DatabaseBackupView()
                }
                .padding()
            }
        }
        .frame(minWidth: 450, idealWidth: 600, maxWidth: 800,
               minHeight: 500, idealHeight: 600, maxHeight: 800)
        .onAppear {
            loadAvailableStyles()
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
}
