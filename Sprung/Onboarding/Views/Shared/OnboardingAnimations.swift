import SwiftUI

/// Centralized animation constants for consistent motion design in the onboarding interview
enum OnboardingAnimations {

    // MARK: - Interview View Entrance Sequence

    enum InterviewEntrance {
        static let windowSpring = Animation.spring(response: 0.7, dampingFraction: 0.68)
        static let progressSpring = Animation.spring(response: 0.55, dampingFraction: 0.72)
        static let cardSpring = Animation.spring(response: 0.8, dampingFraction: 0.62)
        static let bottomBarSpring = Animation.spring(response: 0.6, dampingFraction: 0.72)

        static let progressDelay: Double = 0.14
        static let cardDelay: Double = 0.26
        static let bottomBarDelay: Double = 0.38
    }

    // MARK: - Card Animations

    enum Card {
        static let stepTransition = Animation.spring(response: 0.4, dampingFraction: 0.82)
    }

    // MARK: - Tool Pane Animations

    enum ToolPane {
        static let tabSwitch = Animation.easeInOut(duration: 0.15)
        static let tabAutoSwitch = Animation.easeInOut(duration: 0.2)
    }

    // MARK: - Status Bar Animations

    enum StatusBar {
        static let stateChange = Animation.easeInOut(duration: 0.2)
        static let stepChange = Animation.easeInOut(duration: 0.25)
    }
}
