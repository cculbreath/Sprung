//
//  ContactsModuleView.swift
//  Sprung
//
//  Contacts CRM module wrapper.
//

import SwiftUI

/// Contacts module - wraps existing ContactsView
struct ContactsModuleView: View {
    @Environment(DiscoveryCoordinator.self) private var coordinator

    var body: some View {
        VStack(spacing: 0) {
            // Module header
            ModuleHeader(
                title: "Contacts",
                subtitle: "Track relationships and log interactions — follow-ups surface as daily tasks"
            )

            // Existing ContactsView
            ContactsView(coordinator: coordinator)
        }
    }
}
