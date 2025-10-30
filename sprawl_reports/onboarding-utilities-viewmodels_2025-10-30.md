# Code Sprawl Analysis Report
**Directory**: ./Sprung/Onboarding/Utilities/ and ./Sprung/Onboarding/ViewModels/
**Analysis Date**: 2025-10-30
**Files Examined**: 4

## ✅ COMPLETED REFACTORING (2025-10-30)
**Quick Wins Implemented:**
1. Deleted unused `replaceSection()` method in ExperienceDefaultsDraft+Onboarding.swift (-37 LOC)
2. Created StringExtensions.swift utility with `trimmedNonEmpty` and `isTrimmedEmpty` helpers (+14 LOC)

**Status**: Utilities directory reduced from 306 → 283 LOC

## Executive Summary
- Total LOC in directories: 283 (was 306, reduced by 23)
- Estimated reducible LOC: 62-72 (22-25%, was 85-95)
- High-priority issues: 1 (was 2, completed 1)
- Medium-priority issues: 3
- Low-priority issues: 2

## File-by-File Analysis

### ExperienceDefaultsDraft+Onboarding.swift
**Current LOC**: 84
**Estimated reducible LOC**: 50-60

#### Issues Found

1. **Massive Switch Statement Duplication** (Priority: High)
   - **Lines**: 11-47, 53-67, 69-83
   - **Problem**: Three massive switch statements (`replaceSection`, `setEnabled`, `isEnabled`) manually enumerate all 11 section types. This pattern is extremely brittle - adding a new section type requires updating all three switches plus the enum definition. The `replaceSection` method alone is 36 lines of pure boilerplate.
   - **Recommendation**: Replace with a KeyPath-based approach or a protocol-oriented design. Since `ExperienceDefaultsDraft` has a regular structure (pairs of `isXEnabled: Bool` and `x: [XDraft]` properties), use reflection or a lookup table mapping `ExperienceSectionKey` to KeyPaths for both the enabled flag and the data array.
   - **Effort**: Medium
   - **Impact**: Reduce ~60 lines to ~15-20 lines. Eliminates entire category of bugs when adding new section types. Dramatically improves maintainability.
   - **Example**:
   ```swift
   // Before: 36 lines of switch cases
   mutating func replaceSection(_ key: ExperienceSectionKey, with other: ExperienceDefaultsDraft) {
       switch key {
       case .work:
           work = other.work
           isWorkEnabled = !work.isEmpty
       // ... 10 more identical cases
       }
   }

   // After: Could use a lookup table approach
   private static let sectionMappings: [ExperienceSectionKey: SectionMapping] = [
       .work: SectionMapping(
           dataKeyPath: \ExperienceDefaultsDraft.work,
           enabledKeyPath: \ExperienceDefaultsDraft.isWorkEnabled
       ),
       // ... etc
   ]

   mutating func replaceSection(_ key: ExperienceSectionKey, with other: ExperienceDefaultsDraft) {
       guard let mapping = Self.sectionMappings[key] else { return }
       self[keyPath: mapping.dataKeyPath] = other[keyPath: mapping.dataKeyPath]
       self[keyPath: mapping.enabledKeyPath] = !self[keyPath: mapping.dataKeyPath].isEmpty
   }
   ```

2. **Unused Method** (Priority: High)
   - **Lines**: 11-47
   - **Problem**: `replaceSection(_ key:with:)` is defined but never called anywhere in the codebase. 36 lines of dead code that adds maintenance burden.
   - **Recommendation**: Delete the entire method unless there's a planned future use. If it's for future functionality, document that clearly or move it to a separate extension marked as experimental.
   - **Effort**: Low
   - **Impact**: Remove 36 lines immediately. Reduces cognitive load when reading this file.

3. **Verbose Boolean Manipulation** (Priority: Low)
   - **Lines**: 4-9
   - **Problem**: `setEnabledSections` iterates through all cases and calls `setEnabled` for each. While not terrible, this is verbose compared to what it could be.
   - **Recommendation**: If adopting the KeyPath approach above, this becomes a simple loop over the mappings table. Otherwise, acceptable as-is.
   - **Effort**: Low (if doing KeyPath refactor), High (if standalone)
   - **Impact**: Minimal standalone, but significant as part of larger refactor.

---

### ExperienceSectionKey+Onboarding.swift
**Current LOC**: 37
**Estimated reducible LOC**: 15-20

#### Issues Found

