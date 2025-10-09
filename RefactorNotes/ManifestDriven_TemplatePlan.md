# Manifest-Driven Template Architecture – Implementation Plan

Prepared: 2025-10-27  
Audience: Handoff reference for the next coding agent  
Goal: Fully eliminate hard-coded resume schema logic so template manifests drive tree construction, seed defaults, and editor behavior.

---

## 1. High-Level Objectives
- **Source-of-truth manifests**: Ensure every template ships with a JSON manifest persisted in SwiftData (`Template.manifestData`) and used to construct resume trees.
- **Seed alignment**: Seed creation and promotion rely exclusively on manifest-defined structure; migration populates seeds from legacy `ResModel` data only once.
- **UI consistency**: Tree editor and template editor render sections according to manifest types (arrays, key/value maps, etc.) without fallback heuristics.
- **Technical debt removal**: Retire `JsonMap`, `SectionType`, and any view-specific logic that infers structure from existing nodes.

---

## 2. Current State Snapshot
- `JsonMap`/`JsonToTree`/`ResumeTemplateDataBuilder` contain static maps of section names to structure. Manifest data is rarely present.
- Template editor’s manifest tab falls back to an empty stub because bundled templates do not provide manifests.
- `TemplateSeedStore` & `TemplateSeedMigration` pull JSON from legacy `ResModel`, but new resumes still depend on hardcoded logic to build trees.
- Tree UI (`NodeHeaderView`, `NodeLeafView`) assumes certain node layouts (e.g., name+value pairs) based on heuristics.

---

## 3. Implementation Phases

### Phase A – Manifest Bootstrap
1. **Restore bundled manifest files**  
   - Copy `archer-manifest.json` from commit `d4ea4731f62b627b29e97e26e905f9db51a3c26d` into `Resources/Templates/archer/`.  
   - Ensure the Typewriter template has an equivalent manifest (check historical commits or author anew).
2. **Importer updates**  
   - Extend `TemplateImporter.Worker.importTemplate` to require a manifest. Log & skip templates without one (future-proof).  
   - On first launch, persist manifest JSON into SwiftData (`Template.manifestData`).
3. **Backfill existing stores**  
   - Add a helper (command or migration) that iterates existing `Template` records, loads manifests from disk (Documents or bundle), and saves them to `manifestData`.
4. **Verification**  
   - Template editor manifest tab should now show full JSON. Document steps in `RefactorNotes/PhaseSP3_Progress.md`.

### Phase B – Manifest-Aware Tree Construction
1. **Extend `TemplateManifest.Section.Kind`**  
   - Map manifest type strings to richer semantics:  
     `string`, `array`, `arrayOfObjects`, `mapOfStrings`, `mapOfObjects`, `fontSizes`, `boolean`, etc.  
   - For backwards compatibility, interpret legacy types (`object`, `objectOfObjects`) by converting into the new enum values.
2. **`JsonToTree` refactor**  
   - Inject `TemplateManifest` into the initializer.  
   - For each section, consult the manifest section definition instead of `JsonMap`.  
   - Build nodes based on declared structure:  
     - `mapOfStrings`: treat entries as label dictionary (no duplicate name/value).  
     - `array`: children with values only.  
     - `arrayOfObjects`: create parent nodes, then populate fields according to the nested object schema (if provided).  
   - Remove or deprecate `JsonMap`, `SectionType`, and helper methods once manifest-backed logic covers all sections.
3. **`ResumeTemplateDataBuilder` refactor**  
   - Mirror `JsonToTree` changes so tree → JSON export uses manifest definitions.  
   - Provide a fallback path for templates lacking manifest (log a warning, use minimal heuristics).
4. **Tree editing rules**  
   - Replace heuristics in `ResumeDetailVM.addChild` & `NodeLeafView` with schema-driven layout decisions.  
   - Example: if manifest says `mapOfStrings`, new child defaults to `""` label & value; editing controls hide the name field for arrays of strings, etc.
