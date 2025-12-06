//
//  ToggleChevronView.swift
//  Sprung
//
//
import SwiftUI
struct ToggleChevronView: View {
    @Binding var isExpanded: Bool
    var body: some View {
        Image(systemName: "chevron.right")
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .animation(.easeInOut(duration: 0.1), value: isExpanded)
            .foregroundColor(.primary)
    }
}
