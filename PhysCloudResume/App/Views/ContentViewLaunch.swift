// PhysCloudResume/App/Views/ContentViewLaunch.swift

import AppKit
import SwiftUI

struct ContentViewLaunch: View {
    let deps: AppDependencies
    @Environment(AppEnvironment.self) private var appEnvironment

    @State private var restoreStatus: RestoreStatus?
    @State private var isRestoring = false

    var body: some View {
        ZStack {
            coreContent
                .disabled(appEnvironment.launchState.isReadOnly)
                .blur(radius: appEnvironment.launchState.isReadOnly ? 4 : 0)

            if case .readOnly(let message) = appEnvironment.launchState {
                LaunchStateOverlay(
                    message: message,
                    isRestoring: isRestoring,
                    status: restoreStatus,
                    restoreAction: restoreLatestBackup,
                    openBackupsAction: openBackupFolder
                )
                .padding()
                .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: appEnvironment.launchState)
    }

    private var coreContent: some View {
        ContentView()
            .environment(deps.appEnvironment)
            .environment(deps.appEnvironment.appState)
            .environment(deps.appEnvironment.openRouterService)
            .environment(deps.appEnvironment.coverLetterService)
            .environment(deps.debugSettingsStore)
            .environment(deps.jobAppStore)
            .environment(deps.resRefStore)
            .environment(deps.resModelStore)
            .environment(deps.resStore)
            .environment(deps.coverRefStore)
            .environment(deps.coverLetterStore)
            .environment(deps.enabledLLMStore)
            .environment(deps.dragInfo)
            .environment(deps.llmFacade)
            .environment(deps.llmService)
    }

    private func restoreLatestBackup() {
        guard !isRestoring else { return }
        isRestoring = true
        restoreStatus = nil

        Task {
            do {
                try SwiftDataBackupManager.restoreMostRecentBackup()
                await MainActor.run {
                    restoreStatus = .success("Latest backup restored. Quit and relaunch the app to load your data.")
                }
            } catch {
                await MainActor.run {
                    restoreStatus = .failure(error.localizedDescription)
                }
            }

            await MainActor.run {
                isRestoring = false
            }
        }
    }

    private func openBackupFolder() {
        guard let backupURL = backupRootURL() else {
            restoreStatus = .failure("Backup folder not found. A backup may not exist yet.")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([backupURL])
        restoreStatus = .success("Opened backup folder in Finder.")
    }

    private func backupRootURL() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let backupRoot = appSupport.appendingPathComponent("PhysCloudResume_Backups", isDirectory: true)
        if !FileManager.default.fileExists(atPath: backupRoot.path) {
            return nil
        }
        return backupRoot
    }
}

private enum RestoreStatus {
    case success(String)
    case failure(String)

    var message: String {
        switch self {
        case .success(let text), .failure(let text):
            return text
        }
    }

    var tint: Color {
        switch self {
        case .success:
            return .green
        case .failure:
            return .red
        }
    }
}

private struct LaunchStateOverlay: View {
    let message: String
    let isRestoring: Bool
    let status: RestoreStatus?
    let restoreAction: () -> Void
    let openBackupsAction: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Read-Only Mode")
                .font(.title2)
                .bold()

            Text(message)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let status {
                Text(status.message)
                    .font(.callout)
                    .foregroundColor(status.tint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if isRestoring {
                ProgressView()
                    .progressViewStyle(.circular)
            }

            VStack(alignment: .leading, spacing: 12) {
                Button("Restore Latest Backup", action: restoreAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(isRestoring)

                Button("Open Backup Folder", action: openBackupsAction)
                    .buttonStyle(.bordered)
                    .disabled(isRestoring)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("After restoring, quit and relaunch PhysCloudResume to reload your data.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .frame(maxWidth: 420)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(radius: 20)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(.separator.opacity(0.4))
        )
    }
}
