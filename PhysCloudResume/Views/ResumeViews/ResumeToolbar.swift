//
//  ResumeToolbar.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/10/24.
//
import SwiftUI


@ToolbarContentBuilder
func resumeToolbarContent(selRes: Binding<Resume?>, selectedApp: JobApp?, attention: Binding<Int>) -> some ToolbarContent {
      // Ensure selRes has a value if it is nil



      // ToolbarItem: Custom Stepper for attention control
      ToolbarItem(placement: .automatic) {
        CustomStepper(value: attention, range: 0...4)
          .padding(.vertical, 0)
          .overlay {
            Text("Attention Grab")
              .font(.caption2)
              .padding(.vertical, 0)
              .lineLimit(1)
              .minimumScaleFactor(0.9)
              .fontWeight(.light)
              .offset(y: 18)
          }
          .offset(y: -1)
          .padding(.trailing, 2)
          .padding(.leading, 6)
      }

      // ToolbarItem: AiFunctionView or fallback text
      ToolbarItem(placement: .automatic) {
        if selRes.wrappedValue?.rootNode != nil {
          AiFunctionView(res: selRes, attn: attention)
        } else {
          Text(":(")
        }
      }

    }
  
