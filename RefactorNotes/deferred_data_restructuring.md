# Deferred Data Restructuring — Working Notes

Scope
- Capture what’s done so far, what remains, and concrete data‑model requirements derived from the earlier conversation about flexible, template‑driven resumes (schemaless JSON + manifest + LLM mask + order preservation).
- Actionable plan to move user templates into SwiftData while preserving current override semantics.

Current State (implemented)
- Export boundary
  - UI prompts/pickers moved out of service to `ExportTemplateSelection`; `ResumeExportService` stays orchestration‑only; renderer remains rendering‑only.
- Template loading (plain text, hot‑swappable)
  - Templates and CSS load from Documents (user overrides) with bundle fallback; no rebuild needed.
  - GRMustache used for HTML/PDF; text generator uses Mustache too.
- Context builder safety
  - Custom JSON parser removed. Tree → JSON context uses `TreeToJson` + `JSONSerialization` to produce `[String: Any]` (no stringly round‑trip at render sites).
  - Deterministic section order via `JsonMap.orderedSectionKeys`; child order via `myIndex`.
- LLM replacement toggles
  - Node‑level flags (`LeafStatus.aiToReplace`) and traversal export for LLM input.
- Secrets & config
  - API keys in Keychain; OpenRouter client built from `AppConfig`.
- DI & store lifetimes
  - Stable store lifetimes via `AppDependencies` and `.environment(...)` injection.

Deferred Work (to do)
1) Store templates inside SwiftData (replace Documents‑only storage)
   - Provide `Template` model(s) with HTML, CSS, manifest, assets, metadata (id, version, slug, timestamps).
   - Import one‑time from Documents (maintain backward compatibility) and prefer SwiftData storage at runtime.
   - Preserve override precedence: SwiftData user templates > app bundle; keep an explicit “active template” per resume.
   - Support partials/assets (and optional preview thumbnail) as separate SwiftData entities or binary blobs.

2) Generalized document + templating (schemaless projection)
   - Introduce a schemaless `JSONValue` (or AnyCodable) for resume “extensions” alongside the current Tree model.
   - Add `TemplateManifest` (JSON/YAML) per template declaring: required paths, bindings (contextKey → JSONPath/Pointer), defaults, and named transforms (date formatting, join, limit, sort).
   - Add `ContextBuilder` that projects `JSONValue` + typed core + tree into a clean Mustache context per manifest (logic‑light templates).
   - Keep plain‑text authoring: templates + manifest are editable in text; no recompilation needed.

3) LLM edit mask + patch applier (safe writes)
   - Define `LLMEditMask` using JSON Pointers/Paths (or stable node IDs) to represent user‑toggled writable fields.
   - Enforce mask both when constructing LLM prompts and when applying structured diffs.
   - Implement `PatchApplier` based on JSON Patch/Merge Patch semantics and maintain an audit log for undo/version history.

4) Order preservation — make it first‑class end‑to‑end
   - Continue to model user‑ordered collections as arrays (not dictionaries) and use `OrderedDictionary` where an ordered map is required.
   - Maintain stable IDs and `position` fields where needed; ensure ContextBuilder emits arrays that preserve order.
   - Ensure patching operations use index‑aware moves/adds/removes; verify via unit tests once a test harness is in place.

5) Resume–template linkage and versioning
   - Persist the selected template per `Resume` (explicit reference to SwiftData `Template`).
   - Support versioning of templates; detect drift and offer a non‑destructive upgrade path.
   - Allow per‑template settings (e.g., format variants) stored with `Template` or a small `TemplateSettings` model.

Data Requirements (from transcript)
- Templates must remain plain text and hot‑loadable at runtime (no app rebuild), with a small stable set of transforms/filters.
- The data format must evolve without rigid compile‑time schemas; templates should not need to change when data grows.
- Per‑field/section toggles for LLM replacement must be persisted and enforceable (mask limiting reads and writes).
- Order must be preserved deterministically across the pipeline (storage → context → rendering → patching).
- Validation should be possible per template (e.g., required fields/paths), with helpful author‑facing errors.

Proposed SwiftData Models (sketch)
- `Template` (model)
  - id (UUID), name (String), slug (String), version (String), createdAt/updatedAt (Date)
  - html (String, plain text), css (String?), manifest (Data/String?)
  - isCustom (Bool), isActive (Bool?)
  - relationship: assets: [TemplateAsset]

- `TemplateAsset` (optional, for images/partials)
  - id (UUID), filename (String), mimeType (String), data (Data)
  - template (inverse)

- `Resume` (existing + deferred fields)
  - template (Template?) — selected template reference
  - rawJSON (Data?) or extensions: [String: JSONValue] (deferred)
  - llmEditMask (Data?) — JSON Pointer list/structure (deferred)

Manifests & ContextBuilder (sketch)
- `TemplateManifest` (JSON/YAML)
  - requiredPaths: [JSONPath/Pointer]
  - bindings: { contextKey: JSONPath/Pointer }
  - transforms: { contextKey: ["formatDate:YYYY-MM", "join:", ...] }
  - partials/assets list
  - order options where relevant: `order: source|sortBy:field|custom`
- `ContextBuilder`
  - Input: (typed core + Tree + JSONValue extensions, manifest)
  - Output: [String: Any] Mustache context (logic‑light templates)

Migration Plan (templates → SwiftData)
- On first launch of the new version:
  1) Scan Documents override folder; import templates into SwiftData.
  2) Preserve slug/name/version; deduplicate by slug and most recent update.
  3) Mark imported templates as custom and set them active if they previously overrode bundle.
  4) Keep reading bundle templates as fallback; prefer SwiftData instances at runtime.

Risks & Mitigation
- Risk: User surprises if import changes precedence
  - Mitigation: Preserve previous override behavior; prompt once; allow “revert to bundle” per template.
- Risk: Manifest DSL drift/complexity
  - Mitigation: Keep a small stable transform set; version manifests; validate with clear messages.
- Risk: Patch application corrupts order or fields
  - Mitigation: Use JSON Patch semantics; restrict to masked paths; keep audit/undo.

Phasing & Next Steps
- Phase A (near‑term):
  - Add `Template` SwiftData storage and import flow.
  - Store selected `Template` on `Resume` and prefer SwiftData templates while keeping bundle fallback.
- Phase B (mid‑term):
  - Add `TemplateManifest` + `ContextBuilder` (schema‑on‑read); keep templates/manifest as plain text in SwiftData.
  - Introduce `JSONValue` extensions bag on `Resume` for schemaless data.
- Phase C (mid‑term):
  - Implement `LLMEditMask` + `PatchApplier` and audit log; enforce write scope and maintain ordering.

Notes
- “Stick a pin in” full data store generalization: the plan above sequences template storage work first, then manifest/context, then LLM mask/patch.
- All changes maintain the current UX and portability of templates while enabling future flexibility.

