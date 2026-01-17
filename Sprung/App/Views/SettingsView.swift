// Sprung/App/Views/SettingsView.swift
import SwiftUI
import SwiftData

enum SettingsCategory: String, CaseIterable, Identifiable {
    case apiKeys = "API Keys"
    case models = "Models"
    case resume = "Resume & Cover Letter"
    case onboarding = "Onboarding"
    case discovery = "Job Discovery"
    case voice = "Voice & Audio"
    case debugging = "Debugging"
    case reset = "Reset"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .apiKeys: return "key.fill"
        case .models: return "cpu"
        case .resume: return "doc.text.fill"
        case .onboarding: return "wand.and.stars"
        case .discovery: return "briefcase.fill"
        case .voice: return "speaker.wave.2.fill"
        case .debugging: return "ladybug.fill"
        case .reset: return "arrow.counterclockwise"
        }
    }
}

struct SettingsView: View {
    @Environment(DiscoveryCoordinator.self) private var searchOpsCoordinator
    @State private var selectedCategory: SettingsCategory? = .apiKeys
    @State private var showSetupWizard = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .frame(minWidth: 820, idealWidth: 900, maxWidth: 1100,
               minHeight: 500, idealHeight: 650, maxHeight: .infinity)
        .sheet(isPresented: $showSetupWizard) {
            SetupWizardView {
                showSetupWizard = false
            }
        }
    }

    private var sidebar: some View {
        List(selection: $selectedCategory) {
            ForEach(SettingsCategory.allCases) { category in
                NavigationLink(value: category) {
                    Label {
                        Text(category.rawValue)
                    } icon: {
                        Image(systemName: category.systemImage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180, idealWidth: 200)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedCategory {
        case .apiKeys:
            apiKeysDetail
        case .models:
            ModelsSettingsView()
        case .resume:
            ResumeSettingsSection()
        case .onboarding:
            OnboardingProcessingSettingsView()
        case .discovery:
            discoveryDetail
        case .voice:
            voiceDetail
        case .debugging:
            debuggingDetail
        case .reset:
            ResetSettingsSection()
        case nil:
            ContentUnavailableView("Select a Category", systemImage: "gearshape", description: Text("Choose a settings category from the sidebar."))
        }
    }

    private var apiKeysDetail: some View {
        Form {
            Section {
                APIKeysSettingsView()
                Button("Run Setup Wizard…") {
                    showSetupWizard = true
                }
                .buttonStyle(.bordered)
            } header: {
                SettingsSectionHeader(title: "API Credentials", systemImage: "key.fill")
            }
        }
        .formStyle(.grouped)
    }

    private var discoveryDetail: some View {
        Form {
            DiscoverySettingsSection(coordinator: searchOpsCoordinator)
        }
        .formStyle(.grouped)
    }

    private var voiceDetail: some View {
        Form {
            Section {
                TextToSpeechSettingsView()
            } header: {
                SettingsSectionHeader(title: "Text-to-Speech", systemImage: "speaker.wave.2.fill")
            }
        }
        .formStyle(.grouped)
    }

    private var debuggingDetail: some View {
        Form {
            Section {
                DebugSettingsView()
            } header: {
                SettingsSectionHeader(title: "Developer Options", systemImage: "ladybug.fill")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Section Header
struct SettingsSectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.subheadline)
        .fontWeight(.medium)
        .foregroundStyle(.secondary)
    }
}
