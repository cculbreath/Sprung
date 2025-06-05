# LLM Multi-Turn Workflows Analysis

## Table of Contents
- [LLM Multi-Turn Workflows Analysis](#llm-multi-turn-workflows-analysis)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [1. Fix Overflow / Does Content Fit Workflow](#1-fix-overflow--does-content-fit-workflow)
    - [UI Flow](#ui-flow)
    - [Prompt Structure \& Conversation Flow](#prompt-structure--conversation-flow)
      - [Iteration Loop (max 3 iterations by default):](#iteration-loop-max-3-iterations-by-default)
    - [Response Handling](#response-handling)
    - [Special Features](#special-features)
  - [2. Generate Resume Revisions / Submit Feedback Workflow](#2-generate-resume-revisions--submit-feedback-workflow)
    - [UI Flow](#ui-flow-1)
    - [Prompt Structure \& Conversation Flow](#prompt-structure--conversation-flow-1)
      - [Phase 1: Clarifying Questions (if enabled)](#phase-1-clarifying-questions-if-enabled)
      - [Phase 2: Process Answers \& Generate Revisions](#phase-2-process-answers--generate-revisions)
      - [Phase 3: Iterative Revision Review Loop](#phase-3-iterative-revision-review-loop)
        - [Step 1: Review Individual Revisions](#step-1-review-individual-revisions)
        - [Step 2: Feedback Collection \& State Management](#step-2-feedback-collection--state-management)
        - [Step 3: Intelligent Feedback Processing](#step-3-intelligent-feedback-processing)
        - [Step 4: AI Resubmission Loop (AiCommsView.swift)](#step-4-ai-resubmission-loop-aicommsviewswift)
        - [Step 5: Validation \& Node Matching](#step-5-validation--node-matching)
    - [Response Handling](#response-handling-1)
  - [3. Multi-Model Cover Letter Recommendation Workflow](#3-multi-model-cover-letter-recommendation-workflow)
    - [UI Flow](#ui-flow-2)
    - [Prompt Structure \& Conversation Flow](#prompt-structure--conversation-flow-2)
      - [Parallel Processing:](#parallel-processing)
      - [FPTP Prompt:](#fptp-prompt)
      - [Score Voting Prompt:](#score-voting-prompt)
    - [Response Handling](#response-handling-2)
    - [Special Features](#special-features-1)
  - [4. Batch Cover Letter Generation and Vote Workflow](#4-batch-cover-letter-generation-and-vote-workflow)
    - [UI Flow](#ui-flow-3)
    - [Prompt Structure \& Conversation Flow](#prompt-structure--conversation-flow-3)
      - [Generation Phase:](#generation-phase)
      - [Batch Processing:](#batch-processing)
    - [Response Handling](#response-handling-3)
    - [Special Features](#special-features-2)
  - [Common Patterns Across Workflows](#common-patterns-across-workflows)
    - [1. Structured Output Handling](#1-structured-output-handling)
    - [2. Progress Communication](#2-progress-communication)
    - [3. Error Handling](#3-error-handling)
    - [4. Model-Specific Adaptations](#4-model-specific-adaptations)
    - [5. State Management](#5-state-management)
    - [6. Iterative Revision Loops](#6-iterative-revision-loops)

## Overview

This document analyzes the UX and LLM prompt workflows for multi-turn operations in the PhysCloudResume application.

## 1. Fix Overflow / Does Content Fit Workflow

### UI Flow
- **Entry Point**: ResumeReviewSheet - "AI Resume Review" dialog
- **UI Selection**: User selects "Fix Overflow" from review type dropdown
- **Options**: Toggle for "Allow entity merge" to enable merging redundant entries
- **Model Selection**: Vision-capable models only (required for PDF image analysis)

### Prompt Structure & Conversation Flow

#### Iteration Loop (max 3 iterations by default):

1. **Initial Analysis**
   - Extract skills JSON from resume tree structure
   - Convert PDF to base64 image
   - Send to LLM with `buildFixFitsPrompt`:
     ```
     "Analyze the Skills & Expertise section in the resume image.
     Suggest modifications to make text more concise while preserving meaning.
     Return revised skills as JSON with specific format."
     ```

2. **Fix Fits Request** (Each Iteration)
   - Sends current skills JSON + resume image
   - LLM returns `FixFitsResponseContainer`:
     - `revisedSkillsAndExpertise`: Array of skill modifications
     - `mergeOperation`: Optional merge of redundant entries
   - Applies changes to resume tree nodes

3. **Content Fit Check**
   - Re-renders resume PDF
   - Sends new image with `buildContentsFitPrompt`:
     ```
     "Does all content fit on one page without overflow?
     Look at bottom of page for cut-off text.
     Return: {contentsFit: boolean, overflowLineCount: number}"
     ```
   - If content fits → Success
   - If not → Continue to next iteration

### Response Handling
- **Progress Updates**: Real-time status messages during each phase
- **Change Tracking**: Detailed log of what changed in each iteration
- **UI Updates**: 
  - Shows overflow line count
  - Displays merge operations
  - Lists all node changes with before/after values

### Special Features
- **Entity Merging**: Can combine redundant skills into single entries
- **Iterative Refinement**: Continues until content fits or max iterations reached
- **Visual Verification**: Uses actual PDF rendering for accurate fit detection

## 2. Generate Resume Revisions / Submit Feedback Workflow

### UI Flow
- **Entry Points**: **CURRENTLY BROKEN** - UnifiedToolbar migration incomplete
  - **Generate Button**: Non-functioning button in UnifiedToolbar (needs implementation)
  - **Clarify & Generate Button**: Non-functioning button in UnifiedToolbar (needs implementation)
  - **Legacy Option+Click**: Being eliminated in favor of separate buttons
- **Model Selection**: **MISSING** - Needs DropdownModelPicker implementation before LLM operations begin
  - Should be accessed via model selector sheet or modal attached to toolbar buttons
  - Currently uses `OpenAIModelFetcher.getPreferredModelString()` without user choice
- **Current Recommendation**: Wait for LLM refactoring (Phase 1-2) before implementing toolbar functionality
- **Clarifying Questions** (Optional, Clarify & Generate button only):
  - System analyzes resume and job context  
  - May ask up to 3 clarifying questions
  - User answers via ClarifyingQuestionsSheet
- **Revision Generation**: Based on context + answers (if any)

### Prompt Structure & Conversation Flow

#### Phase 1: Clarifying Questions (if enabled)
```swift
conversationHistory = [
    AppLLMMessage(role: .system, text: clarifyingQuestionsSystemPrompt),
    AppLLMMessage(role: .user, text: resumeContext)
]
```

LLM responds with:
```json
{
    "questions": [
        {
            "id": "q1",
            "question": "What specific achievements...",
            "context": "This helps highlight relevant experience"
        }
    ],
    "proceedWithRevisions": false
}
```

#### Phase 2: Process Answers & Generate Revisions
- Appends Q&A summary to conversation
- Requests revision suggestions
- Returns `RevisionsContainer` with array of `ProposedRevisionNode`

#### Phase 3: Iterative Revision Review Loop
**Entry Point**: ReviewView.swift - User review interface for AI revisions
**Iterative Process**: Multi-round feedback and refinement cycle

##### Step 1: Review Individual Revisions
- **UI Flow**: User reviews each `ProposedRevisionNode` individually
- **Review Options**:
  - **Accept**: Apply revision as-is (`.accepted`)
  - **Accept with Changes**: Edit revision before applying (`.acceptedWithChanges`)
  - **Restore Original**: Keep original text unchanged (`.restored`)
  - **Revise with Comments**: Reject with feedback for AI (`.revise`)
  - **Rewrite (No Comments)**: Reject without feedback (`.rewriteNoComment`)
  - **Mandated Change**: Force change with comments (`.mandatedChange`)
  - **No Change**: Accept original as appropriate (`.noChange`)

##### Step 2: Feedback Collection & State Management
```swift
// Each user decision creates a FeedbackNode
FeedbackNode(
    id: revisionNode.id,
    originalValue: revisionNode.oldValue,
    proposedRevision: revisionNode.newValue,
    actionRequested: userSelectedAction,
    reviewerComments: userComments,
    isTitleNode: revisionNode.isTitleNode
)
```

##### Step 3: Intelligent Feedback Processing
- **Apply Accepted Changes**: Immediately update resume tree nodes
- **Filter AI-Required Actions**: Extract nodes needing `.revise`, `.mandatedChange`, `.rewriteNoComment`, `.mandatedChangeNoComment`
- **Iterative Resubmission**: Only send rejected nodes back to AI for revision

##### Step 4: AI Resubmission Loop (AiCommsView.swift)
- **Context Preservation**: Maintain conversation history across revision rounds
- **Focused Revision**: AI only revises nodes that were rejected with feedback
- **State Synchronization**: 
  - `aiResub` flag triggers resubmission workflow
  - PDF re-rendering ensures current state for AI analysis
  - Safety timeouts prevent infinite loops

##### Step 5: Validation & Node Matching
- **Node Validation**: Ensure AI-returned revisions match existing resume nodes
- **ID Matching**: Cross-reference revision IDs with current tree structure
- **Content Validation**: Verify oldValue matches current node content
- **Tree Path Fallback**: Use tree structure for orphaned revisions

### Response Handling
- **Structured Output**: JSON with revision nodes
- **Conversation State**: Maintains full conversation history across all revision rounds
- **Fallback Parsing**: Multiple strategies for extracting revisions from response
- **Node Filtering**: Remove revisions for deleted/non-existent nodes between rounds
- **State Recovery**: Handle provider resets and maintain UI state consistency

## 3. Multi-Model Cover Letter Recommendation Workflow

### UI Flow
- **Entry Point**: MultiModelChooseBestCoverLetterSheet
- **Model Selection**: Checkbox selection of multiple models
- **Voting Schemes**: 
  - First Past The Post (FPTP): Each model votes for one letter
  - Score Voting: Each model allocates 20 points among all letters

### Prompt Structure & Conversation Flow

#### Parallel Processing:
- Each selected model evaluates all cover letters simultaneously
- Uses `CoverLetterRecommendationProvider` with model-specific configuration

#### FPTP Prompt:
```
"Review these cover letters and select the single best one.
Return: {bestLetterUuid: 'uuid', verdict: 'reasoning'}"
```

#### Score Voting Prompt:
```
"Allocate exactly 20 points among these cover letters based on quality.
Return: {scoreAllocations: [{letterUuid: 'uuid', score: number}], verdict: 'reasoning'}"
```

### Response Handling
- **Vote/Score Tallying**: Real-time aggregation as models complete
- **Progress Tracking**: Shows X of Y models completed
- **Summary Generation**: Uses o4-mini to synthesize all model reasonings
- **Persistence**: Saves vote/score counts to cover letter objects

### Special Features
- **Parallel Execution**: All models run concurrently
- **UUID Replacement**: Automatically replaces UUIDs with letter names in UI
- **Zero-Vote Cleanup**: Option to delete letters with no votes/points
- **Winner Selection**: Automatically identifies and can select winning letter

## 4. Batch Cover Letter Generation and Vote Workflow

### UI Flow
- **Entry Point**: BatchCoverLetterView
- **Modes**:
  - Generate New: Create letters from multiple models
  - Revise Existing: Apply revisions to existing letters
- **Revision Options**: improve, zissner, mimic

### Prompt Structure & Conversation Flow

#### Generation Phase:
1. **Base Generation** (per model):
   - Standard cover letter generation prompt
   - Each model creates initial letter

2. **Revision Generation** (optional):
   - For each base letter + revision type
   - Can use same model or different revision model
   - Revision prompts based on `EditorPrompts` enum

#### Batch Processing:
```swift
// Parallel task group execution
await withTaskGroup(of: GenerationResult.self) { group in
    for model in models {
        group.addTask { 
            // Generate base letter
            // Then generate revisions if requested
        }
    }
}
```

### Response Handling
- **Progress Updates**: Completed/Total operations counter
- **Error Resilience**: Continues even if some generations fail
- **Name Generation**: "Model Name" or "Model Name - Revision Type"
- **Cleanup**: Removes ungenerated drafts after completion

### Special Features
- **Parallel Generation**: All operations run concurrently
- **Model-Specific Handling**: Special logic for o1 models (no system messages)
- **Revision Chaining**: Can apply multiple revision types to same letter
- **"Same as Generating" Option**: Revisions can use original model

## Common Patterns Across Workflows

### 1. Structured Output Handling
- All workflows use typed response containers
- Fallback parsing strategies for non-compliant responses
- JSON schema generation for API requests

### 2. Progress Communication
- Real-time status updates during processing
- Visual progress indicators (progress bars, counters)
- Detailed change logs for transparency

### 3. Error Handling
- Request ID tracking to prevent race conditions
- Graceful degradation with fallback responses
- User-friendly error messages

### 4. Model-Specific Adaptations
- Vision capability checks for image-based workflows
- Special handling for o1 models (reasoning models)
- Provider-specific prompt adjustments

### 5. State Management
- Conversation history tracking
- Persistent storage of results
- UI state synchronization with async operations

### 6. Iterative Revision Loops
- **Human-in-the-Loop Feedback**: User review and approval cycles
- **Selective Resubmission**: Only rejected revisions returned to AI
- **State Preservation**: Maintain conversation context across revision rounds
- **Node Validation**: Ensure revision consistency with current document state
- **Incremental Application**: Apply accepted changes immediately while continuing iterations
- **Safety Mechanisms**: Timeouts and validation to prevent infinite loops
- **Multi-Action Support**: Rich set of user response options (accept, reject, edit, restore, etc.)

---

## 🚨 IMPLEMENTATION GUIDANCE FOR REFACTORING

### **ResumeReviseService Architecture**

The complex revision workflow logic currently embedded in AiCommsView.swift should be extracted into a dedicated service:

**ResumeReviseService Responsibilities:**
- **Revision State Management**: Track revision nodes and their states across feedback rounds
- **Feedback Processing**: Process user feedback arrays and determine which nodes need AI resubmission
- **Tree Node Operations**: Apply accepted changes to resume tree structure
- **Validation Logic**: Ensure revision node IDs match current tree state  
- **Conversation Coordination**: Work with LLMService to manage multi-turn revision conversations
- **State Persistence**: Maintain revision context across UI state changes

**AiCommsView Refactored Role:**
- **UI Coordination**: Handle user interactions and display updates
- **Progress Display**: Show revision progress and status messages
- **Service Integration**: Call ResumeReviseService methods and display results
- **Error Handling**: Present user-friendly error messages and recovery options

### **Start with Fix Overflow Workflow** 
This workflow is the most complex and demonstrates all key patterns:
- Image + text multimodal prompts
- Iterative refinement loops  
- Structured JSON responses with fallback parsing
- Real-time progress updates
- State validation between iterations

**Key Implementation Details:**
- Uses `@AppStorage("fixOverflowMaxIterations")` for user-configurable iteration limits
- PDF rendering with `resume.ensureFreshRenderedText()` between iterations
- Image conversion via `ImageConversionService.shared.convertPDFToBase64Image()`
- Node matching by ID with fallback to content matching

### **Critical State Management Patterns**

#### **Conversation Context Persistence** 
```swift
// Pattern from AiCommsView.swift - preserve context across provider resets
if chatProvider.appState == nil {
    let currentMessages = chatProvider.genericMessages
    let currentRevArray = chatProvider.lastRevNodeArray
    chatProvider = ResumeChatProvider(appState: appState)
    chatProvider.genericMessages = currentMessages
    chatProvider.lastRevNodeArray = currentRevArray
}
```

#### **Revision Loop State Synchronization**
```swift
// Pattern from ReviewView.swift - intelligent feedback filtering
let aiActions: Set<PostReviewAction> = [
    .revise, .mandatedChange, .mandatedChangeNoComment, .rewriteNoComment
]
let nodesToResubmit = feedbackArray.filter { aiActions.contains($0.actionRequested) }
```

### **Model Selection Integration Points**

1. **Toolbar Buttons**: Need DropdownModelPicker before operation starts
2. **Capability Filtering**: Vision models for image operations, structured output for JSON responses  
3. **Clarifying Questions**: Separate model picker in ClarifyingQuestionsModelSheet
4. **Multi-Model Operations**: CheckboxModelPicker for parallel execution

### **Error Handling Patterns**

#### **Network Resilience** (from AiCommsView.swift)
```swift
// Retry logic with timeout
if retryCount == 0 {
    retryCount += 1
    isRetrying = true
    chatAction(hasRevisions: true)
} else {
    showError = true
    errorMessage = "Request taking too long. Please try again."
}
```

#### **JSON Parsing Fallback** (implement in LLMService)
- Primary: Use structured output API
- Fallback 1: Manual JSON extraction from text response
- Fallback 2: Pattern matching for key fields
- Fallback 3: User-friendly error with retry option

### **Performance Optimization Opportunities**

1. **Parallel Task Groups** (from BatchCoverLetterGenerator):
```swift
await withTaskGroup(of: GenerationResult.self) { group in
    for model in models {
        group.addTask { /* parallel operation */ }
    }
}
```

2. **Request Deduplication**: Cache identical prompts to avoid redundant API calls
3. **Progressive Loading**: Stream responses for long-running operations
4. **Context Compression**: Summarize old conversation history for very long sessions

### **UI/UX Considerations for Refactoring**

- **Progress Indicators**: All multi-turn workflows show real-time progress
- **Cancellation**: Users can stop long-running operations
- **State Recovery**: Handle app backgrounding/foregrounding gracefully  
- **Error Recovery**: Always provide clear next steps when operations fail
- **Model Validation**: Show helpful errors when selected models lack required capabilities

### **Testing Priorities for Refactoring**

1. **Basic Operations**: Simple text requests with various models
2. **Structured Output**: JSON parsing with malformed responses
3. **Conversation Context**: Multi-turn conversations with provider resets
4. **Image Operations**: PDF conversion and vision model integration
5. **Error Scenarios**: Network failures, rate limits, invalid API keys
6. **Model Capabilities**: Automatic fallbacks and capability detection