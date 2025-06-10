// PhysCloudResume/App/Views/UnifiedToolbar.swift
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
    resumeReviseViewModel: ResumeReviseViewModel?,
    showNewAppSheet: Binding<Bool>,
    showSlidingList: Binding<Bool>
) -> some CustomizableToolbarContent {
    UnifiedToolbar(
        selectedTab: selectedTab,
        listingButtons: listingButtons,
        refresh: refresh,
        sheets: sheets,
        clarifyingQuestions: clarifyingQuestions,
        resumeReviseViewModel: resumeReviseViewModel,
        showNewAppSheet: showNewAppSheet,
        showSlidingList: showSlidingList
    )
}

struct UnifiedToolbar: CustomizableToolbarContent {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(AppState.self) private var appState: AppState
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore

    @Binding var selectedTab: TabList
    @Binding var listingButtons: SaveButtons
    @Binding var refresh: Bool
    @Binding var sheets: AppSheets
    @Binding var clarifyingQuestions: [ClarifyingQuestion]
    var resumeReviseViewModel: ResumeReviseViewModel?
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

                .help("Create New Job Application")
            }

            ToolbarItem(id: "bestJob", placement: .navigation, showsByDefault: true) {
                BestJobButton()
            }

            ToolbarItem(id: "showSources", placement: .navigation, showsByDefault: true) {
                Button(action: {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0.2)) {
                        showSlidingList.toggle()
                    }})
                {Label("Show Sources", systemImage: "newspaper").font(.system(size: 14, weight: .light))

                        .help("Show Sources")
                }
            }
        }}

    private var mainButtonsGroup: some CustomizableToolbarContent {
        Group {
            // Resume Operations
            ToolbarItem(id: "customize", placement: .secondaryAction, showsByDefault: true) {
                ResumeCustomizeButton(
                    selectedTab: $selectedTab,
                    resumeReviseViewModel: resumeReviseViewModel
                )
            }
            
            ToolbarItem(id: "clarifyCustomize", placement: .secondaryAction, showsByDefault: true) {
                ClarifyingQuestionsButton(
                    selectedTab: $selectedTab,
                    clarifyingQuestions: $clarifyingQuestions,
                    sheets: $sheets,
                    resumeReviseViewModel: resumeReviseViewModel
                )
            }
            
            ToolbarItem(id: "optimize", placement: .secondaryAction, showsByDefault: true) {
                Button(action: {
                    sheets.showResumeReview = true
                }) {
                    Label("Optimize", systemImage: "character.magnify")
                        .font(.system(size: 14, weight: .light))
                       
                }
                .buttonStyle(.automatic)
                .help("AI Resume Review")
                .disabled(jobAppStore.selectedApp?.selectedRes == nil)
            }
            
            // Cover Letter Operations
            ToolbarItem(id: "coverLetter", placement: .secondaryAction, showsByDefault: true) {
                CoverLetterGenerateButton()
            }
            
            ToolbarItem(id: "reviseLetter", placement: .secondaryAction, showsByDefault: true) {
                CoverLetterReviseButton()
            }
            
            ToolbarItem(id: "batchLetter", placement: .secondaryAction, showsByDefault: true) {
                Button(action: {
                    sheets.showBatchCoverLetter = true
                }){Label("Batch Letter", systemImage: "square.stack.3d.down.right").font(.system(size: 14, weight: .light))

                        .disabled(jobAppStore.selectedApp?.selectedRes == nil)
                    .help("Batch Cover Letter Operations")}
            }
            
            ToolbarItem(id: "committee", placement: .secondaryAction, showsByDefault: true) {
                Button(action: {
                    sheets.showMultiModelChooseBest = true
                }) {
                    Label("Committee", systemImage: "trophy")
                           .font(.system(size: 14, weight: .light))
                    }

                .font(.system(size: 14, weight: .light))
                .buttonStyle(.automatic)
                .help("Multi-model Choose Best Cover Letter")
                .disabled((jobAppStore.selectedApp?.coverLetters.filter { $0.generated }.count ?? 0) < 2)
            }
            
            // TTS button removed temporarily - causes duplicate ID crashes during toolbar customization
            
            ToolbarItem(id: "analyze", placement: .secondaryAction, showsByDefault: true) {
                Button(action: {
                    sheets.showApplicationReview = true
                }) {
                    Label("Analyze", systemImage: "mail.and.text.magnifyingglass")
                        .font(.system(size: 14, weight: .light))
                       
                }
                .buttonStyle(.automatic)
                .help("Review Application")
                .disabled(jobAppStore.selectedApp?.selectedRes == nil ||
                          jobAppStore.selectedApp?.selectedCover == nil ||
                          jobAppStore.selectedApp?.selectedCover?.generated != true)
            }
        }
    }
    
    private var inspectorButtonGroup: some CustomizableToolbarContent {
        Group {
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
            
            ToolbarItem(id: "applicantProfile", placement: .primaryAction, showsByDefault: false) {
                Button("Profile", systemImage: "person.crop.circle") {
                    NotificationCenter.default.post(name: .showApplicantProfile, object: nil)
                }
                .help("Open Applicant Profile")
            }
            
            ToolbarItem(id: "templateEditor", placement: .primaryAction, showsByDefault: false) {
                Button("Templates", systemImage: "doc.text") {
                    NotificationCenter.default.post(name: .showTemplateEditor, object: nil)
                }
                .help("Open Template Editor")
            }
            
            // Legacy placeholder items to prevent crashes for previously customized toolbars
            ToolbarItem(id: "tts", placement: .primaryAction, showsByDefault: false) {
                Button("TTS") {
                    // Legacy TTS button - functionality moved to menu
                }
                .disabled(true)
                .help("TTS functionality moved to Cover Letter menu")
            }
            
            ToolbarItem(id: "ttsReadAloud", placement: .primaryAction, showsByDefault: false) {
                Button("Read Aloud") {
                    // Legacy TTS button - functionality moved to menu
                }
                .disabled(true)
                .help("TTS functionality moved to Cover Letter menu")
            }
            
            ToolbarItem(id: "separator", placement: .primaryAction, showsByDefault: false) {
                Divider()
            }
        }
    }
}

