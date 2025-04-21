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