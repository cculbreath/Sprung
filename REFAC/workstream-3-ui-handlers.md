# Workstream 3: UI Layer & Handler Cleanup

**Owner:** Developer C  
**Estimated Duration:** 3-4 days  
**Priority:** High (open-source readiness)  
**Dependencies:** None (can proceed independently)

---

## Executive Summary

This workstream addresses UI layer code quality issues: splitting large view files, extracting animation constants, fixing the critical force unwrap, removing dead code, and cleaning up handlers. These changes improve maintainability and demonstrate professional code organization for open-source readiness.

---

## Scope & Boundaries

### In Scope
- `/Sprung/Onboarding/Views/OnboardingCompletionReviewSheet.swift`
- `/Sprung/Onboarding/Views/OnboardingInterviewView.swift`
- `/Sprung/Onboarding/Views/Components/ToolPaneTabsView.swift`
- `/Sprung/Onboarding/Views/Components/OnboardingInterviewChatComponents.swift`
- `/Sprung/Onboarding/Models/OnboardingPlaceholders.swift`
- `/Sprung/Onboarding/Handlers/ChatboxHandler.swift`
- `/Sprung/Onboarding/Handlers/SwiftDataSessionPersistenceHandler.swift`
- Animation constants extraction
- Drop zone logic consolidation

### Out of Scope
- Core coordinator refactoring (Workstream 1)
- Services layer changes (Workstream 2)
- Event system changes (coordinated with Workstream 1)

---

## Task Breakdown

### Task 3.1: Fix Critical Force Unwrap
**Effort:** 5 minutes  
**Priority:** P0 - Critical (crash risk)

**File:** `Views/Components/ToolPaneTabsView.swift` (Line 121)

**Current Code:**
```swift
let experiences = coordinator.ui.skeletonTimeline?["experiences"].array
return experiences?.isEmpty == false ? experiences!.count : 0
```

**Problem:** Force unwrap (`!`) after optional check can crash if `experiences` becomes nil between the check and unwrap.

**Fix:**
```swift
// Option A: Simple fix
return coordinator.ui.skeletonTimeline?["experiences"].array?.count ?? 0

// Option B: More explicit (if additional logic needed later)
guard let experiences = coordinator.ui.skeletonTimeline?["experiences"].array else {
    return 0
}
return experiences.count
```

**Apply fix immediately** - this is a 5-minute change that prevents crashes.

---

### Task 3.2: Split OnboardingCompletionReviewSheet.swift
**Effort:** 3-4 hours  
**Priority:** P0 - Critical (1096 lines with 4 embedded types)

**File:** `Views/OnboardingCompletionReviewSheet.swift`

**Current Structure:**
- Main `OnboardingCompletionReviewSheet` view (~400 lines)
- `CompletionKnowledgeCardsTab` private struct (~270 lines)
- `WritingContextBrowserTab` private struct (~200 lines)
- `ExperienceDefaultsBrowserTab` private struct (~290 lines)
- Helper functions and extensions

**Target Structure:**
```
Views/CompletionReview/
├── OnboardingCompletionReviewSheet.swift     (~400 lines)
├── CompletionKnowledgeCardsTab.swift         (~270 lines)
├── WritingContextBrowserTab.swift            (~200 lines)
└── ExperienceDefaultsBrowserTab.swift        (~290 lines)
```

#### Step 1: Create Directory
```bash
mkdir -p Sprung/Onboarding/Views/CompletionReview
```

#### Step 2: Extract CompletionKnowledgeCardsTab
```swift
// Views/CompletionReview/CompletionKnowledgeCardsTab.swift
import SwiftUI
import SwiftyJSON

/// Tab view for reviewing and editing knowledge cards
/// Displayed in the completion review sheet
struct CompletionKnowledgeCardsTab: View {
    @Bindable var coordinator: OnboardingInterviewCoordinator
    @State private var selectedCard: KnowledgeCard?
    @State private var isEditingCard = false
    // ... other state
    
    var body: some View {
        // Extract body from OnboardingCompletionReviewSheet
    }
    
    // MARK: - Subviews
    
    private var cardList: some View {
        // ...
    }
    
    private var cardEditor: some View {
        // ...
    }
}

#Preview {
    CompletionKnowledgeCardsTab(coordinator: .preview)
}
```

#### Step 3: Extract WritingContextBrowserTab
```swift
// Views/CompletionReview/WritingContextBrowserTab.swift
import SwiftUI

/// Tab for browsing and reviewing writing context samples
struct WritingContextBrowserTab: View {
    @Bindable var coordinator: OnboardingInterviewCoordinator
    // ... state
    
    var body: some View {
        // Extract implementation
    }
}
```

