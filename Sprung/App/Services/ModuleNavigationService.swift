//
//  ModuleNavigationService.swift
//  Sprung
//
//  Manages module navigation state for the unified app layout.
//

import Foundation
import SwiftUI

/// Manages module navigation state
@Observable
@MainActor
final class ModuleNavigationService {

    // MARK: - Storage Keys

    private enum StorageKeys {
        static let selectedModule = "selectedModule"
        static let iconBarExpanded = "iconBarExpanded"
    }

    // MARK: - State

    /// Currently selected module
    var selectedModule: AppModule {
        didSet {
            UserDefaults.standard.set(selectedModule.rawValue, forKey: StorageKeys.selectedModule)
            Logger.debug("Module changed to: \(selectedModule.label)", category: .ui)
        }
    }

    /// Whether the icon bar is expanded to show labels
    var isIconBarExpanded: Bool {
        didSet {
            UserDefaults.standard.set(isIconBarExpanded, forKey: StorageKeys.iconBarExpanded)
        }
    }

    /// Track module visit history for back navigation (optional future feature)
    private var moduleHistory: [AppModule] = []
    private let maxHistorySize = 10

    // MARK: - Initialization

    init() {
        // Restore selected module from UserDefaults
        if let storedModule = UserDefaults.standard.string(forKey: StorageKeys.selectedModule),
           let module = AppModule(rawValue: storedModule) {
            self.selectedModule = module
        } else {
            self.selectedModule = .resumeEditor // Default to Resume Editor
        }

        // Restore icon bar expansion state
        self.isIconBarExpanded = UserDefaults.standard.bool(forKey: StorageKeys.iconBarExpanded)

        // Listen for navigation notifications from menus
        NotificationCenter.default.addObserver(
            forName: .navigateToModule,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let moduleString = notification.userInfo?["module"] as? String,
                  let module = AppModule(rawValue: moduleString) else { return }
            Task { @MainActor in
                self?.selectModule(module)
            }
        }

        Logger.debug("ModuleNavigationService initialized (module: \(selectedModule.label), expanded: \(isIconBarExpanded))", category: .appLifecycle)
    }

    // MARK: - Navigation

    /// Select a specific module
    func selectModule(_ module: AppModule) {
        guard module != selectedModule else { return }

        // Add current module to history before changing
        addToHistory(selectedModule)

        withAnimation(.easeInOut(duration: 0.2)) {
            selectedModule = module
        }
    }

    /// Select the previous module in the list
    func selectPreviousModule() {
        guard let currentIndex = AppModule.allCases.firstIndex(of: selectedModule),
              currentIndex > 0 else { return }
        selectModule(AppModule.allCases[currentIndex - 1])
    }

    /// Select the next module in the list
    func selectNextModule() {
        guard let currentIndex = AppModule.allCases.firstIndex(of: selectedModule),
              currentIndex < AppModule.allCases.count - 1 else { return }
        selectModule(AppModule.allCases[currentIndex + 1])
    }

    /// Go back to the previously selected module
    func goBack() {
        guard let previousModule = moduleHistory.popLast() else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedModule = previousModule
        }
    }

    /// Toggle icon bar expansion
    func toggleIconBarExpansion() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isIconBarExpanded.toggle()
        }
    }

    /// Expand the icon bar
    func expandIconBar() {
        guard !isIconBarExpanded else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            isIconBarExpanded = true
        }
    }

    /// Collapse the icon bar
    func collapseIconBar() {
        guard isIconBarExpanded else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            isIconBarExpanded = false
        }
    }

    // MARK: - History

    private func addToHistory(_ module: AppModule) {
        // Don't add duplicates consecutively
        if moduleHistory.last != module {
            moduleHistory.append(module)

            // Trim history if too long
            if moduleHistory.count > maxHistorySize {
                moduleHistory.removeFirst()
            }
        }
    }

    /// Whether back navigation is available
    var canGoBack: Bool {
        !moduleHistory.isEmpty
    }
}
