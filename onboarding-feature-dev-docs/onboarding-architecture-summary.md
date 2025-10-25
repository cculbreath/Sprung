# Onboarding Interview — From Rigid Specs to a Dynamic Middle‑Ground

## 1) What felt rigid in the original dev‑docs
The first round of dev‑docs skewed toward **hard‑coded flows and model/vendor coupling**, which limited the original “coach‑like, decide‑and‑act” spirit of the onboarding experience. In practice this meant:
- The orchestrator logic lived mostly in app code, not in the LLM’s planning loop.
- PDF handling referenced a specific model/provider path in spec space (e.g., naive local decode or direct provider coupling), leaking implementation choices into the model’s world.
- Tools were present but not the *single* abstraction point; some steps mixed UI, business rules, and model selection in one place.
These choices increased reliability, but also reduced *agentic flexibility* and raised maintenance risk whenever vendors/models change. (See the Clean‑Slate plan and Executive Summary for examples of the earlier stance.) fileciteturn0file5 fileciteturn0file7

## 2) Restoring the original spirit (and what that entails)
Your north star was an **LLM‑guided interview** that can accept *any* artifact, choose the right micro‑step, and keep momentum without peppering the user with questions. To restore that spirit safely we:
- Put the **LLM back in charge of micro‑planning** (coach persona + allowed tools), while the app enforces capability boundaries and schema contracts. fileciteturn0file14
- Make **tools vendor‑agnostic**: the model calls `extract_document` / `get_user_upload` / `submit_for_validation` / `persist_data`, and the app chooses providers locally. fileciteturn0file13
- Treat **any PDF as extract‑first**: every uploaded PDF goes through the extraction workflow before use. (No provider IDs or layouts are visible to the model.) fileciteturn0file10
- Exploit **GPT‑5 agentic controls**—`reasoning.effort` and `text.verbosity`—to dial speed vs. depth per step, and reuse reasoning across tool calls via the Responses API. fileciteturn0file1 fileciteturn0file2

### Concrete implications
- The coach can decide “upload → extract → validate → persist” end‑to‑end using only tools; the app selects OCR/layout engines and handles failures. fileciteturn0file10 fileciteturn0file13
- Artifacts, timelines, knowledge cards, and applicant profiles flow through **schema‑first validation** so the LLM can act boldly while the app guards correctness. fileciteturn0file13
- The UX narrative explicitly reflects this dynamic, pausable flow with clear waiting states. fileciteturn0file14

## 3) The middle‑ground architecture you can build on today
This architecture keeps the system **dynamic where it matters** and **deterministic where it must**:

**a) Orchestrator (LLM) + Allowed Tools**  
- Orchestrator uses GPT‑5 (default), with step‑level `reasoning.effort` and `text.verbosity`.  
- Allowed tools per phase keep behavior bounded and predictable. fileciteturn0file8 fileciteturn0file1

**b) Tool Executor (app)**  
- Owns provider selection (e.g., Gemini via OpenRouter for PDFs), retries, and error semantics—**never** surfaced to the LLM.  
- Returns structured outputs and quality flags only. fileciteturn0file10

**c) Minimal State + Checkpoints**  
- Phase + objectives + `waiting` flag; actor‑backed for concurrency; small, testable transitions. fileciteturn0file12

**d) Single‑source Tool Spec**  
- Canonical schemas and continuation tokens; consistent error/waiting patterns across all tools. fileciteturn0file13

**e) UX Narrative**  
- Coach explains “why,” pauses at uploads/validations, and resumes with extracted structure ready for confirmation. fileciteturn0file14

## 4) This is already incorporated in the new docs
The shipped dev‑docs encode this middle ground:
- **Final Implementation Guide** — model policy (GPT‑5 family), Responses API usage, services split. fileciteturn0file8
- **Tool Specification (v2)** — vendor‑agnostic tools and schemas (incl. deprecating inline PDF text). fileciteturn0file13
- **PDF Extraction Spec (v2)** — any‑PDF‑first pipeline handled locally (Gemini via OpenRouter), invisible to the LLM. fileciteturn0file10
- **Workflow Narrative & UX** — restored interview “spirit” with a dynamic but bounded coach. fileciteturn0file14
- **Executive Summary** — rationale, model selection, and scope decisions at a glance. fileciteturn0file7

You can move prior docs into **`dev-docs/legacy/`** and install these as the new canonical set. For API reference, **OpenAI GPT‑5 docs** are available under **`dev-docs/open-ai-gpt-5/`** (verbosity/minimal‑reasoning/custom tools/allowed tools list, and function‑calling guide). fileciteturn0file1 fileciteturn0file2 fileciteturn0file3 fileciteturn0file0

---

## Appendix — Key principles to keep us honest
1. **The LLM sees tools, not vendors.**  
2. **Any PDF → extract first.**  
3. **Schemas at the edges; freedom inside.**  
4. **Reasoning budget matches the step.**  
5. **Small state, strong checkpoints.**