#### Step 4: Extract ExperienceDefaultsBrowserTab
```swift
// Views/CompletionReview/ExperienceDefaultsBrowserTab.swift
import SwiftUI

/// Tab for reviewing experience defaults and section configuration
struct ExperienceDefaultsBrowserTab: View {
    @Bindable var coordinator: OnboardingInterviewCoordinator
    // ... state
    
    var body: some View {
        // Extract implementation
    }
}
```

#### Step 5: Update Main Sheet
```swift
// Views/CompletionReview/OnboardingCompletionReviewSheet.swift
import SwiftUI

/// Main completion review sheet with tabbed interface
struct OnboardingCompletionReviewSheet: View {
    @Bindable var coordinator: OnboardingInterviewCoordinator
    @State private var selectedTab: CompletionTab = .knowledgeCards
    
    enum CompletionTab: String, CaseIterable {
        case knowledgeCards = "Knowledge Cards"
        case writingContext = "Writing Context"
        case experienceDefaults = "Experience Defaults"
    }
    
    var body: some View {
        VStack {
            tabPicker
            
            switch selectedTab {
            case .knowledgeCards:
                CompletionKnowledgeCardsTab(coordinator: coordinator)
            case .writingContext:
                WritingContextBrowserTab(coordinator: coordinator)
            case .experienceDefaults:
                ExperienceDefaultsBrowserTab(coordinator: coordinator)
            }
        }
    }
    
    private var tabPicker: some View {
        Picker("Tab", selection: $selectedTab) {
            ForEach(CompletionTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }
}
```

---

### Task 3.3: Create Animation Constants Namespace
**Effort:** 2 hours  
**Priority:** P1 - High

**Problem:** Magic numbers scattered across views:
```swift
// OnboardingInterviewView.swift
withAnimation(.spring(response: 0.7, dampingFraction: 0.68)) { windowAppeared = true }
withAnimation(.spring(response: 0.55, dampingFraction: 0.72).delay(0.14)) { progressAppeared = true }
withAnimation(.spring(response: 0.8, dampingFraction: 0.62).delay(0.26)) { cardAppeared = true }
withAnimation(.spring(response: 0.6, dampingFraction: 0.72).delay(0.38)) { bottomBarAppeared = true }
```

**New File:** `Views/Shared/OnboardingAnimations.swift`

```swift
import SwiftUI

/// Centralized animation constants for consistent motion design
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
    }
    
    // MARK: - Chat Animations
    
    enum Chat {
        static let messageAppear = Animation.spring(response: 0.4, dampingFraction: 0.75)
        static let typingIndicator = Animation.easeInOut(duration: 0.6).repeatForever()
        static let scrollToBottom = Animation.spring(response: 0.5, dampingFraction: 0.85)
    }
    
    // MARK: - Tool Pane Animations
    
    enum ToolPane {
        static let tabSwitch = Animation.spring(response: 0.35, dampingFraction: 0.8)
        static let contentReveal = Animation.spring(response: 0.5, dampingFraction: 0.75)
    }
    
    // MARK: - Drop Zone Animations
    
    enum DropZone {
        static let activate = Animation.spring(response: 0.3, dampingFraction: 0.7)
        static let deactivate = Animation.spring(response: 0.4, dampingFraction: 0.8)
        static let pulse = Animation.easeInOut(duration: 1.0).repeatForever()
    }
}

// MARK: - View Extension for Accessibility

extension View {
    /// Apply animation only if reduce motion is not enabled
    func animateUnlessReduceMotion(
        _ animation: Animation,
        value: some Equatable
    ) -> some View {
        self.modifier(AccessibleAnimationModifier(animation: animation, value: value))
    }
}

private struct AccessibleAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V
    
    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.animation(animation, value: value)
        }
    }
}
```

**Update OnboardingInterviewView.swift:**
```swift
// Before:
withAnimation(.spring(response: 0.7, dampingFraction: 0.68)) { windowAppeared = true }
withAnimation(.spring(response: 0.55, dampingFraction: 0.72).delay(0.14)) { progressAppeared = true }

// After:
withAnimation(OnboardingAnimations.InterviewEntrance.windowSpring) { 
    windowAppeared = true 
}
withAnimation(
    OnboardingAnimations.InterviewEntrance.progressSpring
        .delay(OnboardingAnimations.InterviewEntrance.progressDelay)
) { 
    progressAppeared = true 
}
```

---

### Task 3.4: Consolidate Drop Zone Logic
**Effort:** 2-3 hours  
**Priority:** P2 - Medium