5. **Testing**  
   - Manual: create new resume, modify section labels, promote to seed, create another resume—verify defaults align with manifest and no duplicate entry text.  
   - Automated (if time): unit tests for `JsonToTree` and `ResumeTemplateDataBuilder` with manifest fixtures.

### Phase C – Seed & Resume Creation Alignment
1. **Seed promotion**  
   - Ensure `TemplateEditorView.promoteCurrentResumeToSeed()` writes JSON conforming to manifest (no orphan sections).  
   - Consider storing a metadata header (e.g., manifest version) within seeds for future migrations.
2. **Resume creation**  
   - In `ResStore.create`, pass manifest defaults + template seed data to `ResumeTemplateContextBuilder`.  
   - Update `ResumeTemplateContextBuilder` merge logic to respect manifest-defined precedence (manifest defaults < seed < applicant profile).  
   - Add logging when sections appear in context but not manifest; use this to clean up stale data.
3. **Legacy cleanup**  
   - Once manifests and seeds drive everything, remove reliance on `ResModel` during new resume creation (keep migration file until final deletion).  
   - Document deprecation path for `ResModel` in `RefactorNotes/PhaseSP3_Progress.md`.

### Phase D – UI Polish & Tooling
1. **Template Quick Actions**  
   - Shorten the “Promote” button label or render on two lines; ensure the “Open Template Editor” button successfully invokes `AppDelegate.showTemplateEditorWindow()`.  
   - Add status messaging when manifest/seed data is missing.
2. **Editor affordances**  
   - Highlight unsaved manifest/seed changes across tabs.  
   - Consider schema visualization (e.g., show type next to section names) for clarity.
3. **Diagnostic commands**  
   - Optional CLI/script: dump manifest/seed for auditing, compare with runtime tree structure.

### Phase E – Remove Hardcoded Fallbacks
1. **Delete `JsonMap`, `SectionType`, and related fallback code** once manifest-driven logic covers all sections.  
2. **Audit other legacy helpers** (e.g., `TemplateSeedMigration`, `TemplateQuickActionsView`) to ensure they no longer reference hardcoded structures.  
3. **Documentation**  
   - Update `CLAUDE.md` / developer docs to explain manifest schema, editor workflow, and how to add new templates.

---

## 4. Risk & Mitigation
- **Missing manifests in user data**: Provide a one-time backfill. Log warnings so support can spot misconfigured templates.
- **Runtime regressions**: Introduce unit tests or snapshot comparisons (resume context before vs. after) using archived seeds.
- **Editor confusion**: Ensure manifest format is well-documented and validated in the editor; add helpful validation errors.
- **Migration sequencing**: Run manifest backfill before eliminating hardcoded fallbacks to avoid broken resume creation during the transition.

---

## 5. Deliverables & Definition of Done
- Bundled manifests stored in repo and persisted to SwiftData on bootstrap.
- Tree builder/exporter operate purely from manifest schema; Section Labels render without duplicated text.
- Template editor fully manipulates manifest/seed JSON and warns if a template lacks either.
- Quick actions panel buttons function correctly with adjusted layout.
- Legacy schema helpers removed or clearly deprecated, tests/QA confirm resume creation/export works for Archer + Typewriter.
- Documentation updated to describe manifest schema and template workflow.

---

## 6. Optional Enhancements (Post-Refactor)
- Add manifest versioning and migration support for template evolution.
- Provide schema-aware UI controls (e.g., specialized editors for sections like employment/publications).
- Build automated diff tooling comparing seed vs. manifest vs. live resume to aid curation.

---

This plan should equip the next agent with the timeline and concrete steps required to finish the manifest-driven architecture without reintroducing legacy assumptions. Continual logging and incremental validation are recommended throughout to confirm the manifests match runtime expectations.

> **Process Reminder**  
> Commit early and often—especially after landing each subtask above—and run `xcodebuild` (or the quick error-check build) with reasonable regularity so regressions are caught immediately.
