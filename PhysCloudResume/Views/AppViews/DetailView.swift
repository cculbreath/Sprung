//
//  DetailView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 1/30/25.
//

// DetailView.swift

import SwiftUI

struct DetailView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Binding var selectedTab: TabList
    @Binding var tabRefresh: Bool
    var body: some View {
        @Bindable var jobAppStore = jobAppStore
        VStack(alignment: .leading) {
            if let selApp = jobAppStore.selectedApp {
                TabWrapperView(selectedTab: $selectedTab, tabRefresh: $tabRefresh)
                    .navigationTitle(selApp.job_position)
            } else {
                Text("No Selection")
            }
        }
        .frame(
            minWidth: 200,
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .center
        )
        .background(
            VStack {
                Divider()
                Spacer()
            }
        )
    }
}
