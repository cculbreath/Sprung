import SwiftUI

// MARK: - View Extensions

extension View {
    /// Applies an Apple Intelligence-style glow effect using the provided shape
    @MainActor
    func intelligenceGlow<S: InsettableShape>(
        in shape: S,
        isActive: Bool = true
    ) -> some View {
        overlay(
            Group {
                if isActive {
                    shape.intelligenceStroke()
                }
            }
        )
    }
}

// MARK: - Shape Extension

extension InsettableShape {
    @MainActor
    func intelligenceStroke(
        lineWidths: [CGFloat] = [3, 5, 7, 9],
        blurs: [CGFloat] = [0, 3, 8, 12],
        updateInterval: TimeInterval = 0.5,
        animationDurations: [TimeInterval] = [0.6, 0.8, 1.0, 1.2]
    ) -> some View {
        IntelligenceStrokeView(
            shape: self,
            lineWidths: lineWidths,
            blurs: blurs,
            updateInterval: updateInterval,
            animationDurations: animationDurations
        )
        .allowsHitTesting(false)
    }
}

// MARK: - Core Rendering View

private struct IntelligenceStrokeView<S: InsettableShape>: View {
    let shape: S
    let lineWidths: [CGFloat]
    let blurs: [CGFloat]
    let updateInterval: TimeInterval
    let animationDurations: [TimeInterval]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stops: [Gradient.Stop] = .rainbowSpring

    var body: some View {
        let layerCount = min(lineWidths.count, blurs.count, animationDurations.count)
        let gradient = AngularGradient(
            gradient: Gradient(stops: stops),
            center: .center
        )

        ZStack {
            ForEach(0..<layerCount, id: \.self) { i in
                shape
                    .strokeBorder(gradient, lineWidth: lineWidths[i])
                    .blur(radius: blurs[i])
                    .animation(
                        reduceMotion ? .linear(duration: 0) : .easeInOut(duration: animationDurations[i]),
                        value: stops
                    )
            }
        }
        .task(id: updateInterval) {
            while !Task.isCancelled {
                stops = .rainbowSpring
                try? await Task.sleep(for: .seconds(updateInterval))
            }
        }
    }
}

// MARK: - Gradient Definition

private extension Array where Element == Gradient.Stop {
    /// Rainbow spring gradient based on the SVG gradient:
    /// Uses colors from #0CF → #0059FF → #0014A8 → #764DFF → #B00068 → #CC008D → #F02C00 → #FF8A47 → #FFB700
    static var rainbowSpring: [Gradient.Stop] {
        let colors: [Color] = [
            Color(red: 0, green: 0.8, blue: 1.0),          // #0CF (cyan)
            Color(red: 0, green: 0.35, blue: 1.0),         // #0059FF (blue)
            Color(red: 0, green: 0.08, blue: 0.66),        // #0014A8 (dark blue)
            Color(red: 0.46, green: 0.30, blue: 1.0),      // #764DFF (purple)
            Color(red: 0.69, green: 0, blue: 0.41),        // #B00068 (magenta)
            Color(red: 0.8, green: 0, blue: 0.55),         // #CC008D (pink)
            Color(red: 0.94, green: 0.17, blue: 0),        // #F02C00 (red-orange)
            Color(red: 1.0, green: 0.54, blue: 0.28),      // #FF8A47 (orange)
            Color(red: 1.0, green: 0.72, blue: 0)          // #FFB700 (golden)
        ]

        return colors.map { Gradient.Stop(color: $0, location: Double.random(in: 0...1)) }
            .sorted { $0.location < $1.location }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 30) {
        Text("Rainbow Spring Glow")
            .font(.title)
            .padding(22)
            .background(.ultraThinMaterial)
            .intelligenceGlow(in: RoundedRectangle(cornerRadius: 16, style: .continuous))

        VStack(spacing: 12) {
            Text("Chat Transcript Example")
                .font(.headline)
            Text("This demonstrates the glow effect")
                .font(.body)
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .intelligenceGlow(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
    .padding()
    .preferredColorScheme(.dark)
}
