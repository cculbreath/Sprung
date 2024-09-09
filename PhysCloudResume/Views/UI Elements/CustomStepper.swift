import SwiftUI
struct Colors  {
  static let ltGray = Color(red: 245 / 255, green: 245 / 255, blue: 245 / 255)
  static let midLtGray = Color(red: 235 / 255, green: 235 / 255, blue: 235 / 255)
  static let midGray = Color(red: 225 / 255, green: 225 / 255, blue: 225 / 255)

}
struct CustomStepper: View {
  @Binding var value: Int
  @State var isPlusHovering: Bool = false
  @State var isMinusHovering: Bool = false
  var range: ClosedRange<Int>
  var body: some View {
    HStack(spacing: 0) {
      // Decrement button (-)
      Button(action: {
        if value > range.lowerBound {
          value -= 1
        }
      }) {
        Text("–")
          .frame(width: 24, height: 24)
          .background(isMinusHovering ? Colors.ltGray : Color.clear )
          .foregroundColor(.primary)  // Text color for button
      }
      .buttonStyle(PlainButtonStyle()).onHover{hover in isMinusHovering = hover}  // Disable default button style

      // Divider between the buttons and value
      Divider()
        .frame(height: 22)
        .background(Colors.midGray)

      // Value display
      Text("\(value)")
        .frame(width: 24, height: 24)
        .background(Color.clear)
        .foregroundColor(.primary)  // Text color for value

      // Divider between value and increment button
      Divider()
        .frame(height: 22)
        .background(Colors.midGray)

      // Increment button (+)
      Button(action: {
        if value < range.upperBound {
          value += 1
        }
      }) {
        Text("+")
          .frame(width: 24, height: 24)
          .background(isPlusHovering ? Colors.ltGray : Color.clear)
          .foregroundColor(.primary)  // Text color for button
      }
      .buttonStyle(PlainButtonStyle())
      .onHover{hovering in
        isPlusHovering = hovering}// Disable default button style
    }
    .font(.body)  // Set the font size
    .cornerRadius(8)  // Rounded corners
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(Colors.ltGray, lineWidth: 1)
    )  // Add border around the entire stepper
    .background(Colors.midLtGray)  // Use tertiary background color to match design
    .clipShape(RoundedRectangle(cornerRadius: 8))  // Clip the shape to match the rounded corners
  }
}



