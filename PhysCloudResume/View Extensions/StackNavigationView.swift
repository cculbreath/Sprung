//
//  StackNavigationView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/2/24.
//
import SwiftUI

struct StackNavigationView<RootContent>: View where RootContent: View {
    @Binding var currentSubview: AnyView
    @Binding var showingSubview: Bool

    let rootView: () -> RootContent

    init(
        currentSubview: Binding<AnyView>, showingSubview: Binding<Bool>,
        @ViewBuilder rootView: @escaping () -> RootContent
    ) {
        _currentSubview = currentSubview
        _showingSubview = showingSubview
        self.rootView = rootView
    }

    var body: some View {
        VStack {
            if !showingSubview {
                rootView()
            } else {
                StackNavigationSubview(isVisible: $showingSubview) {
                    currentSubview
                }
                .transition(.move(edge: .trailing))
            }
        }
    }

    private struct StackNavigationSubview<Content>: View where Content: View {
        @Binding var isVisible: Bool
        let contentView: () -> Content
        var body: some View {
            VStack {
                contentView() // subview
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button(
                        action: {
                            withAnimation(.easeOut(duration: 0.3)) {
                                isVisible = false
                            }
                        },
                        label: {
                            Label("back", systemImage: "chevron.left")
                        }
                    )
                }
            }
        }
    }
}
