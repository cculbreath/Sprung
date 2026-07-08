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
        // ApplicantProfileView owns its own L1 header (identity + Edit/Save/
        // Cancel actions slot) — no separate module header here.
        ApplicantProfileView()
            // ApplicantProfileView declares minHeight 750; publish it so the window
            // floor honors it and Profile can't be vertically clipped.
            .moduleMinContentSize(CGSize(width: 520, height: 750))
    }
}
