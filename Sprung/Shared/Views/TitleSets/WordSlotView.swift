//
//  WordSlotView.swift
//  Sprung
//
//  Single editable word slot with lock toggle for the title set generator.
//

import SwiftUI

struct WordSlotView: View {
    @Binding var word: TitleWord
    let index: Int

    var body: some View {
        HStack {
            TextField("Word \(index + 1)", text: $word.text)
                .textFieldStyle(.plain)
                .font(.body)

            Button {
                word.isLocked.toggle()
            } label: {
                Image(systemName: word.isLocked ? "lock.fill" : "lock.open")
                    .foregroundStyle(word.isLocked ? .cyan : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(word.isLocked ? Color.cyan.opacity(0.5) : Color.clear, lineWidth: 2)
        )
    }
}
