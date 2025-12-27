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

            ToolbarItem(id: "discovery", placement: .navigation, showsByDefault: true) {
                Button(action: {
                    Task { @MainActor in
                        Logger.info("🔍 Toolbar Discovery button tapped", category: .ui)
                        NotificationCenter.default.post(name: .showDiscovery, object: nil)
                        if !NSApp.sendAction(#selector(AppDelegate.showDiscoveryWindow), to: nil, from: nil),
                           let delegate = NSApplication.shared.delegate as? AppDelegate {
                            delegate.showDiscoveryWindow()
                        }
                    }
                }, label: {
                    Label("Discovery", systemImage: "magnifyingglass.circle")
                        .font(.system(size: 14, weight: .light))
                })
                .buttonStyle(.automatic)
                .help("Open Discovery")
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
                    Label("Resume", systemImage: "doc.badge.plus")
                        .font(.system(size: 14, weight: .light))
                })
                .buttonStyle(.automatic)
                .help("Create resume for selected listing")
                .disabled(jobAppStore.selectedApp == nil)
            }

            ToolbarItem(id: "coverLetter", placement: .secondaryAction, showsByDefault: true) {
                CoverLetterGenerateButton()
            }

            ToolbarItem(id: "optimizeResume", placement: .secondaryAction, showsByDefault: true) {
                Button(action: {
                    sheets.showResumeReview = true
                }, label: {
                    Label("Optimize", systemImage: "wand.and.stars")
                        .font(.system(size: 14, weight: .light))
                })
                .buttonStyle(.automatic)
                .help("Optimize resume (reorder skills, fix overflow, assess quality)")
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
                    switch selectedTab {
                    case .resume:
                        sheets.showResumeInspector.toggle()
                    case .coverLetter:
                        sheets.showCoverLetterInspector.toggle()
                    default:
                        break
                    }
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                        .overlay(alignment: .topTrailing) {
                            if selectedTab == .resume, let resumeCount = jobAppStore.selectedApp?.resumes.count, resumeCount > 1 {
                                Text("\(resumeCount)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.accentColor, in: Capsule())
                                    .offset(x: 8, y: -6)
                            }
                        }
                }
                .disabled(selectedTab != .resume && selectedTab != .coverLetter)
                .help(selectedTab == .resume ? "Toggle Resume Inspector" :
                      selectedTab == .coverLetter ? "Toggle Cover Letter Inspector" : "Inspector")
            }

            ToolbarItem(id: "knowledgeCards", placement: .primaryAction, showsByDefault: false) {
                Button(action: {
                    sheets.showKnowledgeCardsBrowser = true
                }, label: {
                    Label("Knowledge", systemImage: "brain.head.profile")
                        .font(.system(size: 14, weight: .light))
                })
                .buttonStyle(.automatic)
                .help("Browse Knowledge Cards")
            }

            ToolbarItem(id: "settings", placement: .primaryAction, showsByDefault: false) {
                Button("Settings", systemImage: "gear") {
                    NotificationCenter.default.post(name: .showSettings, object: nil)
                }
                .help("Open Settings")
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
