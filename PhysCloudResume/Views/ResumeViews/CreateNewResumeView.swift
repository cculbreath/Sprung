//
//  CreateNewResumeView.swift
//  PhysicsCloudResume
//
//  Created by Christopher Culbreath on 8/18/24.
//

import SwiftData
import SwiftUI

struct CreateNewResumeView: View {
  @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
  @Environment(ResRefStore.self) private var resRefStore: ResRefStore
  @Environment(ResStore.self) private var resStore: ResStore

  var body: some View {
    let selApp: JobApp = jobAppStore.selectedApp!

    VStack {
      Text("No resumes available")
        .font(.title)
      Button(action: {
        resStore.create(jobApp: selApp, sources: resRefStore.defaultSources)}) {
        Text("Create Résumé")
          .buttonStyle(.borderedProminent)
          .controlSize(.regular)
          .buttonBorderShape(.capsule)
      }
    }.onAppear { print("create app bitches") }
  }
}
