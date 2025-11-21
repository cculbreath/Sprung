//
//  DraggableSlidingSourceListView.swift
//  Sprung
//
//  Created by Christopher Culbreath on 2/27/25.
//
import SwiftUI
struct DraggableSlidingSourceListView: View {
    @Binding var refresh: Bool
    @Binding var isVisible: Bool // Add this to control visibility from parent
    @State private var height: CGFloat = 300
    @State private var isDragging = false
    @GestureState private var dragOffset: CGFloat = 0
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Drag handle
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 4)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .updating($dragOffset) { value, state, _ in
                                state = value.translation.height
                            }
                            .onChanged { value in
                                isDragging = true
                                let newHeight = height - value.translation.height
                                if newHeight < 150 {
                                    // Allow height to continue decreasing when near hiding threshold
                                    height = newHeight
                                } else {
                                    // Bound height to 80% of container when not hiding
                                    height = min(max(150, newHeight), geometry.size.height * 0.8)
                                }
                            }
                            .onEnded { value in
                                let newHeight = height - value.translation.height
                                if newHeight < 150 {
                                    withAnimation(.spring()) {
                                        isVisible = false
                                    }
                                } else {
                                    height = min(max(150, newHeight), geometry.size.height * 0.8)
                                }
                                isDragging = false
                            }
                    )
                ScrollView {
                    VStack(spacing: 12) {
                        ResRefView()
                        Divider()
                        TemplateQuickActionsView()
                    }
                    .padding(.horizontal, 0)
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.6))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color.black.opacity(0.4)),
                alignment: .top
            )
            .clipped()
            .position(x: geometry.size.width / 2,
                      y: geometry.size.height - (height / 2))
            .frame(height: height)
        }
    }
}
