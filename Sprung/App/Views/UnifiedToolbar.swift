// Sprung/App/Views/UnifiedToolbar.swift
import SwiftUI
import AppKit

/// Unified toolbar with macOS-idiomatic design
/// Default buttons focus on core workflow; additional buttons available via Customize Toolbar
@ToolbarContentBuilder
func buildUnifiedToolbar(
    selectedTab: Binding<TabList>,
    listingButtons: Binding<SaveButtons>,
    refresh: Binding<Bool>,
    sheets: Binding<AppSheets>,
    clarifyingQuestions: Binding<[ClarifyingQuestion]>,
    showNewAppSheet: Binding<Bool>
) -> some CustomizableToolbarContent {
    UnifiedToolbar(
        selectedTab: selectedTab,
        listingButtons: listingButtons,
        refresh: refresh,
        sheets: sheets,
        clarifyingQuestions: clarifyingQuestions,
        showNewAppSheet: showNewAppSheet
    )
}

struct UnifiedToolbar: CustomizableToolbarContent {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore

    @Binding var selectedTab: TabList
    @Binding var listingButtons: SaveButtons
    @Binding var refresh: Bool
    @Binding var sheets: AppSheets
    @Binding var clarifyingQuestions: [ClarifyingQuestion]
    @Binding var showNewAppSheet: Bool

    var body: some CustomizableToolbarContent {
        Group {
            navigationButtonsGroup
            mainButtonsGroup
            inspectorButtonGroup
        }
    }

    // MARK: - Navigation Buttons (4 items)

