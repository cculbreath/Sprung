import SwiftUI

struct ImageButton: View {
  let systemName: String?
  let name: String?
  var defaultColor: Color?
  var activeColor: Color?
  let imageSize: CGFloat
  let action: () -> Void

  @State private var isHovered = false
  @State private var isActive = false

  init(
    systemName: String? = nil, name: String? = nil, imageSize: CGFloat = 35,
    defaultColor: Color? = Color.secondary, activeColor: Color? = Color.accentColor,
    action: @escaping () -> Void
  ) {
    // Validation: Ensure either systemName or name is provided, but not both or none
    if (systemName == nil && name == nil) || (systemName != nil && name != nil) {
      fatalError("You must provide either `systemName` or `name`, but not both or none.")
    }
    self.imageSize = imageSize
    self.systemName = systemName
    self.name = name
    self.defaultColor = defaultColor
    self.activeColor = activeColor
    self.action = action
  }

  var body: some View {
    imageView()
      .resizable()
      .aspectRatio(contentMode: .fit)
      .frame(width: imageSize, height: imageSize)
      .foregroundColor(
        (isActive || isHovered) ? activeColor ?? Color.accentColor : defaultColor ?? Color.secondary
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
    return isActive ? baseName + ".fill" : baseName
  }
}
