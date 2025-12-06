//
//  ImageButton.swift
//  Sprung
//
//
import SwiftUI
struct ImageButton: View {
    let systemName: String?
    let name: String?
    var defaultColor: Color?
    var activeColor: Color?
    let imageSize: CGFloat
    let action: () -> Void
    let externalIsActive: Bool?
    @State private var isHovered = false
    @State private var isActive = false
    init(
        systemName: String? = nil, name: String? = nil, imageSize: CGFloat = 35,
        defaultColor: Color? = Color.secondary, activeColor: Color? = Color.accentColor,
        isActive: Bool? = nil,
        action: @escaping () -> Void
    ) {
        // Validation: Ensure either systemName or name is provided, but not both or none
        let hasSystem = (systemName != nil)
        let hasName = (name != nil)
        var resolvedSystemName = systemName
        var resolvedName = name
        if (!hasSystem && !hasName) || (hasSystem && hasName) {
            Logger.error("ImageButton misconfigured: provide either `systemName` or `name` (but not both)")
            // Fallback to a safe system image
            resolvedSystemName = "questionmark.circle"
            resolvedName = nil
        }
        self.imageSize = imageSize
        self.systemName = resolvedSystemName
        self.name = resolvedName
        self.defaultColor = defaultColor
        self.activeColor = activeColor
        self.externalIsActive = isActive
        self.action = action
    }
    var body: some View {
        imageView()
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: imageSize, height: imageSize)
            .foregroundColor(
                (isActive || isHovered || (externalIsActive == true)) ? activeColor ?? Color.accentColor : defaultColor ?? Color.secondary
            )
            .onHover { hovering in
                isHovered = hovering
            }
            .onTapGesture {
                isActive = true
                action()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                    isActive = false
                }
            }
    }
    private func imageView() -> Image {
        let baseName = currentImageName()
        // Check if systemName is nil or not, and use the appropriate initializer
        if systemName != nil {
            return Image(systemName: baseName)
        } else {
            return Image(baseName)
        }
    }
    private func currentImageName() -> String {
        let baseName = systemName ?? name ?? ""
        return (isActive || (externalIsActive == true)) ? baseName + ".fill" : baseName
    }
}
