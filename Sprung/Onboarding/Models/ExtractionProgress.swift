import Foundation
enum ExtractionProgressStage: String, CaseIterable, Identifiable {
    case fileAnalysis
    case aiExtraction
    case artifactSave
    case assistantHandoff
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fileAnalysis:
            return "Analyzing document"
        case .aiExtraction:
            return "Extracting résumé details"
        case .artifactSave:
            return "Saving résumé artifact"
        case .assistantHandoff:
            return "Preparing interview flow"
        }
    }
}
enum ExtractionProgressStageState: String {
    case pending
    case active
    case completed
    case failed
}
struct ExtractionProgressItem: Identifiable, Equatable {
    var stage: ExtractionProgressStage
    var state: ExtractionProgressStageState
    var detail: String?
    var id: ExtractionProgressStage { stage }
}
struct ExtractionProgressUpdate: Equatable {
    let stage: ExtractionProgressStage
    let state: ExtractionProgressStageState
    let detail: String?
    init(stage: ExtractionProgressStage, state: ExtractionProgressStageState, detail: String? = nil) {
        self.stage = stage
        self.state = state
        self.detail = detail
    }
}
typealias ExtractionProgressHandler = @Sendable (ExtractionProgressUpdate) async -> Void
extension ExtractionProgressStage {
    static func defaultItems() -> [ExtractionProgressItem] {
        ExtractionProgressStage.allCases.map { stage in
            ExtractionProgressItem(stage: stage, state: .pending, detail: nil)
        }
    }
    var order: Int {
        guard let index = ExtractionProgressStage.allCases.firstIndex(of: self) else { return 0 }
        return index
    }
}
