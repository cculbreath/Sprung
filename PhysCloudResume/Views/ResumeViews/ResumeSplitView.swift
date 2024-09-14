//
//  ResumeSplitView.swift
//  PhysicsCloudResume
//
//  Created by Christopher Culbreath on 8/31/24.
//

import SwiftUI

struct ResumeSplitView: View {
  @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
  @Binding var isWide: Bool
  @Binding var tab: TabList
  var body: some View {
    if let selApp = jobAppStore.selectedApp {
      if let selRes = selApp.selectedRes {
        @Bindable var selApp = selApp

        HSplitView {
          if let rootNode = selRes.rootNode {

            ResumeDetailView(
              selRes: $selApp.selectedRes,
              tab: $tab,
              rootNode: rootNode,
              isWide: $isWide

            )
            .frame(
              minWidth: isWide ? 350 : 200,
              idealWidth: isWide ? 500 : 300,
              maxWidth: 600,
              maxHeight: .infinity
            ).onAppear{print("RootNode")
              //          print(rootNode.resume.id)
            }
            .layoutPriority(1)  // Ensures this view gets priority in layout
          }

            ResumePDFView(resume: selRes)
              .frame(
                minWidth: 300, idealWidth: 400,
                maxWidth: .infinity, maxHeight: .infinity
              )
              .layoutPriority(1)  // Less priority, but still resizable
          }
        }
      }
    }
  }

