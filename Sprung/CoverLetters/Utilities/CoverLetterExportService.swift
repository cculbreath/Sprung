//
//  CoverLetterExportService.swift
//  Sprung
//
//  Created by Christopher Culbreath on 4/20/25.
//

import Foundation
import SwiftUI

protocol CoverLetterExportService {
    func exportPDF(from coverLetter: CoverLetter, applicant: Applicant) -> Data
}

struct LocalCoverLetterExportService: CoverLetterExportService {
    func exportPDF(from coverLetter: CoverLetter, applicant: Applicant) -> Data {
        return CoverLetterPDFGenerator.generatePDF(from: coverLetter, applicant: applicant)
    }
}
