//
//  ResumePDFViewModel.swift
//  Sprung
//
//  Created by Christopher Culbreath on 4/17/25.
//
import Foundation
import Observation
@Observable
@MainActor
final class ResumePDFViewModel {
    private(set) var resume: Resume
    /// Tracks whether a JSON → PDF export operation is currently running so
    /// the UI can display a progress indicator.
    var isUpdating: Bool = false
    init(resume: Resume) {
        self.resume = resume
    }
}
