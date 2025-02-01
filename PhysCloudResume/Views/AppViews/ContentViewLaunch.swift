//
//  ContentViewLaunch.swift
//  PhysicsCloudResume
//
//  Created by Christopher Culbreath on 8/31/24.
//

import SwiftUI

struct ContentViewLaunch: View {
    @Environment(\.modelContext) private var modelContext
    var body: some View {
        ContentView(modelContext: modelContext)
    }
}
