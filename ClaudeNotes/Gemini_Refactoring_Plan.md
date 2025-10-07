# Gemini Refactoring Plan

This document outlines a systematic plan to refactor the PhysCloudResume application based on the findings of the architectural review. The primary goals are to improve modularity, adopt modern Swift/SwiftUI best practices, enhance testability, and create a more reliable and maintainable codebase.

## Issue Summary

The architectural review identified several recurring, high-level issues:

1.  **Tight Coupling & God Objects:** Core components like `AppState`, `LLMService`, and `NativePDFGenerator` have too many responsibilities. Views and services are tightly coupled to global singletons (`AppState`, `JobAppStore`) and concrete implementations, hindering modularity and testing.
2.  **Mixing of Concerns:** The Single Responsibility Principle is frequently violated.
    *   **Models with Presentation Logic:** Data models (`JobApp`, `TreeNode`) contain UI-specific code, such as color mapping, formatted strings, and even `@ViewBuilder` extensions.
    *   **Views with Business Logic:** SwiftUI views (`SidebarView`, `NodeLeafView`, `ReorderableLeafRow`) perform direct data manipulation, persistence, and complex business logic instead of delegating to a ViewModel or service layer.
    *   **Services with UI Logic:** Service-layer components (`ResumeExportService`) are responsible for presenting UI alerts and panels.
3.  **Outdated & Inconsistent Practices:**
    *   **Custom JSON Handling:** The codebase relies on custom, brittle JSON parsers (`JSONParser.swift`, `JsonToTree.swift`) and manual string building (`TreeToJson.swift`) instead of Swift's robust, type-safe `Codable` protocol.
    *   **Legacy UI Communication:** `NotificationCenter` is used for several communication patterns. While its use for decoupling global UI (menus, toolbars) from specific handlers is a functional pattern, it lacks type safety and makes the flow of control difficult to trace. Furthermore, its use for managing sheet presentation and triggering data refreshes are clear anti-patterns in modern SwiftUI, where direct state binding and observable objects are superior. A long-term goal should be to migrate even the menu/toolbar triggers to a centralized, type-safe command or action handler for better maintainability.
    *   **Brittle Web Scraping:** Parsing logic relies on hardcoded, fragile selectors and string manipulation, making it susceptible to breaking when source websites change.
    *   **Poor Error Handling:** A common pattern of silent error handling (`catch {}`) and using `fatalError` for control flow obscures bugs and can lead to unexpected crashes.
4.  **Poor Dependency Management:**
    *   The singleton pattern is overused, leading to hidden dependencies and global state.
    *   There is a lack of protocol-oriented design and dependency injection, making components difficult to test in isolation and replace.

## Refactoring Roadmap

This roadmap is divided into four phases, designed to be executed sequentially. Each phase builds a foundation for the next, starting with the most critical architectural flaws.

### Phase 1: Foundational Cleanup & Modernization

**Goal:** Replace architectural anti-patterns with standard, modern Swift practices to stabilize the data layer.

1.  **Eradicate Custom JSON Parsing:**
    *   **Action:** Replace all usages of `JSONParser`, `JsonToTree`, and `TreeToJson` with the `Codable` protocol.
    *   **Rationale:** Swift's native `Codable` is type-safe, highly optimized, and eliminates vast amounts of complex, brittle, and hard-to-maintain custom parsing code. This is the highest-priority task.
    *   **Steps:**
        1.  Define `Codable` structs that model the JSON structures for resumes and API responses.
        2.  Refactor `JsonToTree` to use `JSONDecoder` to decode JSON into these `Codable` structs, then transform them into the `TreeNode` hierarchy.
        3.  Refactor `TreeToJson` to transform the `TreeNode` hierarchy into `Codable` structs and then use `JSONEncoder` to produce the JSON string.
        4.  Delete `JSONParser.swift`, `JSONValue.swift`, and the custom parsing logic within `JsonToTree.swift` and `TreeToJson.swift`.

2.  **Standardize Error Handling:**
    *   **Action:** Eliminate all silent `catch {}` blocks and `fatalError` calls used for control flow.
    *   **Rationale:** Silent errors hide bugs. A consistent error handling strategy using Swift's `async throws` pattern provides clear, actionable feedback when operations fail.
    *   **Steps:**
        1.  Search the codebase for `catch {}` and `fatalError`.
        2.  Replace them with specific, logged errors or `throw` the original error to be handled by the caller.
        3.  Ensure network and persistence layers consistently use `async throws` for failable operations.

3.  **Remove Obsolete Code:**
    *   **Action:** Delete unused and empty files.
    *   **Rationale:** Dead code and empty files add clutter and confusion.
    *   **Steps:**
        1.  Delete `BrightDataParse.swift`.
        2.  Delete `SidebarToolbarView.swift`.

