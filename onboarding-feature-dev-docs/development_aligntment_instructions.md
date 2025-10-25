## Development Alignment Instructions

As you can tell, there has been a healthy revision process in establishing our development plan for this cycle. The dev docs may contain some contridictions, this document is intended as the autority to resolve them.


1. **Tool-only PDF extraction (accepted)**
   Route *all* PDF/DOCX through the `extract_document` tool.
   Delete or ignore any orchestrator-level provider calls or prompts.
   Keep vendors invisible to the LLM.

2. **snake_case only (accepted)**
   Normalize every `dataType`/enum and tool field to `snake_case` across
   `submit_for_validation` and `persist_data`.

3. **(As before; unchanged)**
   Add `candidate_dossier` to `persist_data`’s enum so it matches the
   narrative and state machine usage.

4. **Actor vs. LLM**
	The LLM can intitiate and override the actor objective test criteria to force advance to next phase. There are some restrictions, and it requires user approval. See next_phase_tool.md the guidance and workflow in next_phase_tool.md supercedes any other dev doc phase advancement criteria.
  

5. **Allowed-tools gating (accepted; unchanged)**
   At each Responses-API turn, pass only the phase-allowed tools to the
   model. Do not expose off-limits tools in the `tools:` field.
   (Prose alone isn’t enough.)

6. **SettingsView: user picks PDF extractor model (accepted)**
   Keep the Settings UI where the user chooses which model handles
   PDF extraction (default: Gemini 2.0 Flash).
   Enforcement lives *inside* the tool executor.
   Never surface provider or model IDs to the LLM or prompts.
   `capabilities.describe` may expose functional flags
   (for example, `ocr: true`) but never vendor names.

7. **Deprecated `extractedText` (fine)**
   Do not populate or consume `extractedText` from `get_user_upload`;
   all extraction flows through `extract_document`.
   Keep the field only for backward-compatibility comments.

9. **Phase-3 objective (OK)**
   Spec and state machine both require `"dossier_complete"` in Phase 3.
   Leave this behavior as-is.
