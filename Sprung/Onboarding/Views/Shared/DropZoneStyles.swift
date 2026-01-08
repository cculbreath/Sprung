import SwiftUI

// MARK: - Shared Drop Zone Styling

extension View {
    /// Apply consistent drop zone styling with dashed border
    /// - Parameters:
    ///   - isHighlighted: Whether the drop zone is currently targeted
    ///   - cornerRadius: Corner radius for the rounded rectangle (default: 12)
    func dropZoneStyle(isHighlighted: Bool, cornerRadius: CGFloat = 12) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isHighlighted ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        isHighlighted ? Color.accentColor : Color.secondary.opacity(0.2),
                        style: StrokeStyle(lineWidth: 1.2, dash: [6, 6])
                    )
            )
    }
}
