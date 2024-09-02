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

                if let url = Bundle.main.url(
                    forResource: "resume_data", withExtension: "json")
                {
                    // Now you can use `url` to read the file, load its contents, etc.
                    print("URL for resume.json: \(url)")
                    if let resume = Resume(
                        jobApp: selApp, templateFileUrl: url,
                        enabledSources: resRefStore.defaultSources)
                    {
                        resStore.addResume(res: resume, to: selApp)
                    } else {
                        print("error reading json file")
                    }

                } else {
                    print("resume.json not found in bundle.")
                }

            }) {
                Text("Create Résumé")
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .buttonBorderShape(.capsule)
            }
        }.onAppear{print("create app bitches")}
    }
}
