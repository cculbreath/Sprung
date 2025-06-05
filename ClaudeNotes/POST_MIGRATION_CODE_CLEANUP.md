# POST-MIGRATION CODE CLEANUP

This document tracks legacy code, files, and suspicious patterns that should be removed after the LLM architecture refactoring is complete.

## HIGH - Definitely Dead/Legacy

### Files to Remove After Phase 4
File: PhysCloudResume/AI/Models/Services/LLMRequestService.swift
Issue: Replaced by unified LLMService

File: PhysCloudResume/AI/Models/Providers/BaseLLMProvider.swift
Issue: May be redundant after LLMService implementation

### Legacy Provider Classes (After Phase 2-4)
File: PhysCloudResume/AI/Models/Providers/ResumeChatProvider.swift
Issue: Logic extracted to LLMService + ResumeReviseService

File: PhysCloudResume/AI/Models/Providers/CoverChatProvider.swift
Issue: Logic extracted to LLMService

### Deprecated UI Components (After Migration Complete)
File: PhysCloudResume/AI/Views/AiCommsView.swift
Issue: Legacy view from old toolbar workflow - replaced by UnifiedToolbar → ResumeReviseService → ReviewView pattern
Evidence: Has compilation errors from partial migration, marked for deprecation in architecture docs

File: PhysCloudResume/AI/Models/Providers/ReorderSkillsProvider.swift
Issue: Simple operation, use LLMService directly

File: PhysCloudResume/AI/Models/Providers/JobRecommendationProvider.swift
Issue: Simple operation, use LLMService directly

File: PhysCloudResume/AI/Models/Providers/CoverLetterRecommendationProvider.swift
Issue: Logic extracted to LLMService

### Commented Out Code
File: ResumeQuery.swift:219-236
Issue: Complex attention grab language generation (commented out)

### Debug Code
File: ResumeQuery.swift:291-294
Issue: Debug file saving throughout codebase

## MEDIUM - Likely Dead/Legacy

### Duplicate Model Management
File: PhysCloudResume/AI/Models/Services/OpenAIModelFetcher.swift
Issue: Uses legacy `getPreferredModelString()` method instead of proper model selection

File: LLMRequestService.swift:67-90
Issue: Legacy AIModels.Provider enum with hardcoded model detection logic

### Redundant Message Conversion
File: Multiple locations
Issue: Multiple message format conversions: `ChatMessage ↔ AppLLMMessage ↔ SwiftOpenAI.Message`
Evidence: Legacy `ChatMessage` type throughout codebase

### Complex State Management
File: Multiple locations
Issue: Multiple overlapping conversation managers (ConversationContextManager, Provider-level conversation history, Built-in ConversationManager in new LLMService)

File: AiCommsView.swift
Issue: Race condition prevention code that may become unnecessary

### Outdated UI Patterns
File: Multiple files
Issue: Option+Click functionality for clarifying questions - replaced by separate toolbar buttons

File: AiFunctionView
Issue: Complex view with manual option key detection

File: LLMRequestService
Issue: Legacy API response format compatibility (ResponsesAPIResponse)

### Disabled Code
File: AiCommsView.swift:400-412
Issue: Suspicious node splitting logic that was "DISABLED"

## LOW - Needs Investigation

### MessageConverter Utility
File: Location unknown
Issue: `MessageConverter` utility class (needs investigation)

### Complex State Management in AiCommsView
File: AiCommsView.swift:58-75
Issue: Provider reset and state recovery logic - suggests underlying architecture issues

File: AiCommsView.swift:112-117
Issue: Race condition prevention with empty array filtering

File: AiCommsView.swift:123-138, 140-184
Issue: Complex revision node validation and filtering

File: AiCommsView.swift:194-227
Issue: Complex timeout/retry logic with 3-minute timeouts

File: AiCommsView.swift:462-596
Issue: Manual conversation context clearing and provider recreation

### Mysterious API Logic
File: LLMRequestService.swift:104
Issue: Special Grok model substitution logic: "Grok vision models are unreliable, use o4-mini instead"

File: LLMRequestService.swift:67-90
Issue: Manual model capability detection with hardcoded substrings

File: AiCommsView.swift
Issue: Complex provider reset logic that suggests architectural issues

### Potential Dead Code
File: ResumeQuery.swift:96-100
Issue: `res.textRes` fallback logic with "⚠️BLANK TEXT RES⚠️" warning

## Cleanup Phases

**Phase 1** (Safe to remove immediately):
- Debug print statements and temporary logging

**Phase 2** (After LLMService + ResumeReviseService are stable):
- Legacy provider classes
- LLMRequestService redundancy

**Phase 3** (After UI integration is complete):
- Legacy message conversion utilities
- Redundant conversation managers

**Phase 4** (Final cleanup):
- Dead code paths
- Unused model management utilities
- Legacy response format compatibility layers

## NEW LEGACY CODE IDENTIFIED (June 4, 2025)

### MEDIUM - Complex Logic to Remove After ResumeReviseService Integration
File: AiCommsView.swift:292-417
Issue: validateRevs function - 125 lines of complex validation logic
Evidence: Will be superseded by ResumeReviseService.validateRevisions()

File: AiCommsView.swift:109-184  
Issue: onChange chatProvider.lastRevNodeArray - complex revision processing
Evidence: 75 lines of state management logic that belongs in business logic layer

File: AiCommsView.swift:419-447
Issue: handleClarifyingQuestionAnswers method
Evidence: Superseded by ResumeReviseService.requestClarifyingQuestions()

File: AiCommsView.swift:451-630
Issue: chatAction method - 179 lines of LLM coordination logic  
Evidence: Should be replaced with ResumeReviseService method calls

### HIGH - Provider Reset Workarounds to Remove
File: AiCommsView.swift:58-75
Issue: Complex provider reset and state recovery logic
Evidence: Architectural workaround that will be eliminated by unified LLMService

File: AiCommsView.swift:574-596
Issue: Manual provider recreation and state preservation
Evidence: Necessary workaround for fragmented architecture, eliminated by LLMService

## Action Items for Future
- Audit all files importing removed provider classes
- Check for unused imports of legacy SwiftOpenAI types
- Verify all model selection flows use new two-stage filtering system
- Remove hardcoded model capability detection in favor of OpenRouterModel properties
- Consolidate conversation management to single system
- Remove duplicate error handling patterns across old providers