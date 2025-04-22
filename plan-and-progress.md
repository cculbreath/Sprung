# Migration Plan: SwiftOpenAI to MacPaw/OpenAI

This document outlines the step-by-step process to migrate PhysCloudResume from SwiftOpenAI to MacPaw/OpenAI.

## Setup Phase

- [x] Create a new feature branch (`git checkout -b feature/macpaw-openai-migration`)
- [ ] Add MacPaw/OpenAI as a dependency to the project
- [ ] Keep both OpenAI libraries temporarily for staged migration

## Core Infrastructure Changes

- [ ] Create OpenAI client wrapper to abstract implementation details
  - [ ] Create an `OpenAIClientProtocol` interface
  - [ ] Implement MacPaw version of the client
  - [ ] Create factory for client instantiation

- [ ] Update Model Handling
  - [ ] Modify `OpenAIModelFetcher.swift` to use MacPaw's model identifiers
  - [ ] Create mapping between SwiftOpenAI models and MacPaw models
  - [ ] Update model fetching logic with compatibility layer

## Feature Migration

- [ ] Message & Parameters Conversion
  - [ ] Create conversion functions for message formats
  - [ ] Update parameter object structures

- [ ] Migrate Chat Completion
  - [ ] Update `CoverChatProvider.swift`
  - [ ] Test chat completion with new API

- [ ] Migrate Job Recommendation
  - [ ] Update `JobRecommendationProvider.swift`
  - [ ] Test job recommendation features

- [ ] Migrate Resume Chat
  - [ ] Update `ResumeChatProvider.swift`
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