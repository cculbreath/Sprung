import SwiftUI

/// A toast message configuration
struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let style: Style
    let duration: TimeInterval

    enum Style {
        case success
        case error
        case info

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .success: return .green
            case .error: return .red
            case .info: return .blue
            }
        }
    }

    static func success(_ message: String) -> Toast {
        Toast(message: message, style: .success, duration: 3.0)
    }

    static func error(_ message: String) -> Toast {
        Toast(message: message, style: .error, duration: 5.0)
    }

    static func info(_ message: String) -> Toast {
        Toast(message: message, style: .info, duration: 3.0)
    }
}

/// Manages toast display across the app
@MainActor @Observable
final class ToastManager {
    static let shared = ToastManager()

    private(set) var currentToast: Toast?
    private var dismissTask: Task<Void, Never>?

    func show(_ toast: Toast) {
        dismissTask?.cancel()
        currentToast = toast

        dismissTask = Task {
            try? await Task.sleep(for: .seconds(toast.duration))
            if !Task.isCancelled {
                currentToast = nil
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        currentToast = nil
    }
}

/// Overlay view that displays toasts
struct ToastOverlay: View {
    @State private var manager = ToastManager.shared

    var body: some View {
        Group {
            if let toast = manager.currentToast {
                VStack {
                    Spacer()

                    HStack(spacing: 8) {
                        Image(systemName: toast.style.icon)
                            .foregroundColor(toast.style.color)
                        Text(toast.message)
                            .font(.callout)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.regularMaterial)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                    .padding(.bottom, 20)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: manager.currentToast?.id)
    }
}

/// View modifier to add toast overlay capability
struct ToastOverlayModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            ToastOverlay()
        }
    }
}

extension View {
    /// Add toast overlay capability to this view
    func toastOverlay() -> some View {
        modifier(ToastOverlayModifier())
    }
}
