import SwiftUI

struct OpenRouterModelSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(EnabledLLMStore.self) private var enabledLLMStore
    
    @State private var searchText = ""
    @State private var selectedProvider: String?
    @State private var showOnlySelected = false
    @State private var isSearchCollapsed = true
    
    // Capability filters
    @State private var filterStructuredOutput = false
    @State private var filterVision = false
    @State private var filterReasoning = false
    @State private var filterTextOnly = false
    
    private var openRouterService: OpenRouterService {
        appState.openRouterService
    }
    
    private var availableProviders: [String] {
        let providers = Set(openRouterService.availableModels.map { $0.providerName })
        return Array(providers).sorted()
    }
    
    private var filteredModels: [OpenRouterModel] {
        var models = openRouterService.availableModels
        
        // Filter by provider if selected
        if let provider = selectedProvider {
            models = models.filter { $0.providerName == provider }
        }
        
        // Filter by capabilities
        if filterStructuredOutput {
            models = models.filter { $0.supportsStructuredOutput }
        }
        if filterVision {
            models = models.filter { $0.supportsImages }
        }
        if filterReasoning {
            models = models.filter { $0.supportsReasoning }
        }
        if filterTextOnly {
            models = models.filter { $0.isTextToText && !$0.supportsImages }
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
            models = models.filter { model in
                enabledLLMStore.enabledModelIds.contains(model.id)
            }
        }
        
        return models
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with controls
                VStack(spacing: 12) {
                    // Top row: Search and provider filter
                    HStack {
                        // Collapsible search
                        if !isSearchCollapsed {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                TextField("Search models...", text: $searchText)
                                    .textFieldStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(6)
                            .transition(.opacity)
                        }
                        
                        Button {
                            withAnimation {
                                isSearchCollapsed.toggle()
                                if isSearchCollapsed {
                                    searchText = ""
                                }
                            }
                        } label: {
                            Image(systemName: isSearchCollapsed ? "magnifyingglass" : "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                        
                        Spacer()
                        
                        // Provider filter
                        Menu {
                            Button("All Providers") {
                                selectedProvider = nil
                            }
                            
                            Divider()
                            
                            ForEach(availableProviders, id: \.self) { provider in
                                Button(provider) {
                                    selectedProvider = provider
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "building.2")
                                Text(selectedProvider ?? "All Providers")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(6)
                        }
                    }
                    
                    // Capability filters
                    HStack {
                        Toggle(isOn: $filterStructuredOutput) {
                            HStack(spacing: 4) {
                                Image(systemName: "list.bullet.rectangle")
                                Text("Structured")
                            }
                        }
                        .toggleStyle(.checkbox)
                        
                        Toggle(isOn: $filterVision) {
                            HStack(spacing: 4) {
                                Image(systemName: "eye")
                                Text("Vision")
                            }
                        }
                        .toggleStyle(.checkbox)
                        
                        Toggle(isOn: $filterReasoning) {
                            HStack(spacing: 4) {
                                Image(systemName: "brain")
                                Text("Reasoning")
                            }
                        }
                        .toggleStyle(.checkbox)
                        
                        Toggle(isOn: $filterTextOnly) {
                            HStack(spacing: 4) {
                                Image(systemName: "text.alignleft")
                                Text("Text Only")
                            }
                        }
                        .toggleStyle(.checkbox)
                        
                        Spacer()
                        
                        // Show only selected toggle
                        Toggle("Selected Only", isOn: $showOnlySelected)
                            .toggleStyle(.switch)
                    }
                    
                    // Selection summary and refresh
                    HStack {
                        Text("\(filteredModels.count) models")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        // Refresh button as circle arrow
                        Button {
                            Task {
                                await openRouterService.fetchModels()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .disabled(openRouterService.isLoading)
                        
                        Text("\(enabledLLMStore.enabledModelIds.count) selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button("Select All") {
                            for model in filteredModels {
                                enabledLLMStore.updateModelCapabilities(from: model)
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        
                        Button("Select None") {
                            for model in filteredModels {
                                enabledLLMStore.disableModel(id: model.id)
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
                                isSelected: enabledLLMStore.enabledModelIds.contains(model.id),
                                pricingThresholds: openRouterService.pricingThresholds
                            ) { isSelected in
                                if isSelected {
                                    enabledLLMStore.updateModelCapabilities(from: model)
                                } else {
                                    enabledLLMStore.disableModel(id: model.id)
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
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 900, height: 650)
        .onAppear {
            // Auto-populate models when opening
            if openRouterService.availableModels.isEmpty {
                Task {
                    await openRouterService.fetchModels()
                }
            }
        }
    }
}

struct OpenRouterModelRow: View {
    let model: OpenRouterModel
    let isSelected: Bool
    let pricingThresholds: [Double]
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
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(model.displayName)
                        .font(.headline)
                        .lineLimit(2)
                    
                    Spacer()
                    
                    // Cost level with warning
                    HStack(spacing: 4) {
                        if model.isHighCostModel {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                        }
                        
                        Text(model.costLevelDescription(using: pricingThresholds))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(model.costLevel(using: pricingThresholds) >= 4 ? .orange : .secondary)
                        
                        Text(model.costDescription)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Text(model.id)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                if let description = model.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                
                // Capabilities with lit/dim indicators
                HStack(spacing: 12) {
                    CapabilityIndicator(
                        icon: "list.bullet.rectangle", 
                        isSupported: model.supportsStructuredOutput
                    )
                    
                    CapabilityIndicator(
                        icon: "eye", 
                        isSupported: model.supportsImages
                    )
                    
                    CapabilityIndicator(
                        icon: "brain", 
                        isSupported: model.supportsReasoning
                    )
                    
                    CapabilityIndicator(
                        icon: "text.alignleft", 
                        isSupported: model.isTextToText
                    )
                    
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

struct CapabilityIndicator: View {
    let icon: String
    let isSupported: Bool
    
    var body: some View {
        Image(systemName: icon)
            .font(.caption)
            .foregroundColor(isSupported ? .accentColor : .secondary)
            .opacity(isSupported ? 1.0 : 0.3)
    }
}


#Preview {
    OpenRouterModelSelectionSheet()
        .environment(AppState())
}