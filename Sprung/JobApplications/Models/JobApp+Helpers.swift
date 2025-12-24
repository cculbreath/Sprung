//
//  JobApp+Helpers.swift
//  Sprung
//
//

import Foundation

/// General helper extensions for JobApp
extension JobApp {
    /// Display-friendly title combining position and company
    var displayTitle: String {
        if !jobPosition.isEmpty {
            return "\(jobPosition) at \(companyName)"
        }
        return companyName
    }
}
