//
//  ResumeInspectorView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 1/30/25.
//

import AppKit
import SwiftUI

struct CursorModifier: ViewModifier {
    let cursor: NSCursor

    func body(content: Content) -> some View {
        content.onHover { inside in
            if inside {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

extension View {
    func customCursor(_ cursor: NSCursor) -> some View {
        modifier(CursorModifier(cursor: cursor))
    }
}

struct ResumeInspectorView: View {
    @Environment(JobAppStore.self) private var jobAppStore
    @Binding var refresh: Bool
    @State private var height: CGFloat = 200
    @State private var isDragging = false
    @State private var isHidden = false
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        if let selApp = jobAppStore.selectedApp {
            @Bindable var selApp = selApp

            GeometryReader { geometry in
                VStack(spacing: 0) {
                    ResumeInspectorListView(
                        listSelection: $selApp.selectedRes,
                        resumes: selApp.resumes
                    )

                    if isHidden {
                        VStack(spacing: 0) {
                            // Drag handle for collapsed state
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 4)
                                .gesture(
                                    DragGesture(minimumDistance: 1)
                                        .onChanged { value in
                                            if value.translation.height < -20 { // Requires slight upward drag
                                                withAnimation(.spring()) {
                                                    isHidden = false
                                                    height = 200
                                                }
                                            }
                                        }
                                )
                                .customCursor(NSCursor.resizeUpDown)

                            Button("Create Resume") {
                                withAnimation(.spring()) {
                                    isHidden = false
                                    height = 200
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .background(Color.white.opacity(0.1)) // Optional: slight highlight for draggable area
                    } else {
                        // Drag handle for expanded state
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 4)
                            .gesture(
                                DragGesture(minimumDistance: 1)
                                    .updating($dragOffset) { value, state, _ in
                                        state = -value.translation.height
                                    }
                                    .onChanged { value in
                                        isDragging = true
                                        let newHeight = height - value.translation.height
                                        let boundedHeight = min(max(50, newHeight), geometry.size.height * 0.8)
                                        height = boundedHeight
                                    }
                                    .onEnded { value in
                                        let newHeight = height - value.translation.height
                                        if newHeight < 150 {
                                            withAnimation(.spring()) {
                                                isHidden = true
                                                height = 0
                                            }
                                        } else {
                                            height = min(max(50, newHeight), geometry.size.height * 0.8)
                                        }
                                        isDragging = false
                                    }
                            )
                            .customCursor(NSCursor.resizeUpDown)

                        CreateNewResumeView(refresh: $refresh)
                            .frame(height: max(0, height))
                            .clipped()
                    }
                }
            }
        } else {
            Text("No application selected.")
        }
    }
}
