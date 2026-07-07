//
//  AppWindowView.swift
//  Sprung
//
//  Renamed from TabWrapperView to better reflect responsibility
//
import SwiftUI
import AppKit
struct AppWindowView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @State private var listingButtons: SaveButtons = .init(edit: false, save: false, cancel: false)
    @Binding var selectedTab: TabList
    @Binding var tabRefresh: Bool
    // Shared app-sheet state; presented once at the shell (UnifiedAppLayout's
    // AppSheetsModifier). This view only feeds bindings into its tab content.
    @Binding var sheets: AppSheets
    var body: some View {
        @Bindable var jobAppStore = jobAppStore
        mainContent
    }
    private var mainContent: some View {
        VStack {
            if jobAppStore.selectedApp != nil {
                tabView
            } else {
                // Show empty state when no job app is selected
                VStack {
                    Spacer()
                    Text("Select a job application from the sidebar to begin")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .id($tabRefresh.wrappedValue)
    }
    private var tabView: some View {
        VStack(spacing: 0) {
            tabPickerBar
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var tabPickerBar: some View {
        HStack {
            Spacer()
            Picker("", selection: $selectedTab) {
                ForEach(TabList.visibleCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .controlSize(.small)
            .font(.system(size: 11))
            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .listing:
            JobAppDetailView(tab: $selectedTab, buttons: $listingButtons)
        case .resume:
            ResumeSplitView(
                isWide: .constant(true),
                tab: $selectedTab,
                refresh: $tabRefresh,
                sheets: $sheets
            )
        case .coverLetter:
            CoverLetterView(showCoverLetterInspector: $sheets.showCoverLetterInspector)
        case .submitApp:
            ResumeExportView(selectedTab: $selectedTab)
        case .none:
            EmptyView()
        }
    }
}
struct SaveButtons {
    var edit: Bool = false
    var save: Bool = false
    var cancel: Bool = false
}
