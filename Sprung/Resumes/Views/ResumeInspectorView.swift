//
//  ResumeInspectorView.swift
//  Sprung
//
//  Created by Christopher Culbreath on 1/31/25.
//
import AppKit
import SwiftUI
struct CursorModifier: ViewModifier {
    let cursor: NSCursor
    @State private var didPushCursor = false
    func body(content: Content) -> some View {
        content
            .onHover { inside in
                if inside {
                    guard didPushCursor == false else { return }
                    cursor.push()
                    didPushCursor = true
                } else if didPushCursor {
                    NSCursor.pop()
                    didPushCursor = false
                }
            }
            .onDisappear {
                if didPushCursor {
                    NSCursor.pop()
                    didPushCursor = false
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
    @State private var drawerHeight: CGFloat = 240
    @State private var isCollapsed = false
    @State private var dragAnchorHeight: CGFloat?
    private let minHeight: CGFloat = 160
    private let maxHeight: CGFloat = 420
    private let collapseThreshold: CGFloat = 180
    private let defaultHeight: CGFloat = 280
    var body: some View {
        if let selApp = jobAppStore.selectedApp {
            @Bindable var selApp = selApp
            VStack(spacing: 12) {
                ResumeInspectorListView(
                    listSelection: $selApp.selectedRes,
                    resumes: selApp.resumes
                )
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 4)
                .padding(.top, 8)
                if isCollapsed {
                    collapsedDrawer
                } else {
                    expandedDrawer
                }
            }
            .background(Color.white)
        } else {
            Text("No application selected.")
        }
    }
    private var collapsedDrawer: some View {
        VStack(spacing: 0) {
            dragHandle
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if value.translation.height < -16 {
                                withAnimation(.spring()) {
                                    isCollapsed = false
                                    drawerHeight = defaultHeight
                                }
                            }
                        }
                )
                .customCursor(.resizeUpDown)
            Button("Create Resume") {
                withAnimation(.spring()) {
                    isCollapsed = false
                    drawerHeight = defaultHeight
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 32)
            .padding(.bottom, 25)
        }
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .padding(.vertical, 15)
    }
    private var expandedDrawer: some View {
        VStack(spacing: 0) {
            dragHandle
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if dragAnchorHeight == nil {
                                dragAnchorHeight = drawerHeight
                            }
                            let proposed = clampHeight((dragAnchorHeight ?? drawerHeight) - value.translation.height)
                            drawerHeight = proposed
                        }
                        .onEnded { value in
                            let start = dragAnchorHeight ?? drawerHeight
                            let finalHeight = clampHeight(start - value.translation.height)
                            dragAnchorHeight = nil
                            if finalHeight < collapseThreshold {
                                withAnimation(.spring()) {
                                    isCollapsed = true
                                    drawerHeight = defaultHeight
                                }
                            } else {
                                drawerHeight = finalHeight
                            }
                        }
                )
                .customCursor(.resizeUpDown)
            CreateNewResumeView(refresh: $refresh)
                .frame(height: drawerHeight)
                .clipped()
        }
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .padding(.top, 8)
        .padding(.bottom, 32)
    }
    private var dragHandle: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(height: 4)
    }
    private func clampHeight(_ proposed: CGFloat) -> CGFloat {
        min(max(proposed, minHeight), maxHeight)
    }
}