**Duplicated in:**
- `Views/Components/PersistentUploadDropZone.swift`
- `Views/Components/OnboardingInterviewUploadRequestCard.swift`

**New File:** `Views/Shared/DropZoneConfiguration.swift`

```swift
import SwiftUI
import UniformTypeIdentifiers

/// Reusable drop zone configuration and validation
struct DropZoneConfiguration {
    /// Allowed file types for dropping
    let allowedTypes: [UTType]
    
    /// Maximum file size in bytes (nil for no limit)
    let maxFileSize: Int?
    
    /// Maximum number of files (nil for no limit)
    let maxFiles: Int?
    
    /// Custom validation closure
    let customValidator: ((URL) -> Bool)?
    
    // MARK: - Preset Configurations
    
    /// Standard document upload configuration
    static let documents = DropZoneConfiguration(
        allowedTypes: [.pdf, .plainText, .rtf, .html],
        maxFileSize: 50_000_000, // 50MB
        maxFiles: 10,
        customValidator: nil
    )
    
    /// Image upload configuration
    static let images = DropZoneConfiguration(
        allowedTypes: [.image, .jpeg, .png, .heic],
        maxFileSize: 20_000_000, // 20MB
        maxFiles: 5,
        customValidator: nil
    )
    
    /// All supported artifacts
    static let allArtifacts = DropZoneConfiguration(
        allowedTypes: [.pdf, .plainText, .rtf, .image, .jpeg, .png],
        maxFileSize: 50_000_000,
        maxFiles: 20,
        customValidator: nil
    )
    
    // MARK: - Validation
    
    /// Validate a dropped URL against this configuration
    func validate(_ url: URL) -> DropValidationResult {
        // Check file type
        guard let uti = UTType(filenameExtension: url.pathExtension),
              allowedTypes.contains(where: { uti.conforms(to: $0) }) else {
            return .failure(.unsupportedType(url.pathExtension))
        }
        
        // Check file size
        if let maxSize = maxFileSize {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let size = attributes[.size] as? Int ?? 0
                if size > maxSize {
                    return .failure(.fileTooLarge(size, maxSize))
                }
            } catch {
                return .failure(.accessError(error))
            }
        }
        
        // Custom validation
        if let validator = customValidator, !validator(url) {
            return .failure(.customValidationFailed)
        }
        
        return .success
    }
    
    /// Validate multiple URLs
    func validate(_ urls: [URL]) -> [URL: DropValidationResult] {
        var results: [URL: DropValidationResult] = [:]
        
        // Check max files
        if let maxFiles, urls.count > maxFiles {
            // Mark excess files as rejected
            for (index, url) in urls.enumerated() {
                if index >= maxFiles {
                    results[url] = .failure(.tooManyFiles(urls.count, maxFiles))
                } else {
                    results[url] = validate(url)
                }
            }
        } else {
            for url in urls {
                results[url] = validate(url)
            }
        }
        
        return results
    }
}

enum DropValidationResult {
    case success
    case failure(DropValidationError)
    
    var isValid: Bool {
        if case .success = self { return true }
        return false
    }
}

enum DropValidationError: LocalizedError {
    case unsupportedType(String)
    case fileTooLarge(Int, Int)
    case tooManyFiles(Int, Int)
    case accessError(Error)
    case customValidationFailed
    
    var errorDescription: String? {
        switch self {
        case .unsupportedType(let ext):
            return "File type '.\(ext)' is not supported"
        case .fileTooLarge(let size, let max):
            let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            let maxStr = ByteCountFormatter.string(fromByteCount: Int64(max), countStyle: .file)
            return "File size (\(sizeStr)) exceeds maximum (\(maxStr))"
        case .tooManyFiles(let count, let max):
            return "Too many files (\(count)). Maximum is \(max)"
        case .accessError(let error):
            return "Cannot access file: \(error.localizedDescription)"
        case .customValidationFailed:
            return "File does not meet requirements"
        }
    }
}
```

**New File:** `Views/Shared/DropZoneView.swift`

```swift
import SwiftUI

/// Reusable drop zone view with drag state visualization
struct DropZoneView<Content: View>: View {
    let configuration: DropZoneConfiguration
    let onDrop: ([URL]) -> Void
    @ViewBuilder let content: (Bool) -> Content
    
    @State private var isTargeted = false
    
    var body: some View {
        content(isTargeted)
            .onDrop(of: configuration.allowedTypes, isTargeted: $isTargeted) { providers in
                handleDrop(providers)
            }
            .animation(OnboardingAnimations.DropZone.activate, value: isTargeted)
    }
    
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        // Implementation using configuration for validation
        var urls: [URL] = []
        
        // Load URLs from providers
        // Validate using configuration
        // Call onDrop with valid URLs
        
        return !urls.isEmpty
    }
}

// MARK: - Drop Zone Styles

extension DropZoneView {
    /// Standard dashed border style
    func dashedBorderStyle() -> some View {
        self.modifier(DashedBorderDropStyle())
    }
    
    /// Subtle highlight style
    func highlightStyle() -> some View {
        self.modifier(HighlightDropStyle())
    }
}

private struct DashedBorderDropStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                    )
                    .foregroundColor(.secondary.opacity(0.5))
            )
    }
}
```

