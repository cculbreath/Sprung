//
//  CoverLetterInspectorView.swift
//  PhysCloudResume
//
//  Created on 6/5/2025.
//  Unified inspector view for cover letter sources and revisions

import SwiftUI

struct CoverLetterInspectorView: View {
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    @Environment(AppState.self) private var appState: AppState
    
    @Binding var isEditing: Bool
    
    var body: some View {
        CoverLetterMetadataView(isEditing: $isEditing)
            .frame(minWidth: 250, idealWidth: 300, maxWidth: 350)
    }
}