### Phase 2: Service Layer Refactoring & Decoupling

**Goal:** Break down God Objects and separate concerns within the service, utility, and networking layers.

1.  **Decompose `AppState`:**
    *   **Action:** Break the `AppState` singleton into smaller, focused objects.
    *   **Rationale:** Decomposing the God Object improves modularity and clarifies dependencies.
    *   **Steps:**
        1.  Create a `SessionState` class to manage UI state like `selectedJobApp`.
        2.  Create an `AIServiceLocator` to hold instances of AI-related services.
        3.  Plan to inject these smaller objects into the SwiftUI environment instead of the monolithic `AppState`.

2.  **Refactor AI & Utility Services:**
    *   **Action:** Convert singletons (`LLMService`, `OpenRouterService`, `KeychainHelper`, `Logger`) into regular classes and use dependency injection. Abstract their functionality behind protocols.
    *   **Rationale:** This is crucial for testability and flexibility. It allows for mock implementations in tests and swapping out concrete types (e.g., a different keychain service) in the future.
    *   **Steps:**
        1.  Define protocols (e.g., `AIModelProviding`, `KeychainServicing`).
        2.  Make the existing services conform to these protocols.
        3.  Remove the `.shared` static instances.
        4.  Inject dependencies through initializers (e.g., `LLMService(modelProvider: ...)`).

3.  **Isolate and Refactor Complex Services:**
    *   **Action:** Decompose `NativePDFGenerator` and extract `HTMLFetcher` from its `JobApp` extension.
    *   **Rationale:** Large, multi-responsibility services are difficult to maintain. Generic utilities should not be tied to specific data models.
    *   **Steps:**
        1.  Break `NativePDFGenerator` into smaller services: `TemplateLoader`, `TemplateRenderer` (using `Mustache`), `ResumeDataTransformer` (using `Codable`), and `PDFExporter` (wrapping `WKWebView`).
        2.  Create a standalone `HTMLFetcher` service. It should be initialized with dependencies like a `CookieManager` (abstracted via protocol) instead of using the static `CloudflareCookieManager`.

4.  **Refactor Web Scrapers:**
    *   **Action:** Decompose the large parsing methods in `IndeedJobScrape`, `AppleJobScrape`, etc. Decouple them from `JobAppStore`.
    *   **Rationale:** The current scraping logic is brittle and mixes parsing, data mapping, and persistence.
    *   **Steps:**
        1.  For each scraper, create separate components: an `Extractor` (to get raw data from HTML/JSON), a `Mapper` (to turn raw data into a `Codable` DTO), and a `Service` (to orchestrate and handle business logic like duplicate checks).
        2.  The final output of the scraping process should be a `JobApp` object, not a direct call to `JobAppStore.addJobApp`. The calling context should handle persistence.

### Phase 3: Data Model & Store Refactoring

**Goal:** Purify data models by removing non-essential logic and clarify the role of data stores.

1.  **Purify Data Models:**
    *   **Action:** Remove all presentation logic (colors, formatted strings, `@ViewBuilder` extensions) from `JobApp` and `TreeNode` model files.
    *   **Rationale:** Models should represent data, not how it's displayed. This separation is fundamental to a clean architecture.
    *   **Steps:**
        1.  Delete `JobApp+Color.swift` and `JobApp+StatusTag.swift`. This logic will be moved to a ViewModel.
        2.  Move utility methods like `jobListingString` and `replaceUUIDsWithLetterNames` out of the `JobApp` model and into a ViewModel or formatter.

2.  **Refactor `JobAppStore` and `JobAppForm`:**
    *   **Action:** Simplify `JobAppStore` to be a pure data manager. Eliminate the redundant `JobAppForm` class.
    *   **Rationale:** `JobAppStore` mixes data management with UI state. Since SwiftData's `@Model` is already `@Observable`, a separate form-specific class is unnecessary boilerplate.
    *   **Steps:**
        1.  Remove UI state like `selectedApp` and `form` from `JobAppStore`. This state should be managed by a ViewModel.
        2.  Delete `JobAppForm.swift`.
        3.  Refactor editing views to bind directly to `@Model` properties of a `JobApp` instance.

### Phase 4: UI Layer Refactoring (MVVM Adoption)

**Goal:** Fully implement the Model-View-ViewModel (MVVM) pattern to create a clean separation between UI and business logic.