**Update Existing Views:**
```swift
// PersistentUploadDropZone.swift - simplified
struct PersistentUploadDropZone: View {
    @Bindable var coordinator: OnboardingInterviewCoordinator
    
    var body: some View {
        DropZoneView(
            configuration: .allArtifacts,
            onDrop: handleFileDrop
        ) { isTargeted in
            dropZoneContent(isTargeted: isTargeted)
        }
        .dashedBorderStyle()
    }
    
    private func dropZoneContent(isTargeted: Bool) -> some View {
        // Simplified content
    }
    
    private func handleFileDrop(_ urls: [URL]) {
        // Delegate to coordinator
    }
}
```

---

### Task 3.5: Evaluate ChatboxHandler Purpose
**Effort:** 1-2 hours  
**Priority:** P1 - High

**File:** `Handlers/ChatboxHandler.swift` (53 lines)

**Current Implementation:**
```swift
private func handleLLMEvent(_ event: OnboardingEvent) async {
    switch event {
    case .errorOccurred(let message):
        Logger.error("LLM error: \(message)", category: .ai)
    default:
        break
    }
}
```

**Problem:** Handler does almost nothing. The spec suggests it should "Display error messages and status updates" but this isn't implemented.

**Options:**

#### Option A: Implement Intended Functionality
```swift
@MainActor @Observable
final class ChatboxHandler {
    weak var coordinator: OnboardingInterviewCoordinator?
    
    // Visible state for UI
    private(set) var currentStatus: ChatStatus = .idle
    private(set) var lastError: ChatError?
    
    enum ChatStatus: Equatable {
        case idle
        case processing(message: String)
        case error(message: String)
        case success(message: String)
    }
    
    struct ChatError: Identifiable {
        let id = UUID()
        let message: String
        let timestamp: Date
        let isRecoverable: Bool
    }
    
    private func handleLLMEvent(_ event: OnboardingEvent) async {
        switch event {
        case .processingStateChanged(let isProcessing, let statusMessage):
            if isProcessing {
                currentStatus = .processing(message: statusMessage ?? "Processing...")
            } else {
                currentStatus = .idle
            }
            
        case .errorOccurred(let message):
            currentStatus = .error(message: message)
            lastError = ChatError(
                message: message,
                timestamp: Date(),
                isRecoverable: true
            )
            Logger.error("LLM error: \(message)", category: .ai)
            
        case .streamingMessageCompleted:
            currentStatus = .success(message: "Response complete")
            
        default:
            break
        }
    }
    
    func clearError() {
        lastError = nil
        if case .error = currentStatus {
            currentStatus = .idle
        }
    }
}
```

#### Option B: Remove as Dead Code
If responsibilities have moved elsewhere:
```swift
// 1. Check if any UI observes ChatboxHandler
grep -r "chatboxHandler" --include="*.swift" .

// 2. If not observed, mark deprecated
@available(*, deprecated, message: "Responsibilities moved to OnboardingUIState")
final class ChatboxHandler { ... }

// 3. Remove after confirming no impact
```

**Recommendation:** Check with project documentation. If spec still says it should display status, implement Option A. Otherwise, Option B.

---

### Task 3.6: Remove Unused Back Button Logic
**Effort:** 15 minutes  
**Priority:** P3 - Low

**File:** `Views/OnboardingInterviewView.swift` (Line 266)

**Current Code:**
```swift
func shouldShowBackButton(for _: OnboardingWizardStep) -> Bool {
    // Go Back functionality was never implemented - hide the button
    false
}
```

**Action:**
1. Search for usages: `grep -r "shouldShowBackButton" .`
2. If only called from this file and always returns false, simplify:

```swift
// Option A: Remove function entirely, replace call sites with `false`

// Option B: Document intent to implement later
/// Returns whether back navigation is available for the given step
/// - Note: Back navigation is not yet implemented. Returns false.
/// - TODO: Implement back navigation (Issue #XXX)
func shouldShowBackButton(for step: OnboardingWizardStep) -> Bool {
    // Future: return step != .initial
    return false
}
```

---

