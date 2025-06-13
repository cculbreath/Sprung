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



### Prompt Structure & Conversation Flow

#### Phase 1: Clarifying Questions (if enabled) ✅ **MIGRATED TO ClarifyingQuestionsViewModel**
```swift
// New architecture: ClarifyingQuestionsViewModel
let fullPrompt = await query.clarifyingQuestionsPrompt()
let questionsRequest = try await llmService.executeStructured(
    prompt: fullPrompt,
    modelId: modelId,
    responseType: ClarifyingQuestionsRequest.self
)
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

#### Phase 2: Process Answers & Generate Revisions ✅ **MIGRATED TO ResumeReviseViewModel**
- ✅ Clean handoff from ClarifyingQuestionsViewModel to ResumeReviseViewModel
- ✅ Appends Q&A summary to conversation via LLMService
- ✅ Requests revision suggestions using continueConversationStructured()
- ✅ Returns `RevisionsContainer` with array of `ProposedRevisionNode`

#### Phase 3: Iterative Revision Review Loop ✅ **MIGRATED TO ENHANCED NODE CLASSES**
**Entry Point**: ✅ RevisionReviewView.swift - Pure UI view with ViewModel delegation
**Iterative Process**: ✅ Multi-round feedback and refinement cycle managed by ResumeReviseViewModel

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

##### Step 2: Feedback Collection & State Management ✅ **ENHANCED NODE CLASSES**
```swift
// Enhanced FeedbackNode with business logic methods
let feedbackNode = currentRevisionNode.createFeedbackNode()
feedbackNode.processAction(userSelectedAction)
```

##### Step 3: Intelligent Feedback Processing ✅ **COLLECTION EXTENSIONS**
- **✅ Apply Accepted Changes**: `feedbackNodes.applyAcceptedChanges(to: resume)`
- **✅ Filter AI-Required Actions**: `feedbackNodes.nodesRequiringAIResubmission`
- **✅ Iterative Resubmission**: Only send rejected nodes back to AI for revision
- **✅ Enhanced Logging**: `feedbackNodes.logFeedbackStatistics()`, `logResubmissionSummary()`

##### Step 4: AI Resubmission Loop ✅ **RESUMEREVISEVIEWMODEL**
- **✅ Context Preservation**: Maintain conversation history via LLMService
- **✅ Focused Revision**: AI only revises nodes requiring resubmission
- **✅ State Synchronization**: 
  - `aiResubmit` flag triggers resubmission workflow in ViewModel
  - PDF re-rendering via `resume.ensureFreshRenderedText()`
  - Clean workflow orchestration without mixed concerns

##### Step 5: Validation & Node Matching ✅ **RESUMEREVISEVIEWMODEL**
- **✅ Node Validation**: Enhanced `validateRevisions()` method
- **✅ ID Matching**: Cross-reference revision IDs with current tree structure
- **✅ Content Validation**: Verify oldValue matches current node content
- **✅ Tree Path Fallback**: Use tree structure for orphaned revisions

### Response Handling ✅ **LLMSERVICE INTEGRATION**
- **✅ Structured Output**: JSON with revision nodes via LLMService
- **✅ Conversation State**: LLMService maintains conversation history with UUID tracking
- **✅ Fallback Parsing**: Enhanced JSON parsing strategies in LLMService
- **✅ Node Filtering**: ResumeReviseViewModel `validateRevisions()` removes non-existent nodes
- **✅ State Recovery**: Clean ViewModel architecture eliminates provider reset issues

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
- ✅ **Uses `LLMService.executeParallelStructured()`** instead of legacy provider

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
- ✅ **Uses CoverLetterService** instead of CoverChatProvider

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