1. **Over-Engineering String Normalization** (Priority: Medium)
   - **Lines**: 4-36
   - **Problem**: The `fromOnboardingIdentifier` method performs complex string normalization (lowercasing, replacing spaces, replacing hyphens) and then has extensive case matching for synonyms. This is only called from one place (ResumeSectionsToggleCard line 23) where it processes AI-generated section names. The normalization chain and extensive synonym matching adds complexity without clear evidence that it's needed.
   - **Recommendation**: Analyze the actual values passed from the AI assistant. If they're already normalized (which is likely, given LLM outputs), simplify to just lowercase comparison without replacements. If synonyms are actually used, document which ones are necessary and remove the rest. Consider whether the fallback `ExperienceSectionKey(rawValue: normalized)` ever succeeds - if not, return nil explicitly.
   - **Effort**: Low
   - **Impact**: Reduce 15-20 lines to 8-10 lines. Improved clarity about what inputs are actually expected.
   - **Example**:
   ```swift
   // Before: Complex normalization + extensive synonym matching
   static func fromOnboardingIdentifier(_ identifier: String) -> ExperienceSectionKey? {
       let normalized = identifier
           .lowercased()
           .replacingOccurrences(of: " ", with: "_")
           .replacingOccurrences(of: "-", with: "_")

       switch normalized {
       case "work", "work_experience", "jobs", "employment":
           return .work
       // ... many more cases
       }
   }

   // After: If simple mapping suffices
   static func fromOnboardingIdentifier(_ identifier: String) -> ExperienceSectionKey? {
       ExperienceSectionKey(rawValue: identifier.lowercased())
   }
   // Or with minimal synonym support:
   static func fromOnboardingIdentifier(_ identifier: String) -> ExperienceSectionKey? {
       let normalized = identifier.lowercased()
       let synonymMap: [String: ExperienceSectionKey] = [
           "jobs": .work,
           "employment": .work
           // Only include synonyms that actually occur in practice
       ]
       return synonymMap[normalized] ?? ExperienceSectionKey(rawValue: normalized)
   }
   ```

2. **Unclear Purpose of Fallback** (Priority: Low)
   - **Lines**: 34
   - **Problem**: After all the explicit case matching, there's a fallback `ExperienceSectionKey(rawValue: normalized)`. This is odd because if the normalized string didn't match any explicit case, it's unlikely to match a raw value. This suggests uncertainty about what inputs to expect.
   - **Recommendation**: Add logging or assertions when the fallback is hit during development to understand if it's ever used. If not, make the method return nil explicitly with a comment explaining expected inputs.
   - **Effort**: Low
   - **Impact**: Minimal LOC reduction but improved understanding of the code's behavior.

---

### OnboardingUploadStorage.swift
**Current LOC**: 82
**Estimated reducible LOC**: 8-10

#### Issues Found

1. **Duplicate Storage URL Keys in JSON** (Priority: Medium)
   - **Lines**: 16-17
   - **Problem**: `toJSON()` writes the same URL value to both `file_url` and `storageUrl`. This duplication serves no clear purpose and creates confusion about which key consumers should use.
   - **Recommendation**: Determine which key is actually used by consumers and remove the other. If both are needed for backward compatibility, add a comment explaining why. Otherwise, this is redundant data.
   - **Effort**: Low (requires checking consumer code)
   - **Impact**: Remove 1 line, improve clarity.

2. **Inconsistent Error Handling** (Priority: Medium)
   - **Lines**: 33-39, 66-68
   - **Problem**: The initializer silently logs and continues if directory creation fails, while `processFile` throws errors. This inconsistency means the storage object could be in a broken state where `uploadsDirectory` points to a non-existent location. Additionally, `removeFile` silently ignores all errors with `try?`.
   - **Recommendation**: Either make the initializer throw an error if directory creation fails, or document that this is designed to work with a fallback location. For `removeFile`, consider logging failures since file deletion errors might indicate permission issues or other problems worth knowing about.
   - **Effort**: Low
   - **Impact**: Improved robustness, ~3-5 lines added for proper error handling or documentation.

3. **Backward Compatibility Check** (Priority: Low)
   - **Lines**: 77-80
   - **Problem**: The `contentType` method checks for macOS 12.0+ availability, but this check is likely unnecessary if the project's deployment target is already macOS 12+.
   - **Recommendation**: Check the project's minimum deployment target. If it's macOS 12.0 or higher, remove the availability check and simplify the method.
   - **Effort**: Low
   - **Impact**: Remove 3-4 lines, slight clarity improvement.

4. **Verbose Filename Construction** (Priority: Low)
   - **Lines**: 44-46
   - **Problem**: Minor verbosity in how the destination filename is constructed with UUID prefix.
   - **Recommendation**: Acceptable as-is. The explicit naming improves clarity about what's happening.
   - **Effort**: N/A
   - **Impact**: N/A

