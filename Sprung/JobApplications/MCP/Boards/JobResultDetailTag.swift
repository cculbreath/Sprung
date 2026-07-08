//
//  JobResultDetailTag.swift
//  Sprung
//
//  Small pill used by the job-board result rows (Dice, ZipRecruiter, Custom
//  Site) to show employment type, workplace type, salary, etc.
//

import SwiftUI

struct JobResultDetailTag: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(4)
            .lineLimit(1)
    }
}
