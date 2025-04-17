//  ContentViewLaunch.swift
//  Centralises creation of data stores and injects them into the SwiftUI
//  environment so that downstream views (e.g. ContentView) can simply fetch
//  them via `@Environment`.

import SwiftUI

struct ContentViewLaunch: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        // Initialise all stores once per scene.
        let resStore = ResStore(context: modelContext)
        let resRefStore = ResRefStore(context: modelContext)
        let coverRefStore = CoverRefStore(context: modelContext)
        let coverLetterStore = CoverLetterStore(context: modelContext, refStore: coverRefStore)
        let jobAppStore = JobAppStore(context: modelContext, resStore: resStore, coverLetterStore: coverLetterStore)
        let resModelStore = ResModelStore(context: modelContext, resStore: resStore)

        return ContentView()
            .environment(jobAppStore)
            .environment(resRefStore)
            .environment(resModelStore)
            .environment(resStore)
            .environment(coverRefStore)
            .environment(coverLetterStore)
    }
}
