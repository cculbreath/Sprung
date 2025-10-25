# PDF Extraction Specification for Onboarding Interview (v2)

**Status:** M1.5 soft‑launch (fallback: naive); M2 mature pipeline  
**Updated:** 2025-10-25T01:35:38.293508Z

**Design change:** Extraction is executed via the **`extract_document` tool** (vendor‑agnostic). The LLM never calls providers directly; implementation details remain local.

---

## 1) Goals

- Make **every PDF** pass through a robust extraction workflow (OCR + layout when available).  
- Hide vendor/model specifics from the LLM.  
- Produce consistent products:
  - `artifact_record` (always)  
  - `applicant_profile` (if résumé-like)  
  - `skeleton_timeline` (if résumé-like)

---

## 2) Architecture

```
User → get_user_upload ───► Orchestrator (LLM) ── tool: extract_document(file_url)
                                           ▼
                                    ToolExecutor (local)
                                           ▼
                     Provider pipeline (e.g., OCR, layout model)  // hidden from LLM
                                           ▼
                           Derived outputs + quality flags
                                           ▼
                  submit_for_validation (optional) → persist_data
```

- The **LLM** only sees `extract_document`.  
- The **ToolExecutor** selects the current provider chain:
  -multimodal/OCR provider enabled (e.g., Gemini Flash) with layout preservation.
- The tool returns **functional** flags (e.g., `ocr: true`) via `capabilities.describe`, never vendor ids.

---

## 3) Tool Contract (summary)

See full spec in *Tools Specification (v2)* → `extract_document`.

Key guarantees:
- **Idempotent** for the same `file_url` (within temp cache window).  
- Returns `artifact_record` even if résumé detection fails.  
- Populates `derived.skeleton_timeline` and/or `derived.applicant_profile` **only** on confident detection.  
- Includes `quality.extraction_confidence` and `issues[]` when relevant.

---

## 4) Résumé Detection & Outputs

- Perform lightweight detection using file heuristics (extension, MIME type, text density) and model-assisted classification.
- On confirmed résumé detection:
  - Send the full file (PDF or DOCX) to the Gemini 2.0 Flash extractor via OpenRouter.
  - Prompt the LLM directly to produce two structured outputs in a single JSON object:

    {
      "skeleton_timeline": {
        "experiences": [ ... ],
        "meta": { "timeline_complete": true | false }
      },
      "applicant_profile": {
        "name": "...",
        "email": "...",
        "phone": "...",
        ...
      }
    }

  - Let Gemini mark `meta.timeline_complete = false` whenever ambiguities or date gaps are detected.
  - The InterviewOrchestrator then:
    1. Sends each section through `submit_for_validation` for user confirmation.
    2. Persists the approved data via `persist_data`.
    3. Marks the corresponding objectives (`applicant_profile`, `skeleton_timeline`) as complete.


---

## 5) Validation flow

1. After `extract_document`, the LLM **may** call `submit_for_validation` on `applicant_profile` and/or `skeleton_timeline`.  
2. User approves/edits; on `approved` or `modified`, the LLM calls `persist_data`.  
3. The actor marks Phase 1 objectives as complete.

---

## 6) Error handling

- **Scanned/No text:** return `status="partial"`, set `issues+=["unparsable_no_text"]`, keep original blob.  
- **Time out:** return `status="failed"` with a user‑safe message; retry policy in Error Recovery doc.  
- **Unsupported type:** tool returns `error(executionFailed("Unsupported format"))`.

---

## 7) Settings

- AppSettings may contain provider keys and toggles.  
- Changing providers **never** changes the LLM surface area.

---

## 8) Test matrix (minimum)

- Text‑based simple résumé → timeline + profile populated.  
- Multi‑column résumé → timeline present; confidence ≥ 0.6.  
- Scanned PDF → `partial` with `unparsable_no_text`.  
- Non‑résumé PDF (e.g., whitepaper) → `artifact_record` only.
