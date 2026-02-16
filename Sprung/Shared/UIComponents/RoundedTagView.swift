//
//  RoundedTagView.swift
//  Sprung
//
//
import SwiftUI
struct RoundedTagView: View {
    var tagText: String
    var backgroundColor: Color = .blue
    var foregroundColor: Color = .white
    var body: some View {
        Text(tagText.capitalized)
            .font(.system(size: 10, weight: .medium))
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .foregroundColor(foregroundColor)
            .glassEffect(.regular.tint(backgroundColor), in: .capsule)
    }
}
