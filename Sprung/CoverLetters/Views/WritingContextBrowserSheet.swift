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
        CoverRefBrowserOverlay(
            isPresented: $isPresented,
            cards: .init(
                get: { allCoverRefs },
                set: { _ in }
            ),
            coverRefStore: coverRefStore,
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
        .frame(minWidth: 940, minHeight: 640)
    }
}

