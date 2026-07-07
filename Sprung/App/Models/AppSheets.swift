//
//  AppSheets.swift
//  Sprung
//
import Foundation
import SwiftUI
/// Centralized sheet and UI state management for the main app window
/// Replaces individual Bool bindings with a single organized struct
struct AppSheets {
    var showApplicationReview = false
    var showResumeReview = false
    var showChooseBestCoverLetter = false
    var showMultiModelChooseBest = false
    var showBatchCoverLetter = false
    var showNewJobApp = false
    var showCreateResume = false
    // UI state that was previously in ResumeButtons
    var showCoverLetterInspector = false
    // Job capture from URL scheme (sprung://capture-job?url=...)
    var capturedJobURL: String?
}
// MARK: - Sheet Presentation ViewModifier
struct AppSheetsModifier: ViewModifier {
    @Binding var sheets: AppSheets
    @Environment(JobAppStore.self) private var jobAppStore
    @Environment(ResStore.self) private var resStore
    @Environment(CoverLetterStore.self) private var coverLetterStore
    @Environment(EnabledLLMStore.self) private var enabledLLMStore
    @Environment(AppState.self) private var appState
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $sheets.showNewJobApp, onDismiss: {
                // Clear captured URL when sheet closes
                sheets.capturedJobURL = nil
            }) {
                NewAppSheetView(
                    isPresented: $sheets.showNewJobApp,
                    initialURL: sheets.capturedJobURL
                )
                .environment(jobAppStore)
                .id(sheets.capturedJobURL ?? "default")
            }
            .onReceive(NotificationCenter.default.publisher(for: .captureJobFromURL)) { notification in
                if let urlString = notification.userInfo?["url"] as? String {
                    Logger.info("📥 [AppSheets] Received job capture URL: \(urlString)", category: .ui)
                    // The sheet receives the URL via initialURL (the .id above
                    // remounts it per captured URL), so no relay is needed here — this
                    // subscriber is the single delivery point. AppDelegate.CaptureURLBuffer
                    // buffers any URL that arrives before UnifiedAppLayout (this modifier's
                    // host) has mounted and this onReceive has subscribed, then delivers it
                    // via the same .captureJobFromURL post once the ready-signal fires.
                    sheets.capturedJobURL = urlString
                    sheets.showNewJobApp = true
                }
            }
            .sheet(isPresented: $sheets.showCreateResume) {
                if let selApp = jobAppStore.selectedApp {
                    CreateResumeView(
                        onCreateResume: { template in
                            try resStore.create(jobApp: selApp, template: template)
                        }
                    )
                    .padding()
                } else {
                    VStack(spacing: 12) {
                        Text("Select a job application first")
                            .font(.headline)
                        Text("Create Resume is scoped to a specific job application.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Close") {
                            sheets.showCreateResume = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(minWidth: 420, minHeight: 220)
                    .padding()
                }
            }
            .sheet(isPresented: $sheets.showResumeReview) {
                if let selectedResume = jobAppStore.selectedApp?.selectedRes {
                    ResumeReviewSheet(selectedResume: .constant(selectedResume))
                }
            }
            .sheet(isPresented: $sheets.showMultiModelChooseBest) {
                if jobAppStore.selectedApp != nil,
                   let currentCoverLetter = coverLetterStore.cL {
                    MultiModelChooseBestCoverLetterSheet(coverLetter: .constant(currentCoverLetter))
                }
            }
            .sheet(isPresented: $sheets.showApplicationReview) {
                // The review runs resume-only; a generated cover letter is optional.
                // Present a helpful empty state (never a blank sheet) when there is no
                // selected job application or no resume to review.
                if let selApp = jobAppStore.selectedApp,
                   let currentResume = selApp.selectedRes {
                    ApplicationReviewSheet(
                        jobApp: selApp,
                        resume: currentResume,
                        availableCoverLetters: selApp.coverLetters.filter { $0.generated }.sorted { $0.moddedDate > $1.moddedDate }
                    )
                } else {
                    VStack(spacing: 12) {
                        Text("Select a job application with a résumé first")
                            .font(.headline)
                        Text("The application review analyzes a résumé (and optionally a cover letter) for a specific job application.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Close") {
                            sheets.showApplicationReview = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(minWidth: 420, minHeight: 220)
                    .padding()
                }
            }
            .sheet(isPresented: $sheets.showBatchCoverLetter) {
                BatchCoverLetterView()
                    .environment(appState)
                    .environment(jobAppStore)
                    .environment(coverLetterStore)
                    .environment(enabledLLMStore)
            }
        // Setup wizard is presented by UnifiedAppLayout (the .showSetupWizard
        // observer that also owns hasCompletedSetupWizard) — not here.
    }
}

// MARK: - Helper View Extension
extension View {
    func appSheets(sheets: Binding<AppSheets>) -> some View {
        self.modifier(AppSheetsModifier(sheets: sheets))
    }
}
