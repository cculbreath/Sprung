# Core App Refactoring Plan (Parallelized)

Based on architectural review (Grade: B, AI Slop Index: 3/10)

## Phase 1: Critical Fixes (2 Parallel Agents)

| Agent | Task | Files | Dependencies |
|-------|------|-------|--------------|
| **Agent P** | Fix hardcoded API URL | `ModelValidationService.swift` | None |
| **Agent Q** | Fix synchronous file I/O in drop handler | `ResRefFormView.swift` | None |

**Status:** ✅ Can run in parallel

---

## Phase 2: Consolidate Shared Utilities (2 Parallel Agents)

| Agent | Task | Files | Dependencies |
|-------|------|-------|--------------|
| **Agent R** | Consolidate JSON extraction into `LLMResponseParser` | `LLMResponseParser.swift`, `ResumeReviewService.swift`, `SkillReorderService.swift`, `ClarifyingQuestionsViewModel.swift`, `SearchOpsLLMService.swift` | None |
| **Agent S** | Create `ExperienceSectionKey` usage throughout (replace magic strings) | `ExperienceDefaultsToTree.swift`, `ExperienceSchema.swift` | None |

**Status:** ✅ Can run in parallel

---

## Phase 3: Unify Data Models (Sequential - foundational change)

| Agent | Task | Files |
|-------|------|-------|
| **Agent T** | Migrate from `JobLead` to `JobApp` everywhere; add conversion methods | `JobLead.swift`, `JobApp.swift`, `JobLeadStore.swift`, all SearchOps views referencing JobLead |

**Status:** ⚠️ Must complete before SearchOps coordinator refactor

---

## Phase 4: Decompose God Objects (3 Parallel Agents)

| Agent | Task | Files | Dependencies |
|-------|------|-------|--------------|
| **Agent U** | Break up `SearchOpsCoordinator` into feature-specific coordinators | `SearchOpsCoordinator.swift` → new `SearchOpsPipelineCoordinator.swift`, `SearchOpsNetworkingCoordinator.swift` | Agent T |
| **Agent V** | Decompose `ResumeReviseViewModel` into state objects | `ResumeReviseViewModel.swift` → new `RevisionNavigationState.swift`, `StreamingState.swift`, `ToolState.swift` | None |
| **Agent W** | Refactor `WebViewHTMLFetcher` as shared utility | `CloudflareChallengeView.swift`, `WebViewHTMLFetcher.swift` | None |

**Status:** ✅ Agents V and W can run immediately; Agent U waits for Agent T

---

## Phase 5: Extract Resources (2 Parallel Agents)

| Agent | Task | Files | Dependencies |
|-------|------|-------|--------------|
| **Agent X** | Extract prompts to resource files | `ResumeApiQuery.swift`, `SearchOpsAgentService.swift`, `ResumeReviewQuery.swift` → new `.txt` files | None |
| **Agent Y** | Extract JSON schemas to external files | `SearchOpsToolSchemas.swift` → new `.json` files | None |

**Status:** ✅ Can run in parallel

---

## Phase 6: Medium Priority Fixes (3 Parallel Agents)

| Agent | Task | Files | Dependencies |
|-------|------|-------|--------------|
| **Agent Z** | Fix unsafe `try!` for regex | `TemplateEditorView+Validation.swift` | None |
| **Agent AA** | Create shared `ReviewPromptBuilder` | `ResumeReviewType.swift`, `ApplicationReviewType.swift` | None |
| **Agent AB** | Fix template filter drift | `TemplateTextFilters.swift`, `TemplateFilters.swift` | None |

**Status:** ✅ All 3 can run in parallel

---

## Phase 7: Cleanup (1 Agent)

| Agent | Task | Files |
|-------|------|-------|
| **Agent AC** | Move `displayTitle` to extension, evaluate `JobApp` Codable synthesis | `JobLead.swift` (if still exists), `JobApp.swift` |

