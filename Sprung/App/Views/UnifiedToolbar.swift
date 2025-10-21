// Sprung/App/Views/UnifiedToolbar.swift
import SwiftUI
import AppKit


/// Unified toolbar with all buttons visible, using disabled state instead of hiding
@ToolbarContentBuilder
func buildUnifiedToolbar(
    selectedTab: Binding<TabList>,
    listingButtons: Binding<SaveButtons>,
    refresh: Binding<Bool>,
    sheets: Binding<AppSheets>,
    clarifyingQuestions: Binding<[ClarifyingQuestion]>,
    showNewAppSheet: Binding<Bool>,
    showSlidingList: Binding<Bool>
) -> some CustomizableToolbarContent {
    UnifiedToolbar(
        selectedTab: selectedTab,
        listingButtons: listingButtons,
        refresh: refresh,
        sheets: sheets,
        clarifyingQuestions: clarifyingQuestions,
        showNewAppSheet: showNewAppSheet,
        showSlidingList: showSlidingList
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
    @Binding var showSlidingList: Bool

    var body: some CustomizableToolbarContent {
        Group {
            navigationButtonsGroup
            mainButtonsGroup
            inspectorButtonGroup
        }
    }
    
    private var navigationButtonsGroup: some CustomizableToolbarContent {
        Group {
            ToolbarItem(id: "newJobApp", placement: .navigation, showsByDefault: true) {
                Button(action: {
                    showNewAppSheet = true
                }){
                    Label("Job App", systemImage:"note.text.badge.plus" ).font(.system(size: 14, weight: .light))
                }
                .buttonStyle( .automatic )
                .help("Create New Job Application")
            }

            ToolbarItem(id: "bestJob", placement: .navigation, showsByDefault: true) {
                BestJobButton()
            }

            ToolbarItem(id: "applicantProfile", placement: .navigation, showsByDefault: true) {
                Button(action: {
                    Task { @MainActor in
                        NotificationCenter.default.post(name: .showApplicantProfile, object: nil)
                        if !NSApp.sendAction(#selector(AppDelegate.showApplicantProfileWindow), to: nil, from: nil),
                           let delegate = NSApplication.shared.delegate as? AppDelegate {
                            delegate.showApplicantProfileWindow()
                        }
                    }
                }) {
                    Label("Profile", systemImage: "person")
                        .font(.system(size: 14, weight: .light))
                }
                .buttonStyle(.automatic)
                .help("Open Applicant Profile")
            }
        }}

    private var mainButtonsGroup: some CustomizableToolbarContent {
        Group {
            ToolbarItem(id: "startOnboardingInterview", placement: .secondaryAction, showsByDefault: true) {
                Button(action: {
                    Task { @MainActor in
                        Logger.info("🎙️ Toolbar interview button tapped", category: .ui)
                        NotificationCenter.default.post(name: .startOnboardingInterview, object: nil)
                        if !NSApp.sendAction(#selector(AppDelegate.showOnboardingInterviewWindow), to: nil, from: nil),
                           let delegate = NSApplication.shared.delegate as? AppDelegate {
                            Logger.debug("🔁 Toolbar fallback to AppDelegate direct invocation", category: .ui)
                            delegate.showOnboardingInterviewWindow()
                        }
                    }
                }) {
                    Label("Interview", systemImage: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 14, weight: .light))
                }
                .buttonStyle(.automatic)
                .help("Launch onboarding interview")
            }

            ToolbarItem(id: "coverLetter", placement: .secondaryAction, showsByDefault: true) {
                CoverLetterGenerateButton()
            }

            ToolbarItem(id: "analyze", placement: .secondaryAction, showsByDefault: true) {
                Button(action: {
                    sheets.showApplicationReview = true
                }) {
                    Label("Analyze", systemImage: "mail.and.text.magnifyingglass")
                        .font(.system(size: 14, weight: .light))
                       
                }
                .buttonStyle( .automatic )
                .help("Review Application")
                .disabled(jobAppStore.selectedApp?.selectedRes == nil ||
                          jobAppStore.selectedApp?.selectedCover == nil ||
                          jobAppStore.selectedApp?.selectedCover?.generated != true)
            }
        }
    }

    private var inspectorButtonGroup: some CustomizableToolbarContent {
        Group {
            ToolbarItem(id: "templateEditor", placement: .primaryAction, showsByDefault: true) {
                Button(action: {
                    Task { @MainActor in
                        NotificationCenter.default.post(name: .showTemplateEditor, object: nil)
                        NSApp.sendAction(#selector(AppDelegate.showTemplateEditorWindow), to: nil, from: nil)
                    }
                }) {
                    Label("Templates", systemImage: "richtext.page")
                        .font(.system(size: 14, weight: .light))
                }
                .buttonStyle(.automatic)
                .help("Open Template Editor")
            }

            ToolbarItem(id: "experienceEditor", placement: .primaryAction, showsByDefault: true) {
                Button(action: {
                    Task { @MainActor in
                        NotificationCenter.default.post(name: .showExperienceEditor, object: nil)
                        NSApp.sendAction(#selector(AppDelegate.showExperienceEditorWindow), to: nil, from: nil)
                    }
                }) {
                    Label("Experience", systemImage: "briefcase")
                        .font(.system(size: 14, weight: .light))
                }
                .buttonStyle(.automatic)
                .help("Open Experience Editor")
            }

            ToolbarItem(id: "showSources", placement: .primaryAction, showsByDefault: true) {
                Button(action: {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0.2)) {
                        showSlidingList.toggle()
                    }
                }) {
                    Label("Sources", systemImage: "newspaper")
                        .font(.system(size: 14, weight: .light))
                }
                .buttonStyle(.automatic)
                .help("Show Sources")
                .disabled(jobAppStore.selectedApp == nil)
            }

            ToolbarItem(id: "inspector", placement: .primaryAction, showsByDefault: true) {
                Button("Inspector", systemImage: "sidebar.right") {
                    switch selectedTab {
                    case .resume:
                        sheets.showResumeInspector.toggle()
                    case .coverLetter:
                        sheets.showCoverLetterInspector.toggle()
                    default:
                        break
                    }
                }
                .disabled(selectedTab != .resume && selectedTab != .coverLetter)
                .help(selectedTab == .resume ? "Show Resume Inspector" : 
                      selectedTab == .coverLetter ? "Show Cover Letter Inspector" : "Inspector")
            }
            
            // Hidden by default but customizable toolbar items
            ToolbarItem(id: "settings", placement: .primaryAction, showsByDefault: false) {
                Button("Settings", systemImage: "gear") {
                    NotificationCenter.default.post(name: .showSettings, object: nil)
                }
                .help("Open Settings")
            }
            
            // Legacy toolbar identifiers retained for existing customizations
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
