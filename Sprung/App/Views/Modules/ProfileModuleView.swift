//
//  ProfileModuleView.swift
//  Sprung
//
//  Applicant Profile module wrapper.
//

import SwiftUI

/// Profile module - wraps existing ApplicantProfileView for embedded use
struct ProfileModuleView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Module header
            ModuleHeader(
                title: "Profile",
                subtitle: "Manage your contact information and professional details"
            )

            // Embedded applicant profile editor
            ApplicantProfileView()
        }
    }
}
