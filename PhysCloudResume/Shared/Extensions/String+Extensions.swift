// PhysCloudResume/Shared/Extensions/String+Extensions.swift

import Foundation
import SwiftUI

extension String {
}

extension View {
    /// Conditionally applies a transformation to a view
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
