//
//  WritingContextBrowserSheet.swift
//  Sprung
//
//  A lightweight entry point for browsing and editing CoverRefs (writing samples + dossier/background facts).
//

import SwiftData
import SwiftUI

struct WritingContextBrowserSheet: View {
    @Environment(CoverRefStore.self) private var coverRefStore
    @Query(sort: \CoverRef.name) private var allCoverRefs: [CoverRef]
    @Binding var isPresented: Bool

    var body: some View {
        WritingSamplesBrowserTab(
            cards: .init(
                get: { allCoverRefs },
                set: { _ in }
            ),
            onCardUpdated: { _ in
                // SwiftData query auto-refreshes
            },
            onCardDeleted: { ref in
                coverRefStore.deleteCoverRef(ref)
            },
            onCardAdded: { ref in
                coverRefStore.addCoverRef(ref)
            }
        )
        .frame(width: 720, height: 680)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

