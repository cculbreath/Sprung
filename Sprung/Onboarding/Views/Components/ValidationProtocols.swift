import Foundation

/// Shared protocol for views that manage an editable draft and track dirty state.
protocol DraftManageable {
    associatedtype DraftType: Equatable

    var draft: DraftType { get set }
    var originalDraft: DraftType { get set }
    var hasChanges: Bool { get }

    func saveDraft() async -> Bool
    func cancelAndClose()
}

/// Callbacks exposed to editable subviews so they can coordinate editing state.
struct EditableContentCallbacks {
    let isEditing: (UUID) -> Bool
    let beginEditing: (UUID) -> Void
    let toggleEditing: (UUID) -> Void
    let endEditing: (UUID) -> Void
    let onChange: () -> Void

    init(
        isEditing: @escaping (UUID) -> Bool,
        beginEditing: @escaping (UUID) -> Void,
        toggleEditing: @escaping (UUID) -> Void,
        endEditing: @escaping (UUID) -> Void,
        onChange: @escaping () -> Void
    ) {
        self.isEditing = isEditing
        self.beginEditing = beginEditing
        self.toggleEditing = toggleEditing
        self.endEditing = endEditing
        self.onChange = onChange
    }
}
