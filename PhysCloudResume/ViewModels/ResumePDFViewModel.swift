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

    /// Public intent called by the view to trigger a PDF refresh.
    func refreshPDF() {
        // Forward to the model’s debounce implementation but keep the state
        // locally.
        resume.debounceExport(onStart: { [weak self] in
            self?.isUpdating = true
        }, onFinish: { [weak self] in
            self?.isUpdating = false
        })
    }
}