    private var navigationButtonsGroup: some CustomizableToolbarContent {
        Group {
            ToolbarItem(id: "newListing", placement: .navigation, showsByDefault: true) {
                Button(action: {
                    showNewAppSheet = true
                }, label: {
                    Label("New Listing", systemImage: "plus.rectangle.on.folder")
                        .font(.system(size: 14, weight: .light))
                })
                .buttonStyle(.automatic)
                .help("Create new job listing")
            }

            ToolbarItem(id: "templateEditor", placement: .navigation, showsByDefault: true) {
                Button(action: {
                    Task { @MainActor in
                        if !NSApp.sendAction(#selector(AppDelegate.showTemplateEditorWindow), to: nil, from: nil),
                           let delegate = NSApplication.shared.delegate as? AppDelegate {
                            delegate.showTemplateEditorWindow()
                        }
                    }
                }, label: {
                    Label("Templates", systemImage: "compass.drawing")
                        .font(.system(size: 14, weight: .light))
                })
                .buttonStyle(.automatic)
                .help("Open Template Editor")
            }

            ToolbarItem(id: "bestJob", placement: .navigation, showsByDefault: false) {
                BestJobButton()
            }

            ToolbarItem(id: "onboardingInterview", placement: .navigation, showsByDefault: false) {
                Button(action: {
                    Task { @MainActor in
                        Logger.info("🎙️ Toolbar interview button tapped", category: .ui)
                        NotificationCenter.default.post(name: .startOnboardingInterview, object: nil)
                        if !NSApp.sendAction(#selector(AppDelegate.showOnboardingInterviewWindow), to: nil, from: nil),
                           let delegate = NSApplication.shared.delegate as? AppDelegate {
                            delegate.showOnboardingInterviewWindow()
                        }
                    }
                }, label: {
                    Label("Onboarding", systemImage: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 14, weight: .light))
                })
                .buttonStyle(.automatic)
                .help("Launch onboarding interview")
            }
        }
    }

    // MARK: - Main Buttons (4 items)

    private var mainButtonsGroup: some CustomizableToolbarContent {
        Group {
            ToolbarItem(id: "createResume", placement: .secondaryAction, showsByDefault: true) {
                Button(action: {
                    sheets.showCreateResume = true
                }, label: {
                    Label("Create Resume", image: "custom.resume.new")
                        .font(.system(size: 14, weight: .light))
                })
                .buttonStyle(.automatic)
                .help("Create resume for selected listing")
                .disabled(jobAppStore.selectedApp == nil)
            }

            ToolbarItem(id: "coverLetter", placement: .secondaryAction, showsByDefault: true) {
                CoverLetterGenerateButton()
            }

            ToolbarItem(id: "experienceEditorMain", placement: .secondaryAction, showsByDefault: true) {
                Button(action: {
                    Task { @MainActor in
                        if !NSApp.sendAction(#selector(AppDelegate.showExperienceEditorWindow), to: nil, from: nil),
                           let delegate = NSApplication.shared.delegate as? AppDelegate {
                            delegate.showExperienceEditorWindow()
                        }
                    }
                }, label: {
                    Label("Experience", systemImage: "building.columns")
                        .font(.system(size: 14, weight: .light))
                })
                .buttonStyle(.automatic)
                .help("Open Experience Editor")
            }

            ToolbarItem(id: "polishResume", placement: .secondaryAction, showsByDefault: false) {
                Button(action: {
                    NotificationCenter.default.post(name: .polishResume, object: nil)
                }, label: {
                    Label("Polish Resume", systemImage: "sparkles")
                        .font(.system(size: 14, weight: .light))
                })
                .buttonStyle(.automatic)
                .help("Polish resume with AI revision agent")
                .disabled(jobAppStore.selectedApp?.selectedRes == nil)
            }

            ToolbarItem(id: "analyze", placement: .secondaryAction, showsByDefault: true) {
                Button(action: {
                    sheets.showApplicationReview = true
                }, label: {
                    Label("Analyze", systemImage: "checkmark.seal")
                        .font(.system(size: 14, weight: .light))
                })
                .buttonStyle(.automatic)
                .help("Analyze complete application")
                .disabled(jobAppStore.selectedApp?.selectedRes == nil ||
                          jobAppStore.selectedApp?.selectedCover == nil ||
                          jobAppStore.selectedApp?.selectedCover?.generated != true)
            }
        }
    }

    // MARK: - Inspector Buttons (5 items)

    private var inspectorButtonGroup: some CustomizableToolbarContent {
        Group {
            ToolbarItem(id: "inspector", placement: .primaryAction, showsByDefault: true) {
                Button {
                    if selectedTab == .coverLetter {
                        sheets.showCoverLetterInspector.toggle()
                    }
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .disabled(selectedTab != .coverLetter)
                .help(selectedTab == .coverLetter ? "Toggle Cover Letter Inspector" : "Inspector")
            }

            ToolbarItem(id: "settings", placement: .primaryAction, showsByDefault: false) {
                Button("Settings", systemImage: "gear") {
                    Task { @MainActor in
                        if !NSApp.sendAction(#selector(AppDelegate.showSettingsWindow), to: nil, from: nil),
                           let delegate = NSApplication.shared.delegate as? AppDelegate {
                            delegate.showSettingsWindow()
                        }
                    }
                }
                .help("Open Settings")
            }

            ToolbarItem(id: "templateEditorSecondary", placement: .primaryAction, showsByDefault: false) {
                Button("Templates", systemImage: "compass.drawing") {
                    Task { @MainActor in
                        if !NSApp.sendAction(#selector(AppDelegate.showTemplateEditorWindow), to: nil, from: nil),
                           let delegate = NSApplication.shared.delegate as? AppDelegate {
                            delegate.showTemplateEditorWindow()
                        }
                    }
                }
                .help("Open Template Editor")
            }

            ToolbarItem(id: "experienceEditor", placement: .primaryAction, showsByDefault: false) {
                Button("Experience", systemImage: "building.columns") {
                    Task { @MainActor in
                        if !NSApp.sendAction(#selector(AppDelegate.showExperienceEditorWindow), to: nil, from: nil),
                           let delegate = NSApplication.shared.delegate as? AppDelegate {
                            delegate.showExperienceEditorWindow()
                        }
                    }
                }
                .help("Open Experience Editor")
            }

            ToolbarItem(id: "applicantProfile", placement: .primaryAction, showsByDefault: false) {
                Button("Profile", systemImage: "person.text.rectangle") {
                    Task { @MainActor in
                        if !NSApp.sendAction(#selector(AppDelegate.showApplicantProfileWindow), to: nil, from: nil),
                           let delegate = NSApplication.shared.delegate as? AppDelegate {
                            delegate.showApplicantProfileWindow()
                        }
                    }
                }
                .help("Open Applicant Profile")
            }

            ToolbarItem(id: "ttsReadAloud", placement: .primaryAction, showsByDefault: false) {
                Button("Read Aloud", systemImage: "speaker.wave.2") {
                    NotificationCenter.default.post(name: .triggerTTSButton, object: nil)
                }
                .help("Toggle text-to-speech playback")
            }

            ToolbarItem(id: "separator", placement: .primaryAction, showsByDefault: false) {
                Divider()
            }
        }
    }
}
