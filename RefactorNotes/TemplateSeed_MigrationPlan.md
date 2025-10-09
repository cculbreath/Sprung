# Template Seed & Manifest Management Migration Plan

Prepared: 2025-10-23  
Owner: Phase SP3 follow-up

---

## 1. Current State Audit
- `ResModel` persists sample JSON blobs and style metadata; new resumes call `ResStore.create(jobApp:sources:model:)`, which feeds `model.json` into `JsonToTree`.
- Template manifests (`Templates/<slug>/<slug>-manifest.json`) are imported but only govern section defaults/fallbacks during export; they are not editable in-app.
- The template editor (`TemplateEditorView`) manages HTML/TXT content only; no manifest or seed CRUD.
- Applicant profile (`Applicant.swift` + `ApplicantProfileView`) stores canonical user data but is not merged automatically while seeding new resumes.

Pain points:
1. Template schema defaults and sample data live in separate systems (manifest vs. `ResModel` JSON).
2. Template-specific defaults reset to placeholders when starting a new resume unless `ResModel` JSON was curated.
3. There is no GUI path to add/update manifests or template seed data.
4. We risk drift because per-resume edits overwrite the only copy of some facts.

---

## 2. Target Architecture Overview

### Core Concepts
- **Applicant Profile**: canonical, user-maintained facts (contact info, education, baseline employment, etc.). Persisted via SwiftData (already exists).
- **Template** (SwiftData) + **Template Assets**: existing store for HTML/TXT/CSS.
- **Template Manifest**: JSON document describing sections, defaults, editor hints. Stored as `Template.manifestData` (already imported).
- **Template Seed** *(new)*: structured JSON blob that provides default resume content per template beyond manifest defaults (bullet examples, default skills, etc.).
- **Resume Tree**: per-resume editable data; lives in SwiftData (`TreeNode` hierarchy).

### Seeding Flow for New Resume
1. Fetch manifest for template slug → create ordered section skeleton.
2. Merge in **Applicant Profile** values for relevant sections.
3. Merge in **Template Seed** data.
4. Persist to SwiftData (`TreeNode`, `FontSizeNode`) and present in the Resume tree UI.
5. Subsequent edits happen in the tree; exporting uses the manifest-guided builder.

### Template Management UI
Extend `TemplateEditorView` into a tabbed interface:
1. **Assets** tab *(existing)* – edit HTML/TXT/CSS.
2. **Manifest** tab – view/edit JSON manifest; validate against schema.
3. **Seed Data** tab – preview/edit template seed JSON; offer “Promote current resume to seed”.
4. (Optional) **Diff/Preview** tab – show diff between seed/profile vs. current resume for quick updates.

---

## 3. Migration Strategy

### Stage 0 – Preparatory Tasks
1. **Schema additions**  
   - Add `TemplateSeed` SwiftData model (`template`, `slug`, `seedData: Data`, timestamps).
   - Extend `Template` with `@Relationship var seed: TemplateSeed?`.
2. **Utility helpers**  
   - Add `TemplateSeedStore` (analogous to `TemplateStore`) for CRUD.
   - Shared merge helper to layer `ApplicantProfile`, manifest defaults, and seed data into a `[String: Any]` context.

### Stage 1 – Data Migration
1. Build SwiftData migration script:
   - Iterate existing `ResModel` entities.
   - Derive slug (`resModel.style.lowercased()`).
   - Upsert `TemplateSeed` for matching template slug with `seedData = resModel.json`.
   - Record mapping to support cleanup logging.
2. After migration, set a flag (e.g., `ResModelMigration.complete`) in persistent storage to avoid rerunning.
3. Back up exported JSON before mutation (write to `~/Documents/PhysCloudResume/MigrationBackups/`).

### Stage 2 – Resume Creation Rewrite
1. Modify `ResStore.create`:
   - Load template slug from job app/resume selection.
   - Retrieve manifest (`TemplateManifestLoader` or from SwiftData `Template.manifestData`).
   - Retrieve applicant profile snapshot.
   - Retrieve `TemplateSeed` JSON.
   - Merge into final context; convert to ordered tree via new helper (replacing `model.json` usage).
2. Ensure duplication logic copies current tree as before (no change).
3. Remove `ResModel` dependency from `JobAppStore`, `ResumeDetailVM`, and UI.

### Stage 3 – Template Editor Enhancements
1. **Manifest Tab**
   - Bind to `Template.manifestData`.
   - JSON editor with validation, auto-reformat, and “revert to file” option.
