//
//  CustomToolbarButtonStyle.swift
//  PhysicsCloudResume
//
//  Created by Christopher Culbreath on 8/22/24.
//


import SwiftUI

struct CustomToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(3)
            .cornerRadius(5)
            .background(Color.blue.opacity(0.3))
            .foregroundStyle(.gray)
            .scaleEffect(configuration.isPressed ? 1.2 : 1)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}