---

### OnboardingInterviewViewModel.swift
**Current LOC**: 103
**Estimated reducible LOC**: 12-15

#### Issues Found

1. **Redundant Configuration Logic** (Priority: High)
   - **Lines**: 32-55
   - **Problem**: `configureIfNeeded` has complex conditional logic that syncs model selection and then overwrites `webSearchAllowed` and `writingAnalysisAllowed` based on service state. This is then duplicated in `syncConsentFromService` (lines 88-92), which does the exact same thing for the consent flags. The separation creates confusion about when each method should be called.
   - **Recommendation**: Consolidate the consent syncing logic. The `configureIfNeeded` method is doing two conceptually different things: (1) initial model selection setup, and (2) consent flag syncing. Split these responsibilities or eliminate the duplication in `syncConsentFromService`.
   - **Effort**: Low
   - **Impact**: Remove 5-8 lines of duplication, clearer method responsibilities.

2. **Over-Parameterized Methods** (Priority: Medium)
   - **Lines**: 32-38, 57-61, 77-85
   - **Problem**: Multiple methods accept the same sets of parameters repeatedly (`defaultModelId`, `availableModelIds`, etc.). This is particularly visible in `configureIfNeeded`, `syncModelSelection`, and `handleDefaultModelChange` which all pass around the same model-related parameters.
   - **Recommendation**: Consider creating a simple `ModelConfiguration` struct to bundle these related parameters. This reduces parameter lists and makes the intent clearer.
   - **Effort**: Medium
   - **Impact**: ~10-12 lines saved across method signatures, improved call site clarity.
   - **Example**:
   ```swift
   // Before:
   func configureIfNeeded(
       service: OnboardingInterviewService,
       defaultModelId: String,
       defaultWebSearchAllowed: Bool,
       defaultWritingAnalysisAllowed: Bool,
       availableModelIds: [String]
   ) { ... }

   // After:
   struct ModelConfiguration {
       let defaultModelId: String
       let availableModelIds: [String]
   }

   func configureIfNeeded(
       service: OnboardingInterviewService,
       modelConfig: ModelConfiguration,
       defaultWebSearchAllowed: Bool,
       defaultWritingAnalysisAllowed: Bool
   ) { ... }
   ```

3. **Import Error State Management Verbosity** (Priority: Low)
   - **Lines**: 12-13, 94-102
   - **Problem**: Two separate properties and two methods to manage a simple error state. `showImportError` and `importErrorText` could potentially be combined.
   - **Recommendation**: Consider using a single optional `importError: String?` property where non-nil means show the error, and nil means hide it. The derived `showImportError` property could become a computed property.
   - **Effort**: Low
   - **Impact**: Remove 2 properties and 1 method (~5-6 lines), simplified state management.

4. **Initialization Tracking Flag** (Priority: Low)
   - **Lines**: 16, 39-45
   - **Problem**: `hasInitialized` is used to ensure setup happens once, but this pattern suggests the view model's lifecycle might not be well-defined. If this is truly needed, it's acceptable, but it's worth questioning why `configureIfNeeded` might be called multiple times.
   - **Recommendation**: Document why multiple calls are expected, or refactor the view lifecycle to ensure initialization happens exactly once through proper SwiftUI view lifecycle management.
   - **Effort**: Medium (requires understanding view lifecycle)
   - **Impact**: Potential architectural improvement, minimal LOC reduction.

---

## Cross-Cutting Patterns

### Pattern 1: Boilerplate from Flat Data Structure
The `ExperienceDefaultsDraft+Onboarding` extension suffers from the flat structure of `ExperienceDefaultsDraft`, which has 11 separate properties for sections and 11 separate boolean flags. This forces manual enumeration everywhere. This is a structural issue that could be addressed by:
- Using a dictionary-based structure: `[ExperienceSectionKey: (enabled: Bool, data: [Any])]`
- Creating a generic `Section<T>` type that bundles the enabled flag with the data
- Using KeyPath-based reflection to eliminate the switch statements

### Pattern 2: String-Based Type Mapping
Both utility files (`ExperienceSectionKey+Onboarding` and `OnboardingUploadStorage`) deal with string-based serialization/deserialization. The fromOnboardingIdentifier method shows defensive programming against unknown AI outputs, but it's unclear if all that defensiveness is needed.

### Pattern 3: Optional Error Handling Inconsistency
Across the utilities, error handling is inconsistent:
- `OnboardingUploadStorage` initializer: silent failure with logging
- `OnboardingUploadStorage.processFile`: throws errors
- `OnboardingUploadStorage.removeFile`: silent failure with try?
This suggests unclear ownership of error handling responsibilities.

