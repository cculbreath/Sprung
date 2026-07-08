//
//  JobSearchImportSummary.swift
//  Sprung
//
//  The "Imported N • M already in pipeline • K skipped" summary rendered after
//  every board's Import-All action. Shared so the phrasing stays identical
//  across Dice, ZipRecruiter, LinkedIn, and Custom Site.
//

import Foundation

enum JobSearchImportSummary {
    static func text(imported: Int, duplicates: Int, skipped: Int) -> String {
        var parts = ["Imported \(imported)"]
        if duplicates > 0 {
            parts.append("\(duplicates) already in pipeline")
        }
        if skipped > 0 {
            parts.append("\(skipped) skipped")
        }
        return parts.joined(separator: " • ")
    }
}
