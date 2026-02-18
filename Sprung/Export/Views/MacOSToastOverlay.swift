//
//  MacOSToastOverlay.swift
//  Sprung
//
//
import SwiftUI

// MARK: - Toast Overlay

struct MacOSToastOverlay: View {
    let showToast: Bool
    let message: String
    var body: some View {
        ZStack {
            if showToast {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.subheadline)
                        Text(message)
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.regularMaterial)
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
                .padding(.top, 8)
                .zIndex(1)
                .animation(.easeInOut(duration: 0.3), value: showToast)
            }
        }
    }
}
