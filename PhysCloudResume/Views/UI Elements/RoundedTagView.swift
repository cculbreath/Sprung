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
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(10)
    }
}
