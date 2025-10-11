//
//  RoundedTagView.swift
//  Sprung
//
//  Created by Christopher Culbreath on 9/9/24.
//

import SwiftUI

struct RoundedTagView: View {
    var tagText: String
    var backgroundColor: Color = .blue
    var foregroundColor: Color = .white

    var body: some View {
        Text(tagText.capitalized)
            .font(.caption)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .foregroundColor(foregroundColor)
            .glassEffect(.regular.tint(backgroundColor), in: .capsule)
    }
}
