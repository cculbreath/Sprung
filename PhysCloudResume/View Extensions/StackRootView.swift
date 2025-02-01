//
//  StackRootView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/2/24.
//

import SwiftUI

struct StackRootView: View {
    @State private var currentSubview = AnyView(StackSecondView())
    @State private var showingSubview = false
    var body: some View {
        StackNavigationView(currentSubview: $currentSubview, showingSubview: $showingSubview) {
            Text("I'm the rootview")
            Button(
                action: {
                    showSubview(
                        view: AnyView(
                            Text("Subview!").frame(maxWidth: .infinity, maxHeight: .infinity).background(
                                Color.white)))
                },
                label: {
                    Text("go to subview")
                }
            )
        }
        .frame(
            minWidth: 500, idealWidth: 500, maxWidth: 500, minHeight: 500, idealHeight: 500,
            maxHeight: 500
        )
    }

    private func showSubview(view: AnyView) {
        withAnimation(.easeOut(duration: 0.3)) {
            currentSubview = view
            showingSubview = true
        }
    }
}
