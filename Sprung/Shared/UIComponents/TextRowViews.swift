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
struct AlignedTextRow: View {
    let leadingText: String
    let trailingText: String?
    let nodeStatus: LeafStatus
    var body: some View {
        let indent: CGFloat = 100.0
        HStack {
            Text(leadingText)
                .foregroundColor(nodeStatus == .aiToReplace ? .accentColor : .secondary)
                .fontWeight(nodeStatus == .aiToReplace ? .medium : .regular)
                .frame(
                    width: ((trailingText?.isEmpty ?? true) ? nil : (leadingText.isEmpty ? 15 : indent)),
                    alignment: .leading
                )
            if let trailingText = trailingText, !trailingText.isEmpty {
                Text(trailingText)
                    .foregroundColor(nodeStatus == .aiToReplace ? .accentColor : .secondary)
                    .fontWeight(.regular)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
        }
        .cornerRadius(5)
        .padding(.vertical, 2)
    }
}
struct StackedTextRow: View {
    let title: String
    let description: String
    let nodeStatus: LeafStatus
    var body: some View {
        let indent: CGFloat = 100.0
        VStack(alignment: .leading) {
            Text(title)
                .foregroundColor(nodeStatus == .aiToReplace ? .accentColor : .secondary)
                .fontWeight(nodeStatus == .aiToReplace ? .semibold : .medium)
                .frame(minWidth: indent, maxWidth: .infinity, alignment: .leading)
            Text(description)
                .foregroundColor(nodeStatus == .aiToReplace ? .accentColor : .secondary)
                .fontWeight(nodeStatus == .aiToReplace ? .regular : .light)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .cornerRadius(5)
        .padding(.vertical, 2)
    }
}
