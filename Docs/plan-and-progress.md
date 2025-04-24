# Migration Plan: SwiftOpenAI to MacPaw/OpenAI

This document outlines the step-by-step process to migrate PhysCloudResume from SwiftOpenAI to MacPaw/OpenAI.

## Setup Phase

- [x] Create a new feature branch (`git checkout -b feature/macpaw-openai-migration`)
- [x] Add MacPaw/OpenAI as a dependency to the project
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
  - [ ] Test chat completion with new API [Skip for now]

- [x] Migrate Job Recommendation
  - [x] Update `JobRecommendationProvider.swift` with abstraction layer
  - [x] Implement dual-mode support for compatibility 
  - [x] Add new method using abstraction layer directly
  - [ ] Test job recommendation features [Skip for now]

- [x] Migrate Resume Chat
  - [x] Update `ResumeChatProvider.swift` with abstraction layer
  - [x] Implement dual-mode support for compatibility
  - [x] Add fallback for streaming functionality
  - [ ] Test resume chat features [Skip for now]

- [x] Migrate Cover Letter Recommendation
  - [x] Update `CoverLetterRecommendationProvider.swift` with abstraction layer
  - [x] Implement dual-mode support for compatibility
  - [x] Add new method using abstraction layer directly
  - [ ] Test cover letter recommendation features  [Skip for now]

## UI Updates

- [x] Update AI Views
  - [x] Modify `AiCommsView.swift`
  - [x] Update `AiFunctionView.swift`
  - [x] Update `CoverLetterAiView.swift`

- [ ] Update Progress/Loading indicators for compatibility

## MacPaw/OpenAI Integration

- [x] Implement MacPaw/OpenAI client
  - [x] Complete MacPawOpenAIClient implementation
  - [x] Add conversion functions for MacPaw's message formats
  - [x] Add proper model mapping

- [x] Switch to MacPaw Client
  - [x] Update factory to default to MacPaw client
  - [ ] Test with MacPaw client

## TTS Capabilities

- [x] Extend OpenAIClientProtocol for TTS support
  - [x] Add TTS methods to OpenAIClientProtocol
  - [x] Implement TTS in MacPawOpenAIClient
  - [x] Add placeholder implementations in SwiftOpenAIClient

- [x] Create TTS Provider Layer
  - [x] Create OpenAITTSProvider class
  - [x] Implement both standard and streaming TTS methods
  - [x] Add AVFoundation playback capabilities

- [x] TTS UI Components
  - [x] Add TTS controls to relevant views
  - [x] Create audio playback indicator
  - [x] Add voice selection to SettingsView

## Testing & Cleanup

- [ ] Comprehensive testing of all AI features [Skip for now]
  - [ ] Test cover letter generation [Skip for now]
  - [ ] Test resume chat [Skip for now]
  - [ ] Test job recommendations [Skip for now]
  - [ ] Test TTS capabilities [Skip for now]

- [ ] Remove SwiftOpenAI dependency
  - [ ] Remove import statements
  - [ ] Remove package dependency
  - [ ] Clean up any adapter code !important existing scaffolding is cumbersome

- [ ] Final testing pass
  - [ ] Verify all features work as expected [I will do manually in UI for now]
  - [ ] Check for any regressions

## Deployment

- [ ] Create PR for review  [Skip for now]
- [ ] Merge to main branch  [Skip for now]
- [ ] Tag release  [Skip for now]

## Future Enhancements (Post-Migration)

- [x] Add TTS streaming capabilities
- [ ] Optimize API call efficiency
- [ ] Implement any MacPaw-specific performance improvements
- [x] Add voice selection UI for TTS features
- [ ] Implement audio file saving for generated speech

## Migration Progress Tracking

**Current status**: UI Integration Complete - Ready for Testing

**Estimated completion**: TBD

**Key blockers**: None identified yet

**Remaining Tasks**:
1. Test with MacPaw client for existing features
2. Comprehensive testing
3. Remove SwiftOpenAI dependency (if decided)
