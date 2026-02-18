// Sprung/Shared/UIComponents/ProcessingLogoOverlay.swift
import SwiftUI

/// Animated Sprung logo overlay shown when the LLM is processing
/// but the reasoning stream dialog and review sheet are not visible.
///
/// Reuses the bounce/wiggle/breathe/float animation from `AnimatedThinkingText`
/// at a smaller size with a subtle material backdrop.
struct ProcessingLogoOverlay: View {
    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.15)
                .ignoresSafeArea()

            // Logo with material pill
            VStack(spacing: 12) {
                animatedLogo

                Text("Customizing...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: true)
    }

    private var animatedLogo: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let bounce = sin(time * 3) * 0.05 + 1.0
            let wiggle = sin(time * 5) * 3
            let breathe = sin(time * 2) * 0.1 + 1.0

            Image("custom.sprung_raster")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 56, height: 56)
                .scaleEffect(bounce * breathe)
                .rotationEffect(.degrees(wiggle))
                .offset(y: sin(time * 4) * 2)
        }
    }
}
