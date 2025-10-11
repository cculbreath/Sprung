//
//  CoverLetterVotingProcessor.swift
//  Sprung
//
//  Created by Christopher Culbreath on 6/11/25.
//

import Foundation

class CoverLetterVotingProcessor {
    
    func getWinningLetter(
        from coverLetters: [CoverLetter],
        voteTally: [UUID: Int],
        scoreTally: [UUID: Int],
        votingScheme: VotingScheme
    ) -> CoverLetter? {
        if votingScheme == .firstPastThePost {
            let maxVotes = voteTally.values.max() ?? 0
            guard maxVotes > 0 else { return nil }
            
            let winningIds = voteTally.filter { $0.value == maxVotes }.map { $0.key }
            return coverLetters.first { winningIds.contains($0.id) }
        } else {
            let maxScore = scoreTally.values.max() ?? 0
            guard maxScore > 0 else { return nil }
            
            let winningIds = scoreTally.filter { $0.value == maxScore }.map { $0.key }
            return coverLetters.first { winningIds.contains($0.id) }
        }
    }
    
    func hasZeroVoteLetters(
        in coverLetters: [CoverLetter],
        voteTally: [UUID: Int],
        scoreTally: [UUID: Int],
        votingScheme: VotingScheme
    ) -> Bool {
        return coverLetters.contains { letter in
            if votingScheme == .firstPastThePost {
                return (voteTally[letter.id] ?? 0) == 0
            } else {
                return (scoreTally[letter.id] ?? 0) == 0
            }
        }
    }
    
    func getZeroVoteLetters(
        from coverLetters: [CoverLetter],
        voteTally: [UUID: Int],
        scoreTally: [UUID: Int],
        votingScheme: VotingScheme
    ) -> [CoverLetter] {
        return coverLetters.filter { letter in
            if votingScheme == .firstPastThePost {
                return (voteTally[letter.id] ?? 0) == 0
            } else {
                return (scoreTally[letter.id] ?? 0) == 0
            }
        }
    }
}