1.  **Introduce ViewModels:**
    *   **Action:** Create ViewModels for all complex views (e.g., `SidebarViewModel`, `ResumeDetailViewModel`, `NodeLeafViewModel`).
    *   **Rationale:** ViewModels act as an intermediary, providing presentation-ready data to the View and handling user interactions, which keeps Views simple and focused on layout and rendering.
    *   **Steps:**
        1.  For a view like `SidebarView`, create `SidebarViewModel`.
        2.  The ViewModel will be injected with the necessary services (`JobAppStore`, `ResumeStore`).
        3.  It will expose `@Published` properties for the view to display (e.g., `filteredJobApps`, `selectedJobApp`) and methods for the view to call (e.g., `deleteJobApp(at:)`).

2.  **Decouple and Simplify Views:**
    *   **Action:** Refactor all views to be "dumb." They should not contain business logic or make direct calls to services or data stores.
    *   **Rationale:** This is the core principle of MVVM. It makes views highly reusable, testable, and easy to reason about.
    *   **Steps:**
        1.  Go through each complex view (`SidebarView`, `NodeLeafView`, `ResumeDetailView`, etc.).
        2.  Move all logic (filtering, data manipulation, persistence calls) into its corresponding ViewModel.
        3.  The view should only bind to the ViewModel's properties and call its methods.

3.  **Generalize UI Components:**
    *   **Action:** Make reusable UI components (`ImageButton`, `CustomTextEditor`, `StatusBadgeView`) more generic.
    *   **Rationale:** Components should not be coupled to specific data models.
    *   **Steps:**
        1.  Modify components to accept simple parameters (e.g., `String`, `Color`, `Bool`, action closures) instead of entire models like `TreeNode`.
        2.  The parent view (or its ViewModel) will be responsible for mapping model state to these simple parameters.

## Best Practice Alignment

*   **Modularity & Single Responsibility Principle (SRP):** The entire roadmap is designed to enforce SRP. Decomposing God Objects (`AppState`, `NativePDFGenerator`) and separating concerns (moving logic from Views to ViewModels, and from Models to formatters) are direct applications of this principle.
*   **Separation of Concerns (SoC):** The adoption of MVVM in Phase 4 is the primary mechanism for achieving a clean SoC between the data layer (Model), business logic (ViewModel), and presentation (View).
*   **Modern Swift/SwiftUI Paradigms:**
    *   **`Codable`:** Replacing custom parsers with `Codable` (Phase 1) is a fundamental shift to a modern, safe, and efficient Swift pattern.
    *   **`async/await` & Structured Concurrency:** Standardizing on `async throws` (Phase 1) aligns with modern Swift concurrency.
    *   **`@Observable`:** Using `@Model` objects directly in forms (Phase 3) and creating `@Observable` ViewModels (Phase 4) leverages the latest SwiftUI data flow mechanisms.
*   **Dependency Injection & Testability:** Moving away from singletons and injecting dependencies via protocols (Phase 2) is a cornerstone of creating testable and maintainable code. Each component can be tested in isolation with mock dependencies.

## Codebase References

To implement this plan, the following files and modules will require significant review and modification.

*   **Phase 1 (Foundational):**
    *   `Shared/Utilities/JSONParser.swift` (To be deleted)
    *   `ResumeTree/Utilities/JsonToTree.swift` (To be refactored with `JSONDecoder`)
    *   `ResumeTree/Utilities/TreeToJson.swift` (To be refactored with `JSONEncoder`)
    *   The entire codebase should be audited for `catch {}` and `fatalError`.

*   **Phase 2 (Services):**
    *   `App/AppState.swift` (To be decomposed)
    *   All files in `AI/Models/Services/` (To be converted from singletons and put behind protocols)
    *   `Shared/Utilities/NativePDFGenerator.swift` (To be decomposed)
    *   `JobApplications/Utilities/HTMLFetcher.swift` (To be created from logic in `JobApp` extension)
    *   All files in `JobApplications/Models/*Scrape.swift` (To be decomposed)

*   **Phase 3 (Models & Stores):**
    *   `JobApplications/Models/JobApp.swift` and its extensions (To be purified of presentation logic)
    *   `ResumeTree/Models/TreeNodeModel.swift` (To be purified and refactored for `Codable` export)
    *   `DataManagers/JobAppStore.swift` (To be simplified)
    *   `JobApplications/Models/JobAppForm.swift` (To be deleted)

*   **Phase 4 (UI):**
    *   `Sidebar/Views/SidebarView.swift` (Requires a `SidebarViewModel`)
    *   `ResumeTree/Views/ResumeDetailView.swift` (Requires a `ResumeDetailViewModel`)
    *   `ResumeTree/Views/NodeLeafView.swift` (Requires a `NodeLeafViewModel`)
    *   `ResumeTree/Views/NodeHeaderView.swift` (To be simplified and driven by a ViewModel)
    *   All files in `Shared/UIComponents/` (To be generalized)
