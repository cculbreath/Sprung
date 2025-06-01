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
            
            // Sort letters: assessed by vote/score count (descending), then unassessed by date
            let sortedLetters = sortCoverLetters(coverLetters)
            
            // Group letters into assessed and unassessed
            let assessedLetters = sortedLetters.filter { $0.hasBeenAssessed }
            let unassessedLetters = sortedLetters.filter { !$0.hasBeenAssessed }
            
            // Show assessed letters first, sorted by vote/score count
            ForEach(assessedLetters, id: \.id) { letter in
                Text(formattedLetterName(letter))
                    .tag(Optional(letter))
            }
            
            // Show separator and unassessed letters if both groups exist
            if !assessedLetters.isEmpty && !unassessedLetters.isEmpty {
                Divider()
                Text("Unassessed").tag(nil as CoverLetter?)
                    .disabled(true)
            }
            
            ForEach(unassessedLetters, id: \.id) { letter in
                Text(formattedLetterName(letter))
                    .tag(Optional(letter))
            }
        }
        .id(coverLetters.map(\.id)) // Force refresh when letters array changes
    }
    
    private func sortCoverLetters(_ letters: [CoverLetter]) -> [CoverLetter] {
        return letters.sorted { letter1, letter2 in
            // First, separate assessed from unassessed
            if letter1.hasBeenAssessed != letter2.hasBeenAssessed {
                return letter1.hasBeenAssessed && !letter2.hasBeenAssessed
            }
            
            // If both are assessed, sort by vote/score count (descending)
            if letter1.hasBeenAssessed && letter2.hasBeenAssessed {
                let score1 = max(letter1.voteCount, letter1.scoreCount)
                let score2 = max(letter2.voteCount, letter2.scoreCount)
                if score1 != score2 {
                    return score1 > score2
                }
            }
            
            // Otherwise, sort by modification date (most recent first)
            return letter1.moddedDate > letter2.moddedDate
        }
    }
    
    private func formattedLetterName(_ letter: CoverLetter) -> String {
        let baseName = letter.generated ? letter.sequencedName : "Ungenerated draft"
        
        if letter.hasBeenAssessed {
            let count = max(letter.voteCount, letter.scoreCount)
            let suffix = letter.voteCount > 0 ? " (\(count) votes)" : " (\(count) pts)"
            return baseName + suffix
        }
        
        return baseName
    }
}
