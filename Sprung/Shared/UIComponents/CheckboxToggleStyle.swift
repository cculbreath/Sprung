//
//  CheckboxToggleStyle.swift
//  Sprung
//
//  Created on 6/2/25.
//

import SwiftUI

/// Custom checkbox toggle style with square checkbox appearance
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .foregroundColor(configuration.isOn ? .accentColor : .secondary)
                .onTapGesture {
                    configuration.isOn.toggle()
                }
            configuration.label
        }
    }
}