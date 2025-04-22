# Migration Plan: SwiftOpenAI to MacPaw/OpenAI

This document outlines the step-by-step process to migrate PhysCloudResume from SwiftOpenAI to MacPaw/OpenAI.

## Setup Phase

- [x] Create a new feature branch (`git checkout -b feature/macpaw-openai-migration`)
- [ ] Add MacPaw/OpenAI as a dependency to the project
- [x] Keep both OpenAI libraries temporarily for staged migration

## Core Infrastructure Changes

- [x] Create OpenAI client wrapper to abstract implementation details
  - [x] Create an `OpenAIClientProtocol` interface
  - [x] Implement SwiftOpenAI version of the client
  - [x] Create placeholder for MacPaw version of the client
  - [x] Create factory for client instantiation

- [x] Update Model Handling
  - [x] Modify `OpenAIModelFetcher.swift` to use generic model identifiers
  - [x] Create mapping between SwiftOpenAI models and MacPaw models
  - [x] Update model fetching logic with compatibility layer

## Feature Migration

- [x] Message & Parameters Conversion
  - [x] Create conversion functions for message formats
  - [x] Update parameter object structures

- [x] Migrate Chat Completion
  - [x] Update `CoverChatProvider.swift` with abstraction layer
  - [x] Implement dual-mode support for compatibility
  - [x] Add new method using abstraction layer directly
  - [ ] Test chat completion with new API

- [x] Migrate Job Recommendation
  - [x] Update `JobRecommendationProvider.swift` with abstraction layer
  - [x] Implement dual-mode support for compatibility 
  - [x] Add new method using abstraction layer directly
  - [ ] Test job recommendation features

- [x] Migrate Resume Chat
  - [x] Update `ResumeChatProvider.swift` with abstraction layer
  - [x] Implement dual-mode support for compatibility
  - [x] Add fallback for streaming functionality
  - [ ] Test resume chat features

- [ ] Migrate Cover Letter Recommendation
  - [ ] Update `CoverLetterRecommendationProvider.swift`
  - [ ] Test cover letter recommendation features

## UI Updates

- [ ] Update AI Views
  - [ ] Modify `AiCommsView.swift`
  - [ ] Update `AiFunctionView.swift`
  - [ ] Update `CoverLetterAiView.swift`

- [ ] Update Progress/Loading indicators for compatibility

## Testing & Cleanup

- [ ] Comprehensive testing of all AI features
  - [ ] Test cover letter generation
  - [ ] Test resume chat
  - [ ] Test job recommendations

- [ ] Remove SwiftOpenAI dependency
  - [ ] Remove import statements
  - [ ] Remove package dependency
  - [ ] Clean up any adapter code

- [ ] Final testing pass
  - [ ] Verify all features work as expected
  - [ ] Check for any regressions

## Deployment

- [ ] Create PR for review
- [ ] Merge to main branch
- [ ] Tag release

## Future Enhancements (Post-Migration)

- [ ] Add TTS streaming capabilities
- [ ] Optimize API call efficiency
- [ ] Implement any MacPaw-specific performance improvements

## Migration Progress Tracking

**Current status**: Setup phase

**Estimated completion**: TBD

**Key blockers**: None identified yet