---

## Execution Flow Diagram

```
Phase 1: ──┬── Agent P (API URL)
           └── Agent Q (file I/O)
                    │
Phase 2: ──┬── Agent R (JSON parser consolidation)
           └── Agent S (magic strings)
                    │
Phase 3: ──── Agent T (JobLead → JobApp) ─────────────┐
                    │                                  │
Phase 4: ──┬── Agent V (ResumeReviseViewModel)        │
           ├── Agent W (WebViewHTMLFetcher)           │
           └────────────────────────────── Agent U (SearchOpsCoordinator)
                    │
Phase 5: ──┬── Agent X (extract prompts)
           └── Agent Y (extract schemas)
                    │
Phase 6: ──┬── Agent Z (regex try!)
           ├── Agent AA (ReviewPromptBuilder)
           └── Agent AB (template filters)
                    │
Phase 7: ──── Agent AC (cleanup)
```

## Issue Details

### Critical Issues

**1. Hardcoded API URL bypassing AppConfig**
- **File:** `Sprung/Shared/AI/Models/Services/ModelValidationService.swift`
- **Problem:** Hardcoded `baseURL = "https://openrouter.ai/api/v1"` ignores `AppConfig.openRouterBaseURL`
- **Fix:** Replace with `AppConfig.openRouterBaseURL`

**2. Synchronous File I/O on Main Thread during Drop**
- **File:** `Sprung/ResRefs/Views/ResRefFormView.swift`
- **Problem:** `try String(contentsOf: url, encoding: .utf8)` blocks UI on slow/network drives
- **Fix:** Move file reading to `Task.detached` before dispatching to main

### High Priority Issues

**3. Rampant Duplication of JSON Extraction Logic**
- **Files:** `ResumeReviewService.swift`, `SkillReorderService.swift`, `ClarifyingQuestionsViewModel.swift`, `SearchOpsLLMService.swift`, `LLMResponseParser.swift`
- **Problem:** `extractJSONFromText`/`parseJSONFromText` copy-pasted across 5+ files
- **Fix:** Consolidate into `LLMResponseParser.parseJSON(_:as:)`

**4. Duplicate Domain Models (JobApp vs. JobLead)**
- **Files:** `JobApp.swift`, `JobLead.swift`
- **Problem:** Two models track same data (company, role, status) but are separate SwiftData entities
- **Fix:** Use `JobApp` everywhere per dev note

**5. Massive "God Object" Coordinator**
- **File:** `SearchOpsCoordinator.swift`
- **Problem:** Initializes 11 stores + 2 services, acts as Service Locator
- **Fix:** Break into `SearchOpsPipelineCoordinator`, `SearchOpsNetworkingCoordinator`

### Medium Priority Issues

**6. Unsafe Force Try in Static Properties**
- **File:** `TemplateEditorView+Validation.swift`
- **Problem:** `try!` for regex compilation crashes on invalid pattern
- **Fix:** Use lazy property with throwing accessor

**7. Duplicate Networking Logic for Cloudflare**
- **Files:** `CloudflareChallengeView.swift`, `WebViewHTMLFetcher.swift`
- **Problem:** Both implement similar `WKNavigationDelegate` logic
- **Fix:** Refactor `WebViewHTMLFetcher` as shared utility

**8. Magic Strings in Template Manifests**
- **File:** `ExperienceDefaultsToTree.swift`
- **Problem:** Hardcoded strings like "work", "volunteer", "education"
- **Fix:** Use `ExperienceSectionKey` enum from `ExperienceSchema.swift`

### Low Priority Issues

**9. Redundant Review Type Enums**
- **Files:** `ResumeReviewType.swift`, `ApplicationReviewType.swift`
- **Fix:** Share prompt construction via `ReviewPromptBuilder`

**10. View Logic in Model**
- **File:** `JobLead.swift` (`displayTitle`)
- **Fix:** Move to extension or View helper