2. **Seed Tab**
   - Show `TemplateSeed.seedData` in JSON editor.
   - Buttons:
     - “Promote current resume” (let user pick from open resumes with matching template, run `ResumeTemplateDataBuilder.buildContext`, write to seed).
     - “Reset to manifest defaults” (optional).
3. Add status indicators (e.g., unsaved changes, validation errors).

### Stage 4 – Profile Integration
1. Create merge helper that maps `ApplicantProfile` fields → manifest keys (e.g., profile.contact → `contact`, profile.education[] → manifest if section exists).
2. Add UI within Applicant Profile to mark sections as “use in all templates” vs. “template-specific”.
3. Provide refresh action in resume UI to reapply profile data to current resume (with diff or confirmation).

### Stage 5 – ResModel Decommission
1. Remove all `ResModel` references from codebase (models, store, views).
2. Delete SwiftUI views `ResModelView`, `ResModelFormView` once replaced by template editor tabs.
3. Drop `ResModel` from SwiftData model graph; add migration step to delete entity after data transfer.
4. Update documentation, menus, and commands to reflect new workflow.

---

## 4. Implementation Checklist

### Models & Storage
- [ ] Define `TemplateSeed` and migration.
- [ ] Update `TemplateStore` or add `TemplateSeedStore`.
- [ ] Wire `Template` ↔ `TemplateSeed` relationship in SwiftData schema.

### Resume Creation
- [ ] Implement context builder layering manifest → profile → seed.
- [ ] Update `JsonToTree` initializer to accept `[String: Any]` context instead of `ResModel.json`.
- [ ] Adjust `ResStore.create` to use new builder.
- [ ] Ensure tests/spot-checks verify tree population parity.

### Template Editor UI
- [ ] Introduce tab view with “Assets / Manifest / Seed”.
- [ ] Manifest editor controls (load/save/validate).
- [ ] Seed editor controls (edit, promote from resume, reset).
- [ ] Feedback UI (validation errors, success toasts).

### Applicant Profile Enhancements
- [ ] Add mapping layer for profile sections.
- [ ] Provide UI toggles per section for template seeding.
- [ ] Implement “refresh profile data” action within resume.

### Cleanup & Documentation
- [ ] Remove `ResModel` model/store/views after migration.
- [ ] Update help docs, onboarding tips, and developer notes.
- [ ] Add developer migration guide referencing this plan.
- [ ] QA: create new resume using existing template, confirm defaults pull from seeds/profile; switch templates, verify profile data persists.

---

## 5. Validation Strategy
1. **Unit/Integration checks**
   - Verify that `ResumeTemplateDataBuilder` output is identical before/after migration when fed legacy JSON.
   - Confirm manifest defaults + seed + profile merge is deterministic.
2. **Manual QA scripts**
   - Create baseline resume (template Archer) → promote to seed → create new resume → ensure defaults match promoted version.
   - Switch template to Typewriter → confirm contact/education etc. come from profile, not stale Archer seed.
   - Modify profile contact info → create new resume → confirm updates apply automatically.
3. **Regression testing**
   - Export PDF/TXT and diff against pre-migration exports.

---

## 6. Open Questions / Follow-Ups
- Decide on storage format for `TemplateSeed`: raw JSON string vs. structured SwiftData child objects. (Lean toward JSON for symmetry with manifests, but consider schema validation.)
- Determine merge precedence rules when profile + seed both provide values for the same field (likely profile wins for canonical sections).
- Consider versioning manifests/seeds to allow template evolution without clobbering existing resumes.
- Evaluate whether applicant profile should support multiple personas (e.g., Contractor vs. Educator) and how that interacts with template seeds.

---

## 7. Timeline Rough Cut
1. **Week 1** – Model work & migration scaffolding (TemplateSeed, data transfer, helper utilities).
2. **Week 2** – Resume creation refactor + seed/profile merge + preliminary QA.
3. **Week 3** – Template editor UI tabs + promote-to-seed workflow.
4. **Week 4** – Applicant profile integration, clean-up, docs, final QA, remove `ResModel`.

Buffer time accounts for SwiftData schema migrations and manual testing against real user data.

---

## 8. Deliverables
- New SwiftData entity `TemplateSeed` with migration and populated data.
- Updated resume creation pipeline using manifest/profile/seed layering.
- Tabbed template editor supporting manifest & seed management.
- Updated applicant profile integration.
- Removal of `ResModel` and associated UI.
- QA report confirming export parity and repeatable seeding.
