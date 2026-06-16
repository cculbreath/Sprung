import SwiftUI

/// Stable color resolution for Skills Bank categories. Pure mapping from a category
/// name to a `Color`, used by the category header chrome.
enum SkillCategoryColor {
    /// Stable color for a category based on a known mapping, falling back to a
    /// hash-derived palette entry for unknown categories.
    static func color(for category: String) -> Color {
        let knownColors: [String: Color] = [
            "Programming Languages": .blue,
            "Frameworks & Libraries": .purple,
            "Tools & Platforms": .orange,
            "Tools & Software": .orange,
            "Hardware & Electronics": .red,
            "Fabrication & Manufacturing": .brown,
            "Scientific & Analysis": .green,
            "Methodologies & Processes": .cyan,
            "Writing & Communication": .mint,
            "Communication & Writing": .mint,
            "Research Methods": .pink,
            "Regulatory & Compliance": .gray,
            "Leadership & Management": .teal,
            "Domain Expertise": .indigo,
        ]
        if let known = knownColors[category] { return known }
        // Stable color based on hash for unknown categories
        let palette: [Color] = [.blue, .purple, .orange, .red, .green, .cyan, .mint, .pink, .teal, .indigo]
        let index = abs(category.hashValue) % palette.count
        return palette[index]
    }
}
