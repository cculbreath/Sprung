import SwiftUI

struct OpenRouterModelSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    
    @State private var searchText = ""
    @State private var selectedCapability: ModelCapability?
    @State private var showOnlySelected = false
    
    private var openRouterService: OpenRouterService {
        appState.openRouterService
    }
    
    private var filteredModels: [OpenRouterModel] {
        var models = openRouterService.availableModels
        
        // Filter by capability if selected
        if let capability = selectedCapability {
            models = openRouterService.getModelsWithCapability(capability)
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            models = models.filter { model in
                model.displayName.localizedCaseInsensitiveContains(searchText) ||
                model.id.localizedCaseInsensitiveContains(searchText) ||
                model.providerName.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Filter by selection status if requested
        if showOnlySelected {
            models = models.filter { appState.selectedOpenRouterModels.contains($0.id) }
        }
        
        return models
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with controls
                VStack(spacing: 12) {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search models...", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
                    
                    // Filter controls
                    HStack {
                        // Capability filter
                        Menu {
                            Button("All Models") {
                                selectedCapability = nil
                            }
                            
                            Divider()
                            
                            ForEach(ModelCapability.allCases, id: \.self) { capability in
                                Button {
                                    selectedCapability = capability
                                } label: {
                                    HStack {
                                        Image(systemName: capability.icon)
                                        Text(capability.displayName)
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: selectedCapability?.icon ?? "line.3.horizontal.decrease.circle")
                                Text(selectedCapability?.displayName ?? "All Capabilities")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(6)
                        }
                        
                        Spacer()
                        
                        // Show only selected toggle
                        Toggle("Selected Only", isOn: $showOnlySelected)
                            .toggleStyle(.switch)
                    }
                    
                    // Selection summary
                    HStack {
                        Text("\(filteredModels.count) models")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("\(appState.selectedOpenRouterModels.count) selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button("Select All") {
                            for model in filteredModels {
                                appState.selectedOpenRouterModels.insert(model.id)
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        
                        Button("Select None") {
                            for model in filteredModels {
                                appState.selectedOpenRouterModels.remove(model.id)
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
                .padding()
                .background(Color(.windowBackgroundColor))
                
                Divider()
                
                // Models list
                if filteredModels.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        
                        Text("No models found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Try adjusting your search or filter criteria")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.controlBackgroundColor).opacity(0.5))
                } else {
                    List {
                        ForEach(filteredModels) { model in
                            OpenRouterModelRow(
                                model: model,
                                isSelected: appState.selectedOpenRouterModels.contains(model.id)
                            ) { isSelected in
                                if isSelected {
                                    appState.selectedOpenRouterModels.insert(model.id)
                                } else {
                                    appState.selectedOpenRouterModels.remove(model.id)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Choose Models")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 800, height: 600)
    }
}

struct OpenRouterModelRow: View {
    let model: OpenRouterModel
    let isSelected: Bool
    let onToggle: (Bool) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Selection checkbox
            Button {
                onToggle(!isSelected)
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .font(.title2)
            }
            .buttonStyle(.plain)
            
            // Model info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(model.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(model.costDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(model.id)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                if let description = model.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
                
                // Capabilities
                HStack(spacing: 8) {
                    if model.supportsStructuredOutput {
                        CapabilityTag(icon: "list.bullet.rectangle", text: "Structured")
                    }
                    
                    if model.supportsImages {
                        CapabilityTag(icon: "eye", text: "Vision")
                    }
                    
                    if model.supportsReasoning {
                        CapabilityTag(icon: "brain", text: "Reasoning")
                    }
                    
                    Spacer()
                    
                    Text(model.providerName)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(4)
                }
                .padding(.top, 4)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle(!isSelected)
        }
    }
}

struct CapabilityTag: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.accentColor.opacity(0.1))
        .foregroundColor(.accentColor)
        .cornerRadius(4)
    }
}

#Preview {
    OpenRouterModelSelectionSheet()
        .environment(AppState())
}