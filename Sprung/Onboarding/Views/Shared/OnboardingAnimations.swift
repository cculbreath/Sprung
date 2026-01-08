import SwiftUI

/// Centralized animation constants for consistent motion design in the onboarding interview
enum OnboardingAnimations {

    // MARK: - Standard Springs

    /// Standard entrance spring - used for primary elements
    static let entranceSpring = Animation.spring(response: 0.6, dampingFraction: 0.7)

    /// Quick response spring - used for immediate feedback
    static let quickSpring = Animation.spring(response: 0.4, dampingFraction: 0.75)

    /// Gentle spring - used for subtle state changes
    static let gentleSpring = Animation.spring(response: 0.8, dampingFraction: 0.8)

    // MARK: - Interview View Entrance Sequence

    enum InterviewEntrance {
        static let windowSpring = Animation.spring(response: 0.7, dampingFraction: 0.68)
        static let progressSpring = Animation.spring(response: 0.55, dampingFraction: 0.72)
        static let cardSpring = Animation.spring(response: 0.8, dampingFraction: 0.62)
        static let bottomBarSpring = Animation.spring(response: 0.6, dampingFraction: 0.72)

        static let windowDelay: Double = 0
        static let progressDelay: Double = 0.14
        static let cardDelay: Double = 0.26
        static let bottomBarDelay: Double = 0.38

        /// Total duration of entrance sequence
        static let totalDuration: Double = bottomBarDelay + 0.6
    }

    // MARK: - Card Animations

    enum Card {
        static let expand = Animation.spring(response: 0.5, dampingFraction: 0.7)
        static let collapse = Animation.spring(response: 0.4, dampingFraction: 0.8)
        static let highlight = Animation.easeInOut(duration: 0.3)
        static let stepTransition = Animation.spring(response: 0.4, dampingFraction: 0.82)
    }

    // MARK: - Chat Animations

    enum Chat {
        static let messageAppear = Animation.spring(response: 0.4, dampingFraction: 0.75)
        static let scrollToBottom = Animation.spring(response: 0.5, dampingFraction: 0.85)
    }

    // MARK: - Tool Pane Animations

    enum ToolPane {
        static let tabSwitch = Animation.easeInOut(duration: 0.15)
        static let contentReveal = Animation.spring(response: 0.5, dampingFraction: 0.75)
        static let tabAutoSwitch = Animation.easeInOut(duration: 0.2)
    }

    // MARK: - Status Bar Animations

    enum StatusBar {
        static let stateChange = Animation.easeInOut(duration: 0.2)
        static let stepChange = Animation.easeInOut(duration: 0.25)
    }
}
