//
//  ToggleChevronView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 2/27/25.
//

import SwiftUI

struct ToggleChevronView: View {
    @Binding var isExpanded: Bool
    let toggleAction: () -> Void

    var body: some View {
        Image(systemName: "chevron.right")
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .animation(.easeInOut(duration: 0.1), value: isExpanded)
            .foregroundColor(.primary)
            .onTapGesture {
                toggleAction()
            }
    }
}