### Task 3.7: Split OnboardingPlaceholders.swift
**Effort:** 2 hours  
**Priority:** P2 - Medium

**File:** `Models/OnboardingPlaceholders.swift` (320 lines, 14+ types)

**Current Types:**
- OnboardingMessage
- OnboardingChoicePrompt
- OnboardingWizardStep
- OnboardingUploadRequest
- OnboardingValidationPrompt
- PendingDocumentExtraction
- OnboardingPendingExtraction
- ... and more

**Target Structure:**
```
Models/UIModels/
├── OnboardingMessage.swift           (~80 lines)
├── OnboardingPrompts.swift           (~60 lines)  # ChoicePrompt + ValidationPrompt
├── OnboardingWizardStep.swift        (~40 lines)
├── OnboardingUploadModels.swift      (~80 lines)  # UploadRequest + PendingExtraction
└── OnboardingPendingOperations.swift (~60 lines)  # PendingDocumentExtraction etc.
```

#### OnboardingMessage.swift
```swift
import Foundation
import SwiftyJSON

/// Represents a message in the onboarding chat interface
struct OnboardingMessage: Identifiable, Equatable, Sendable {
    let id: String
    let role: MessageRole
    var content: String
    let timestamp: Date
    var toolCalls: [ToolCallInfo]
    
    enum MessageRole: String, Sendable {
        case user
        case assistant
        case system
    }
    
    struct ToolCallInfo: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        let arguments: JSON
        var result: JSON?
        var status: ToolStatus
        
        enum ToolStatus: Equatable, Sendable {
            case pending
            case running
            case completed
            case failed(String)
        }
    }
    
    // Mutation methods
    mutating func setToolResult(_ result: JSON, for toolCallId: String) {
        guard let index = toolCalls.firstIndex(where: { $0.id == toolCallId }) else { return }
        toolCalls[index].result = result
        toolCalls[index].status = .completed
    }
}
```

---

### Task 3.8: Add User Feedback for Export Operations
**Effort:** 1-2 hours  
**Priority:** P2 - Medium

**Problem:** Export operations log success/failure but don't inform the user.

**Files affected:**
- `Views/EventDumpView.swift`
- Other export views

**Solution - Create Toast/Alert System:**

```swift
// Views/Shared/ToastView.swift
import SwiftUI

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
}

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

struct ToastOverlay: View {
    @State private var manager = ToastManager.shared
    
    var body: some View {
        if let toast = manager.currentToast {
            VStack {
                Spacer()
                
                HStack {
                    Image(systemName: toast.style.icon)
                        .foregroundColor(toast.style.color)
                    Text(toast.message)
                        .font(.callout)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial)
                .clipShape(Capsule())
                .shadow(radius: 4)
                .padding(.bottom, 20)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: manager.currentToast)
        }
    }
}
```

**Update Export Functions:**
```swift
// EventDumpView.swift
private func exportEventDump() {
    // ... save panel code ...
    
    do {
        try output.write(to: url, atomically: true, encoding: .utf8)
        Logger.info("Event dump exported to: \(url.path)", category: .general)
        ToastManager.shared.show(.success("Event dump exported successfully"))
    } catch {
        Logger.error("Failed to export: \(error.localizedDescription)", category: .general)
        ToastManager.shared.show(.error("Export failed: \(error.localizedDescription)"))
    }
}
```

---

## Verification Checklist

### Build Verification
- [ ] `swift build` succeeds
- [ ] All SwiftUI previews render
- [ ] No new warnings
- [ ] UI tests pass

### Visual Verification
- [ ] Animations feel consistent
- [ ] Drop zones work correctly
- [ ] Toast notifications appear
- [ ] No layout regressions

### Code Quality
- [ ] No files > 500 lines
- [ ] No force unwraps
- [ ] Animation constants extracted
- [ ] Drop zone logic consolidated

---

## Rollback Plan

1. **Per-file rollback:** Each extraction is in its own PR
2. **Animation constants:** Can be reverted to inline values
3. **Toast system:** Optional - can be removed without breaking functionality

---

## Communication Points

### With Workstream 1 (Core)
- Coordinate if ChatboxHandler changes affect event handling
- Notify about model file relocations

### With Workstream 2 (Services)
- Share OnboardingPlaceholders split plan (both may touch models)

---

## Definition of Done

- [ ] Force unwrap fixed
- [ ] OnboardingCompletionReviewSheet split into 4 files
- [ ] Animation constants extracted
- [ ] Drop zone logic consolidated
- [ ] ChatboxHandler evaluated/fixed
- [ ] Export feedback implemented
- [ ] Code reviewed
- [ ] No visual regressions
