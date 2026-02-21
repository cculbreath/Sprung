# OnboardingEvents.swift — Refactoring Assessment

**File:** `Sprung/Onboarding/Core/OnboardingEvents.swift`
**Lines:** 842
**Date assessed:** 2026-02-18

---

## 1. Primary Responsibility / Purpose

The file's stated purpose is "event-driven architecture for the onboarding system." In practice it
currently owns **four distinct responsibilities**:

| # | Responsibility | Lines |
|---|----------------|-------|
| A | Supporting types (`ProcessedUploadInfo`, `LLMStatus`) | 11–25 |
| B | All `OnboardingEvent` case definitions and their nested event enums | 27–291 |
| C | `EventTopic` routing enum + `logDescription` helpers on every event type | 293–633 |
| D | `EventCoordinator` actor — the event bus itself | 635–815 |
| E | `OnboardingEventEmitter` protocol | 817–828 |
| F | `TimelineDiff.summary` extension (belongs to `TimelineDiff`'s domain) | 830–841 |

---

## 2. Distinct Logical Sections

### Section A — Supporting Value Types (lines 11–25)
`ProcessedUploadInfo` and `LLMStatus` are small supporting types used as payloads in event cases.
They have no coupling to the bus or to routing logic.

### Section B — Event Definitions (lines 27–291)
The `OnboardingEvent` enum and its ten nested sub-enums (`LLMEvent`, `ProcessingEvent`,
`ToolpaneEvent`, `ArtifactEvent`, `StateEvent`, `PhaseEvent`, `ObjectiveEvent`, `ToolEvent`,
`TimelineEvent`, `SectionCardEvent`, `PublicationCardEvent`). This is the **schema** of all events
the system can express.

### Section C — Routing & Logging (lines 293–633)
`EventTopic` enum, `OnboardingEvent.topic` computed property, and eleven `logDescription`
extensions (one per nested event enum). These are **consumer utilities**: the `EventCoordinator`
uses `topic` for routing; the logger uses `logDescription`. They are independent of the event
schema itself.

### Section D — EventCoordinator Actor (lines 635–815)
The `actor EventCoordinator` implements the publish/subscribe event bus using `AsyncStream`. It
stores subscriber continuations keyed by `EventTopic`, maintains a debug event history with
streaming consolidation, and exposes `stream(topic:)`, `streamAll()`, and `publish(_:)`. This is a
full service implementation, not a type definition.

### Section E — OnboardingEventEmitter Protocol (lines 817–828)
A one-property protocol with a default `emit` implementation. Small, but belongs with
`EventCoordinator` rather than with the event schema.

### Section F — TimelineDiff.summary Extension (lines 830–841)
An extension on `TimelineDiff` (defined in `Sprung/Onboarding/Utilities/TimelineDiff.swift`) that
computes a human-readable summary string. Used only inside `TimelineEvent.logDescription`. It was
placed here to avoid importing a separate file, but it extends a type from a different domain and
adds to `TimelineDiff`'s surface area in a file that `TimelineDiff` consumers would not think to
look.

---

## 3. Single Responsibility Principle Assessment

**The file violates SRP.** Three distinct reasons to change exist:

1. **Adding or removing an event case** — requires editing the event schema (Section B).
2. **Changing the event bus behavior** — routing, buffering, debug history, subscriber lifecycle
   (Section D). None of this has anything to do with what events exist.
3. **Changing how events are described in logs** — `logDescription` implementations on eleven
   enums (Section C). These are formatting utilities; updating a log string should not live beside
   the bus actor.

The `TimelineDiff.summary` extension (Section F) has its own reason to change independent of all
three above.

---

## 4. Is the Length Justified?

No. 842 lines is not justified by the scope of what each piece does.

- The event schema itself (Section B alone) is ~265 lines — a reasonable size for a well-organized
  schema file.
- The `EventCoordinator` actor (Section D) is ~180 lines of real logic and would benefit from
  being independently readable and testable.
- The log description extensions (Section C) add ~340 lines of string-formatting code that crowds
  out the schema.

The file grew because each new event group brought its own `logDescription` extension with it, and
the bus implementation was never separated. The problem is accumulation, not necessity.

---

## 5. Refactoring Plan

### Summary of proposed split

| New File | Lines Moved From | Purpose |
|----------|-----------------|---------|
| `OnboardingEvents.swift` (kept, trimmed) | 1–291, supporting types | Event schema only |
| `OnboardingEventDescriptions.swift` (new) | 293–633 | Routing enum + all logDescription extensions |
| `EventCoordinator.swift` (new) | 635–828 | EventCoordinator actor + OnboardingEventEmitter |
| Move `TimelineDiff.summary` → `TimelineDiff.swift` | 830–841 | Belongs with TimelineDiff |

---

### File 1: `Sprung/Onboarding/Core/OnboardingEvents.swift` (kept, trimmed)

**Purpose:** Sole source of truth for what events exist. Nothing else — no routing, no logging, no
bus.

**Content after trim:**
- File header comment
- `import Foundation`, `@preconcurrency import SwiftyJSON`
- `ProcessedUploadInfo` struct (lines 14–18)
- `LLMStatus` enum (lines 21–25)
- `OnboardingEvent` enum with all case groups (lines 30–65)
- All `extension OnboardingEvent { enum XEvent }` blocks (lines 67–291)

**Approximate new line count:** ~295 lines

**No imports need to change.** The nested event enums reference types defined in other files
(`OnboardingChoicePrompt`, `ToolCall`, `ConversationEntry`, `UsageSource`, `TimelineDiff`,
`OnboardingPendingExtraction`, etc.) — those references already work via the module scope and do
not require explicit imports beyond `Foundation` and `SwiftyJSON`.

---

### File 2: `Sprung/Onboarding/Core/OnboardingEventDescriptions.swift` (new)

**Purpose:** Centralizes all routing and diagnostic string-formatting logic for
`OnboardingEvent`. Keeps `logDescription` implementations out of the schema file.

**Content (move from current file):**
- `// MARK: - Event Topics` section — `EventTopic` enum (lines 293–309)
- `// MARK: - OnboardingEvent Helpers` section — `OnboardingEvent.topic` and
  `OnboardingEvent.logDescription` (lines 311–358)
- `// MARK: - Nested Event Log Descriptions` — all eleven `logDescription` extensions
  (lines 360–633)

**Approximate new line count:** ~275 lines

**Imports needed:**
```swift
import Foundation
@preconcurrency import SwiftyJSON
```
`EventTopic` is referenced by `EventCoordinator`, so it must be defined before or alongside it.
Since Swift compiles the whole module together, defining `EventTopic` in this file is fine — both
`OnboardingEvents.swift` (for the `topic` property) and `EventCoordinator.swift` can reference it
without an explicit import.

**Note on `ConversationEntry` usage in `LLMEvent.logDescription`:** The log description accesses
`entry.isUser` and `entry.id`. These are module-visible properties on the type defined in
`ConversationLog.swift`, so no additional import is needed.

---

### File 3: `Sprung/Onboarding/Core/EventCoordinator.swift` (new)

**Purpose:** The event bus implementation. Completely independent of what events exist or how they
are described in logs.

**Content (move from current file):**
- `// MARK: - EventCoordinator` section — the `actor EventCoordinator` (lines 635–815)
- `// MARK: - OnboardingEventEmitter Protocol` (lines 817–828)

**Approximate new line count:** ~195 lines

**Imports needed:**
```swift
import Foundation
```
`EventCoordinator` uses `OnboardingEvent`, `EventTopic`, `Logger`. All are in the same module;
no explicit import needed.

**Access level changes:** None required. All types involved are `internal` (Swift default), which
is sufficient for same-module access.

---

### File 4: `TimelineDiff.summary` moved to `Sprung/Onboarding/Utilities/TimelineDiff.swift`

**Move lines 830–841 to the bottom of `TimelineDiff.swift`.**

```swift
// MARK: - TimelineDiff Summary Extension

extension TimelineDiff {
    var summary: String {
        var parts: [String] = []
        if !added.isEmpty { parts.append("\(added.count) added") }
        if !removed.isEmpty { parts.append("\(removed.count) removed") }
        if !updated.isEmpty { parts.append("\(updated.count) updated") }
        if reordered { parts.append("reordered") }
        return parts.isEmpty ? "no changes" : parts.joined(separator: ", ")
    }
}
```

`TimelineDiff.swift` already imports `Foundation`. The `summary` property is only used in
`TimelineEvent.logDescription` inside `OnboardingEventDescriptions.swift`, which can still see it
since it is in the same module.

---

## 6. File Interaction Map After Refactor

```
OnboardingEvents.swift
  └── defines: OnboardingEvent, all nested XEvent enums,
               ProcessedUploadInfo, LLMStatus

OnboardingEventDescriptions.swift
  ├── defines: EventTopic, OnboardingEvent.topic, OnboardingEvent.logDescription
  └── depends on: OnboardingEvent (same module)

EventCoordinator.swift
  ├── defines: EventCoordinator actor, OnboardingEventEmitter protocol
  └── depends on: OnboardingEvent, EventTopic (same module), Logger

TimelineDiff.swift
  └── gains: TimelineDiff.summary (used by OnboardingEventDescriptions.swift)
```

All consumers of `EventCoordinator`, `OnboardingEventEmitter`, `OnboardingEvent`, and `EventTopic`
are in the same Swift module (`Sprung`). No access level changes are needed — everything remains
`internal`. No `import` statements need to change in any of the 57 files that currently reference
these types.

---

## 7. Execution Order for the Developer

1. **Create `EventCoordinator.swift`** — cut lines 635–828 from `OnboardingEvents.swift`,
   paste into new file with a `import Foundation` header.

2. **Create `OnboardingEventDescriptions.swift`** — cut lines 293–633 from
   `OnboardingEvents.swift`, paste into new file with `import Foundation` and
   `@preconcurrency import SwiftyJSON` headers.

3. **Move `TimelineDiff.summary` extension** — cut lines 830–841 from `OnboardingEvents.swift`,
   append to `TimelineDiff.swift`.

4. **Clean up `OnboardingEvents.swift`** — what remains is lines 1–291 (schema + supporting
   types). Update the file header comment to reflect its narrowed scope.

5. **Build** — run a targeted build to catch any issues:
   ```bash
   xcodebuild -project Sprung.xcodeproj -scheme Sprung build 2>&1 | grep -Ei "(error:|warning:|failed|succeeded)" | head -20
   ```
   No errors are expected because this is a pure file reorganization with no type, access-level,
   or API changes.

6. **Verify no old approach survives** — grep confirms `OnboardingEvents.swift` no longer contains
   `actor EventCoordinator`, `EventTopic`, or `logDescription`:
   ```bash
   grep -n "actor EventCoordinator\|EventTopic\|logDescription\|TimelineDiff.summary" \
     Sprung/Onboarding/Core/OnboardingEvents.swift
   ```
   Expected output: empty.

---

## 8. What NOT to Do

- Do not change any method signatures, case names, or associated value labels. This is a
  file-layout refactor, not an API change.
- Do not add `public` or `@_exported` anywhere. Module-internal visibility is correct.
- Do not add a bridging/re-export shim in `OnboardingEvents.swift`. Every consumer imports the
  module, not a specific file.
- Do not split the nested `XEvent` enums into separate files — they are the schema, and keeping
  the full schema in one file aids discoverability.
