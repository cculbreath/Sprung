# Onboarding Interview – LLM Tools Specification (v2)

**Version:** 2.0  
**Updated:** 2025-10-25T01:35:38.293508Z

This is the single source of truth for *LLM-invocable* tools. The design keeps the model vendor‑agnostic: **the LLM sees tool names and schemas only**; all provider/model choices happen inside the app. This preserves a dynamic, LLM-guided experience while keeping implementation details local.

---

## 0) Tool Execution Model (unchanged in spirit)

1. Model decides to use a tool (function calling).  
2. The app executes the tool locally.  
3. The tool may **return immediately**, **enter a waiting state** (e.g., for user input), or **error**.  
4. Tool responses are sent back to the model via the Responses API.  
5. The orchestrator (actor) remains the *single authority* over session state & phase transitions.

```swift
protocol InterviewTool {
    var name: String { get }
    var description: String { get }
    var parameters: JSONSchema { get }
    func execute(_ params: JSON) async throws -> ToolResult
}

enum ToolResult {
    case immediate(JSON)
    case waiting(String, ContinuationToken)  // waitingReason, token
    case error(ToolError)
}
```

---

## 1) Capabilities (sanitized) – **capabilities.describe**

**Purpose:** Inform the model which tools are currently available **without** exposing backend vendors or model ids.

**Name:** `capabilities.describe`  
**Parameters:** none  
**Response:**

```json
{
  "version": 2,
  "tools": {
    "get_user_option":        { "status": "ready" },
    "get_user_upload":        { "status": "ready", "accepts": ["pdf","docx","txt","md"], "max_bytes": 10485760 },
    "get_macos_contact_card": { "status": "ready" },
    "submit_for_validation":  { "status": "ready", "data_types": ["applicant_profile","skeleton_timeline","experience","education","knowledge_card"] },
    "persist_data":           { "status": "ready", "data_types": ["applicant_profile","skeleton_timeline","knowledge_card","artifact_record","writing_sample","candidate_dossier"] },
    "extract_document":       { "status": "ready", "supports": ["pdf","docx"], "ocr": true, "layout_preservation": true }
  }
}
```

> Notes: Boolean capability flags (e.g., `ocr`, `layout_preservation`) are functional, not vendor identifiers. The app may change providers without changing this manifest.

---

## 2) Core Tools (existing + updated enums)

### 2.1 **get_user_option** (unchanged)
Present multiple choice options and collect selection(s).

### 2.2 **get_user_upload** (unchanged surface)
Request files from the user.
- `acceptedFormats` default remains `["pdf","docx","txt","md"]`
- Returns file `storageUrl` and metadata
- **No inline text extraction** here (moved to `extract_document`).

### 2.3 **submit_for_validation** (enum normalized)
Display data for user review & editing before it is marked complete.

**Parameters**
```json
{
  "type": "object",
  "required": ["dataType","data"],
  "properties": {
    "dataType": {
      "type": "string",
      "enum": ["applicant_profile","skeleton_timeline","experience","education","knowledge_card"]
    },
    "data": {"type": "object"},
    "message": {"type": "string"}
  }
}
```

**Response**
```json
{
  "status": "approved" | "modified" | "rejected",
  "data": {}, 
  "changes": [{"field":"basics.email","oldValue":"x","newValue":"y"}],
  "userNotes": "optional"
}
```

### 2.4 **get_macos_contact_card** (existing surface)
Returns ApplicantProfile-shaped data when permission is granted; otherwise returns a friendly execution error with guidance to enter data manually.

---

## 3) **New** Universal Document Extraction – **extract_document**

**Why:** The model should call a single, vendor‑agnostic tool for any PDF/DOCX. The app handles OCR, layout, and provider/model selection internally. **All PDFs go through this tool**, independent of end use.

**Name:** `extract_document`

**Parameters**
```json
{
  "type": "object",
  "required": ["file_url"],
  "properties": {
    "file_url":        {"type":"string","description":"app-local URL from get_user_upload"},
    "purpose":         {"type":"string","enum":["resume_timeline","generic"],"default":"generic"},
    "return_types":    {"type":"array","items":{"type":"string","enum":["artifact_record","applicant_profile","skeleton_timeline"]},"default":["artifact_record"]},
    "auto_persist":    {"type":"boolean","default":false},
    "timeout_seconds": {"type":"integer","default":60}
  }
}
```

**Behavior (app-side)**  
- Detects file type and routes to configured extractor.  
- **If the file is a résumé-like document** and `return_types` allows it: also produce `applicant_profile` and/or `skeleton_timeline` with confidence & quality flags.  
- **If scanned/unsupported**: return `artifact_record.status="unparsable"` with `quality.issues=["unparsable_no_text"]` and keep original blob.  
- **No vendor/model strings** are exposed in the tool result.

**Response**
```json
{
  "status": "ok" | "partial" | "failed",
  "artifact_record": {},
  "derived": {
    "applicant_profile": {}, 
    "skeleton_timeline": {} 
  },
  "quality": {"extraction_confidence": 0.0, "issues": []},
  "persisted": false
}
```

---

## 4) Persistence – **persist_data**

**Parameters**
```json
{
  "type": "object",
  "required": ["dataType","data"],
  "properties": {
    "dataType": {
      "type":"string",
      "enum":[
        "applicant_profile","skeleton_timeline","knowledge_card",
        "artifact_record","writing_sample","candidate_dossier"
      ]
    },
    "data": {"type":"object"},
    "upsert": {"type":"boolean","default": true}
  }
}
```

**Response**
```json
{ "status":"ok", "id":"...", "version":1 }
```

---

## 5) Phase-safe usage

Use **`capabilities.describe`** to inform planning. The orchestrator sets an **allowed tools list** per phase (e.g., Phase 1: `get_user_upload`, `extract_document`, `submit_for_validation`, `persist_data`). The app enforces allowed tools; the model can plan freely within that sandbox.

---

## 6) Error & Waiting Semantics

All tools may return:
- `waiting(reason, token)` when user action is required.  
- `error(executionFailed("message"))` with user-safe messages.  
- `immediate(json)` for successful, synchronous responses.

---

## 7) Contract Tests (minimum)

1. `extract_document` returns `artifact_record` with `status!="failed"` for a text-based PDF.  
2. `extract_document` returns `status="partial"` and `issues` contains `"unparsable_no_text"` for a scanned PDF when OCR is not available.  
3. `submit_for_validation` echoes `status` and optional `data` diffs.  
4. `persist_data` stores and returns a stable id.

