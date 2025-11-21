import SwiftUI

// MARK: - View Extensions
extension View {
    @MainActor
    func intelligenceBackground<S: InsettableShape>(
        in shape: S
    ) -> some View {
        background(shape.intelligenceStroke())
    }

    @MainActor
    func intelligenceOverlay<S: InsettableShape>(
        in shape: S
    ) -> some View {
        overlay(shape.intelligenceStroke())
    }
}

// MARK: - Shape Extension
extension InsettableShape {
    @MainActor
    func intelligenceStroke(
        lineWidths: [CGFloat] = [2.0, 3.0, 4.0, 5.0],
        blurs: [CGFloat] = [6, 12, 20, 30],
        updateInterval: TimeInterval = 0.6,
        animationDurations: [TimeInterval] = [0.8, 1.0, 1.2, 1.5],
        gradientGenerator: @MainActor @Sendable @escaping () -> [Gradient.Stop] = { .rainbowSpring }
    ) -> some View {
        IntelligenceStrokeView(
            shape: self,
            lineWidths: lineWidths,
            blurs: blurs,
            updateInterval: updateInterval,
            animationDurations: animationDurations,
            gradientGenerator: gradientGenerator
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
    let gradientGenerator: @MainActor @Sendable () -> [Gradient.Stop]

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
                stops = gradientGenerator()
                try? await Task.sleep(for: .seconds(updateInterval))
            }
        }
    }
}

// MARK: - Gradient Definition
private extension Array where Element == Gradient.Stop {
    /// Rainbow spring gradient based on the SVG gradient:
    /// Uses colors from #0CF → #0059FF → #0014A8 → #764DFF → #B00068 → #CC008D → #F02C00 → #FF8A47 → #FFB700
    /// With boosted opacity for visibility
    static var rainbowSpring: [Gradient.Stop] {
        let colors: [Color] = [
            Color(red: 0, green: 0.8, blue: 1.0).opacity(0.6),          // #0CF (cyan)
            Color(red: 0, green: 0.35, blue: 1.0).opacity(0.65),         // #0059FF (blue)
            Color(red: 0, green: 0.08, blue: 0.66).opacity(0.65),        // #0014A8 (dark blue)
            Color(red: 0.46, green: 0.30, blue: 1.0).opacity(0.65),      // #764DFF (purple)
            Color(red: 0.69, green: 0, blue: 0.41).opacity(0.65),        // #B00068 (magenta)
            Color(red: 0.8, green: 0, blue: 0.55).opacity(0.65),         // #CC008D (pink)
            Color(red: 0.94, green: 0.17, blue: 0).opacity(0.65),        // #F02C00 (red-orange)
            Color(red: 1.0, green: 0.54, blue: 0.28).opacity(0.6),      // #FF8A47 (orange)
            Color(red: 1.0, green: 0.72, blue: 0).opacity(0.6)          // #FFB700 (golden)
        ]

        return colors.map { Gradient.Stop(color: $0, location: Double.random(in: 0...1)) }
            .sorted { $0.location < $1.location }
    }
}
