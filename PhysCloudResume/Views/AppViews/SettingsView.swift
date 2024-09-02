import SwiftUI

struct SettingsView: View {
    @AppStorage("scrapingDogApiKey") var scrapingDogApiKey: String = "none"
    @AppStorage("openAiApiKey") var openAiApiKey: String = "none"
    
    @State private var isEditingScrapingDog = false
    @State private var isEditingOpenAI = false
    
    @State private var editedScrapingDogApiKey = ""
    @State private var editedOpenAiApiKey = ""
    
    @State private var isHoveringCheckmark = false
    @State private var isHoveringXmark = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {  // Reduced spacing between label and table
            Text("API Keys")
                .font(.headline)
                .padding(.bottom, 5)  // Slightly smaller padding for tighter layout
            
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
                Rectangle()
                    .fill(Color.gray.opacity(0.5))
                    .frame(height: 0.5)  // Thinner separator
                    .edgesIgnoringSafeArea(.horizontal)  // Extend to edges
                apiKeyRow(
                    label: "OpenAI",
                    icon: "sparkles",
                    value: $openAiApiKey,
                    isEditing: $isEditingOpenAI,
                    editedValue: $editedOpenAiApiKey,
                    isHoveringCheckmark: $isHoveringCheckmark,
                    isHoveringXmark: $isHoveringXmark
                )
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.7), lineWidth: 1)  // Hardcoded border color
            )
            
            Spacer()
        }
        .padding()
        .frame(width: 400, height: 200)
    }
    
    @ViewBuilder
    private func apiKeyRow(label: String, icon: String, value: Binding<String>, isEditing: Binding<Bool>, editedValue: Binding<String>, isHoveringCheckmark: Binding<Bool>, isHoveringXmark: Binding<Bool>) -> some View {
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
}

