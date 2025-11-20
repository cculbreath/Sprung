# Implementation Plan: Phase 2 "Lead Investigator" Refactor

## 1. Overview
Refactor Phase 2 from a linear "Deep Dive Interview" to an asynchronous "Evidence Audit & Investigation" model. The LLM will act as a Lead Investigator, analyzing the user's Skeleton Timeline to generate a targeted "Evidence Request List". Users will fulfill these requests by uploading documents, which will be processed in parallel to generate Draft Knowledge Cards without blocking the chat.

## 2. Architectural Changes

### A. New Data Stores & Models
1.  **`EvidenceRequirement` Model**:
    *   Tracks specific evidence the LLM wants (e.g., "Dissertation for PhD", "Github Repo for Software Job").
    *   Links to a specific `timeline_entry_id`.
    *   Status: `requested`, `fulfilled`, `skipped`.
2.  **`DraftKnowledgeStore` (New Service)**:
    *   Holds `KnowledgeCardDraft` objects generated from background processing.
    *   Separates "Drafts" (unverified) from "Persisted" (verified) cards in `ArtifactRepository`.

### B. Tooling Updates
1.  **`RequestEvidenceTool` (New)**:
    *   Allows the LLM to add items to the Evidence Request List.
    *   Params: `timeline_entry_id`, `description`, `category` (paper, code, website, etc.).
2.  **`GenerateKnowledgeCardTool` (Update)**:
    *   Update to support "Background Mode" where it doesn't return to the chat stream but pushes to `DraftKnowledgeStore`.

### C. Service Orchestration
1.  **`IngestionPipeline` (New/Refactor)**:
    *   Chain `DocumentExtractionService` output directly into `KnowledgeCardAgent`.
    *   Trigger: When a file is uploaded and linked to an Evidence Request.
    *   Output: A `KnowledgeCardDraft` pushed to `DraftKnowledgeStore`.

## 3. Component Implementation Steps

### Step 1: Define Evidence Models
*   Create `Sprung/Onboarding/Models/EvidenceRequirement.swift`.
*   Update `StateCoordinator` to hold a list of `evidenceRequirements`.

### Step 2: Create Request Evidence Tool
*   Implement `RequestEvidenceTool.swift`.
*   Register in `PhaseTwoScript` allowed tools.
*   **Action**: LLM calls this tool -> Updates State -> UI shows "Requested Item".

### Step 3: Update Phase 2 Script
*   **File**: `Sprung/Onboarding/Phase/PhaseTwoScript.swift`.
*   **Prompt Overhaul**:
    *   **Role**: "Lead Investigator".
    *   **Instruction**: "Analyze the timeline. Immediately call `request_evidence` for high-value targets (papers, portfolios). Do NOT ask the user to describe them manually if they can upload them. While waiting for uploads, you may chat about context."
    *   **Objectives**: Replace `interviewed_one_experience` with `evidence_audit_complete` and `knowledge_base_sufficient`.

### Step 4: Parallel Ingestion Pipeline
*   **File**: `Sprung/Onboarding/Services/IngestionCoordinator.swift` (New).
*   **Logic**:
    *   Listen for `.artifactRecordProduced` events.
    *   If artifact is linked to an Evidence Request -> Trigger `KnowledgeCardAgent`.
    *   On success -> Emit `.draftKnowledgeCardProduced`.

### Step 5: UI/UX Implementation
*   **ToolPane Update**:
    *   Create `EvidenceRequestCard`: A checklist UI where users can drag-and-drop files onto specific requests.
    *   Create `DraftKnowledgeList`: A side-panel view showing "Processing..." states and "Review Draft" buttons.
*   **StateCoordinator**: Handle the new events to update these views.

## 4. Execution Order
1.  **Models & Store**: Define the data structures.
2.  **Tools**: Implement `request_evidence`.
3.  **Script**: Rewrite the Phase 2 prompt.
4.  **Pipeline**: Wire up the extraction-to-generation logic.
5.  **UI**: Build the Evidence Checklist and Draft Review views.

## 5. Questions / Validation
*   *Self-Correction*: Ensure `KnowledgeCardAgent` can handle "Timeline Entry" context when it's just an ID passed from the Evidence Request. We might need to fetch the actual JSON content of the timeline entry to pass to the agent.
