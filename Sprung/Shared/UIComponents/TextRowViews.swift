//
//  TextRowViews.swift
//  Sprung
//
//
import SwiftUI

struct HeaderTextRow: View {
    var body: some View {
        HStack {
            Text("Résumé Field Values")
                .font(.headline)
        }
        .cornerRadius(5)
        .padding(.vertical, 2)
    }
}

/// Single-line text row with leading/trailing text
/// Background color indicates AI status, not text color
struct AlignedTextRow: View {
    let leadingText: String
    let trailingText: String?

    var body: some View {
        let indent: CGFloat = 100.0
        HStack {
            Text(leadingText)
                .foregroundColor(.secondary)
                .frame(
                    width: ((trailingText?.isEmpty ?? true) ? nil : (leadingText.isEmpty ? 15 : indent)),
                    alignment: .leading
                )
            if let trailingText = trailingText, !trailingText.isEmpty {
                Text(trailingText)
                    .foregroundColor(.primary)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
        }
        .cornerRadius(5)
        .padding(.vertical, 2)
    }
}

/// Two-line text row with title and description
/// Background color indicates AI status, not text color
struct StackedTextRow: View {
    let title: String
    let description: String

    var body: some View {
        let indent: CGFloat = 100.0
        VStack(alignment: .leading) {
            Text(title)
                .foregroundColor(.secondary)
                .fontWeight(.medium)
                .frame(minWidth: indent, maxWidth: .infinity, alignment: .leading)
            Text(description)
                .foregroundColor(.primary)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .cornerRadius(5)
        .padding(.vertical, 2)
    }
}
