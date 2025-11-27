import Foundation
/// Callbacks exposed to editable subviews so they can coordinate editing state.
struct EditableContentCallbacks {
    let isEditing: (UUID) -> Bool
    let beginEditing: (UUID) -> Void
    let toggleEditing: (UUID) -> Void
    let onChange: () -> Void
    init(
        isEditing: @escaping (UUID) -> Bool,
        beginEditing: @escaping (UUID) -> Void,
        toggleEditing: @escaping (UUID) -> Void,
        onChange: @escaping () -> Void
    ) {
        self.isEditing = isEditing
        self.beginEditing = beginEditing
        self.toggleEditing = toggleEditing
        self.onChange = onChange
    }
}
