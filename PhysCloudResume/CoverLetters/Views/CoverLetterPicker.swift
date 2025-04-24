//
//  CoverLetterPicker.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/21/25.
//

import Foundation
import SwiftUI

/// A reusable picker for selecting a CoverLetter
struct CoverLetterPicker: View {
    /// The list of cover letters to choose from (ideally pre-sorted)
    let coverLetters: [CoverLetter]
    /// Currently selected cover letter (optional)
    @Binding var selection: CoverLetter?
    /// Whether to show a "None" option for no selection
    var includeNoneOption: Bool = false
    /// Label for the none option
    var noneLabel: String = "None"
    /// Title label for the picker
    var label: String = "Select a Cover Letter"

    var body: some View {
        Picker(label, selection: $selection) {
            if includeNoneOption {
                Text(noneLabel).tag(nil as CoverLetter?)
            }
            ForEach(coverLetters, id: \.id) { letter in
                if letter.generated {
                    Text(letter.sequencedName)
                        .tag(letter as CoverLetter?)
                } else {
                    Text(selection == letter ? letter.sequencedName : "Ungenerated draft")
                        .tag(letter as CoverLetter?)
                }
            }
        }
        .id(selection?.id) // Force refresh when selection changes
    }
}
