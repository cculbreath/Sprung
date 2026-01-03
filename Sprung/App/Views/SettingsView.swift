// Sprung/App/Views/SettingsView.swift
import SwiftUI
import SwiftData

enum SettingsCategory: String, CaseIterable, Identifiable {
    case apiKeys = "API Keys"
    case resume = "Resume & Cover Letter"
    case onboarding = "Onboarding"
    case discovery = "Job Discovery"
    case voice = "Voice & Audio"
    case debugging = "Debugging"
    case dangerZone = "Danger Zone"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .apiKeys: return "key.fill"
        case .resume: return "doc.text.fill"
        case .onboarding: return "wand.and.stars"
        case .discovery: return "briefcase.fill"
        case .voice: return "speaker.wave.2.fill"
        case .debugging: return "ladybug.fill"
        case .dangerZone: return "exclamationmark.octagon.fill"
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
        .frame(minWidth: 720, idealWidth: 800, maxWidth: 1000,
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
                            .foregroundStyle(category == .dangerZone ? .red : .secondary)
                    }
                    .foregroundStyle(category == .dangerZone ? .red : .primary)
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
        case .resume:
            ResumeSettingsSection()
        case .onboarding:
            OnboardingModelSettingsView()
        case .discovery:
            discoveryDetail
        case .voice:
            voiceDetail
        case .debugging:
            debuggingDetail
        case .dangerZone:
            DangerZoneSettingsSection()
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
