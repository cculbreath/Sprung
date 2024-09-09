//
//  ResumeSplitView.swift
//  PhysicsCloudResume
//
//  Created by Christopher Culbreath on 8/31/24.
//

import SwiftUI

struct ResumeSplitView: View {
  @Binding var selRes: Resume
  @Binding var isWide: Bool
  @Binding var tab: TabList
  var body: some View {
    HSplitView {
      if let rootNode = selRes.rootNode {

        ResumeDetailView(
          selRes: $selRes,
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