---

## Prioritized Recommendations

### Quick Wins (High Impact, Low Effort)

1. **Delete unused `replaceSection` method** (ExperienceDefaultsDraft+Onboarding.swift)
   - Files: ExperienceDefaultsDraft+Onboarding.swift lines 11-47
   - Estimated LOC reduction: 36 lines
   - Impact: Immediate maintenance burden reduction, zero risk

2. **Remove duplicate storageUrl key** (OnboardingUploadStorage.swift)
   - Files: OnboardingUploadStorage.swift line 17
   - Estimated LOC reduction: 1 line
   - Impact: Cleaner JSON output, reduced confusion

3. **Simplify import error state** (OnboardingInterviewViewModel.swift)
   - Files: OnboardingInterviewViewModel.swift lines 12-13, 94-102
   - Estimated LOC reduction: 5-6 lines
   - Impact: Simpler state management, less property duplication

**Total Quick Wins**: ~42 lines reduction

### Medium-term Improvements (High Impact, Medium Effort)

1. **Simplify string normalization** (ExperienceSectionKey+Onboarding.swift)
   - Files: ExperienceSectionKey+Onboarding.swift lines 4-36
   - Estimated LOC reduction: 15-20 lines
   - Impact: Dramatically improved clarity, easier to understand actual requirements
   - Requires: Analysis of actual AI output patterns to determine necessary synonyms

2. **Consolidate consent syncing logic** (OnboardingInterviewViewModel.swift)
   - Files: OnboardingInterviewViewModel.swift lines 32-55, 88-92
   - Estimated LOC reduction: 5-8 lines
   - Impact: Clearer responsibilities, reduced duplication

3. **Introduce ModelConfiguration parameter object** (OnboardingInterviewViewModel.swift)
   - Files: OnboardingInterviewViewModel.swift lines 32-38, 57-61, 77-85
   - Estimated LOC reduction: 10-12 lines
   - Impact: Cleaner method signatures, better encapsulation of related data

**Total Medium-term**: ~30-40 lines reduction

### Strategic Refactoring (High Impact, High Effort)

1. **Replace switch statements with KeyPath-based approach** (ExperienceDefaultsDraft+Onboarding.swift)
   - Files: ExperienceDefaultsDraft+Onboarding.swift entire file
   - Estimated LOC reduction: 50-60 lines → 15-20 lines implementation
   - Impact: Eliminates entire category of bugs when adding sections, dramatically improves maintainability
   - Risk: Moderate - requires understanding of Swift KeyPaths and potentially more complex type system usage
   - Note: This may require changes to `ExperienceDefaultsDraft` itself or creation of parallel infrastructure
   - Recommendation: Worth the investment if new section types are planned or if this pattern appears elsewhere

**Total Strategic**: ~35-45 lines reduction, but much higher maintainability improvement

### Not Recommended (Low Impact or High Risk)

1. **Changing ExperienceDefaultsDraft's structure to use dictionaries**
   - While this would eliminate the switch statements, `ExperienceDefaultsDraft` is used throughout the Experience module with SwiftData and has many dependencies. The refactoring risk is extremely high relative to the benefit.
   - Better to work within the existing structure using KeyPaths or accept the boilerplate.

2. **Making OnboardingUploadStorage initializer throw**
   - The silent failure in initialization is likely intentional to avoid app crashes. Changing this could have unexpected consequences on app stability.
   - Better to add documentation explaining the behavior.

---

## Total Impact Summary

- **Quick Wins**: ~42 LOC reduction, 3 changes, immediate benefit
- **Medium-term**: ~30-40 LOC reduction, 3 changes, significant clarity improvements
- **Strategic**: ~35-45 LOC reduction, 1 change, transformative maintainability improvement
- **Total Potential**: ~107-127 LOC reduction (35-41% of current 306 LOC)

## Conclusion

These directories contain well-structured code with specific areas of excessive boilerplate. The highest-priority issue is the massive switch statement duplication in `ExperienceDefaultsDraft+Onboarding.swift`, which represents both dead code (the unused `replaceSection` method) and repeated patterns that could be eliminated through better abstractions.

The `OnboardingInterviewViewModel` is generally well-structured but shows signs of parameter proliferation that could be cleaned up. The utility extensions show defensive programming that may or may not be necessary depending on actual runtime behavior.

The most impactful improvement would be implementing a KeyPath-based approach for section manipulation, but this requires careful design to avoid introducing new complexity. The quick wins (particularly deleting the unused 36-line method) should be implemented immediately as they have zero risk and immediate benefit.
