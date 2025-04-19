import SwiftUI
import UniformTypeIdentifiers

struct DatabaseBackupView: View {
    @State private var showRestoreWarning = false
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Database Management")
                .font(.title2)
                .bold()

            VStack(spacing: 12) {
                backupButton
                restoreButton
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )

            Spacer()
        }
        .padding()
        .frame(minWidth: 300, minHeight: 200)
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .alert("Confirm Restore", isPresented: $showRestoreWarning) {
            Button("Cancel", role: .cancel) {}
            Button("Restore", role: .destructive) {
                presentOpenPanel()
            }
        } message: {
            Text("This will overwrite your current database. Are you sure you want to proceed?")
        }
    }

    private var backupButton: some View {
        Button {
            DatabaseBackupManager.backupDatabase()
            showAlert(title: "Success", message: "Database backup saved to Downloads folder")
        } label: {
            HStack {
                Image(systemName: "arrow.down.doc.fill")
                Text("Backup Database")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private var restoreButton: some View {
        Button {
            showRestoreWarning = true
        } label: {
            HStack {
                Image(systemName: "arrow.up.doc.fill")
                Text("Restore Database")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.red.opacity(0.1))
            .foregroundColor(.red)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "Select Backup File"
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [.init(filenameExtension: "store")!]
        } else {
            panel.allowedFileTypes = ["store"]
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            DatabaseBackupManager.restoreDatabase(from: url)
            showAlert(title: "Success", message: "Database restored successfully")
        }
    }

    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}
