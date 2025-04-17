import Foundation
import Observation

@Observable
@MainActor
final class ResumePDFViewModel {
    private(set) var resume: Resume

    // UI State exposed to the view. Currently mirrors a flag on the model
    // but can be fully owned here in a later refactor.
    var isUpdating: Bool { resume.isUpdating }

    init(resume: Resume) {
        self.resume = resume
    }

    func refreshPDF() {
        resume.debounceExport()
    }
}
