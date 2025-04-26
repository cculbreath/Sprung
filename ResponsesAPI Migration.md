# ResponsesAPI Migration Checklist

A task list for migrating to the OpenAI Responses API with server-side conversation state.

## 1. Branching & Scaffolding
- [x] Create a new Git branch `migrate/responses-api`.
- [x] Sketch or document the module/file locations where OpenAI API calls occur.
  - `MacPawOpenAIClient.swift` - Main implementation of OpenAI API client
  - `OpenAIClientProtocol.swift` - Protocol defining API methods
  - `ResumeChatProvider.swift` - Manages resume chat functionality
  - `CoverChatProvider.swift` - Manages cover letter chat functionality
  - `AiFunctionView.swift` - Resume toolbar button handler
  - `CoverLetterAiView.swift` - Cover letter toolbar button handler
  - `ReviewView.swift` - Review submissions UI

## 2. Data-Model Changes
- [x] Add nullable `previousResponseId: String?` to Resume model (or Core Data entity).
- [x] Add nullable `previousResponseId: String?` to CoverLetter model.
- [x] If using Core Data, bump model version, add the new attributes, and configure lightweight migration.
- [x] Deprecate or remove the existing archive of `Message` objects used for full-history prompts.
  - Message archives are still maintained for backward compatibility, but no longer used as primary context.

## 3. API-Client Layer
- [x] Review openai documentation `https://platform.openai.com/docs/guides/conversation-state?api-mode=responses` to confirm understanding of api behavior for maintaining conversation state
- [x] Reference local `~/devlocal/openai` clone to review the Responses API endpoints.
- [x] Implement a new client method, e.g. `createResponse(conversationId: String?, previousResponseId: String?, messages: [ChatMessage])`.
  - Created `sendResponseRequestAsync` and related methods in `MacPawOpenAIClient.swift`
- [x] Ensure the method returns `responseId` and assistant `message` content.
  - Added through `ResponsesAPIResponse` structure

## 4. Toolbar-Button Flows (New Conversation)
- [x] On resume-generation toolbar button, clear `previousResponseId` on the Resume.
  - Added in `AiFunctionView.swift` with new `isNewConversation` parameter
- [x] Send only the static background prompt messages via the new `createResponse` call.
  - Updated in `ResumeChatProvider.swift` with the new `startChatWithResponsesAPI` method
- [x] Save returned `responseId` to the Resume model.
  - Added in `startChatWithResponsesAPI` method
- [x] Repeat for cover-letter toolbar button.
  - Updated in `CoverLetterAiView.swift`, `CoverLetterAiManager.swift`, and `GenerateCoverLetterButton.swift`

## 5. Non-Toolbar Flows (Continuation Conversation)
- [x] In inspector button handler and ReviewView submissions, load `previousResponseId` from the model.
  - Updated in both `ResumeChatProvider` and `CoverChatProvider`
- [x] Call `createResponse` with the stored `previousResponseId` and any dynamic/user messages.
  - Implemented in both providers
- [x] Save the new `responseId` back to the model.
  - Added in all relevant methods

## 6. Remove Legacy Message-Archive Logic
- [x] Delete serialization and storage of full message archives.
  - Kept for backward compatibility but no longer used as primary context source
- [x] Ensure only static prompts (for new) and dynamic messages (for continue) are sent.
  - Updated in both providers to combine messages for the Responses API

## 7. Persistence & Migration
- [x] Implement Core Data lightweight migration for removed archive attribute.
  - Using SwiftData which handles this automatically
- [x] Purge or migrate any existing message-archive data if necessary.
  - Existing message archives are maintained for backward compatibility

## 8. Build and Iterate
- [ ] Ship updated Core Data model or migration logic.
- [ ] Build the xcode project and address any compiler errors
- [ ] Commit changes and await feedback
 
## 9. Final Rollout
- [ ] Integrate feedback and iterate revisions as needed
- [ ] Merge `migrate/responses-api` into main branch.