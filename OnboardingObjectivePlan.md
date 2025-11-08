# Onboarding Objective & Workflow Fix Plan

## Goals
- Keep existing user sessions functional after the Phase overhaul.
- Ensure workflow automation (developer messaging + auto-start logic) fires with accurate context.
- Reduce duplication between phase prompts, workflow metadata, and ledger configuration.

---

## 1. Migrate Saved Objective Snapshots
1. **Add snapshot schema versioning**
   - Introduce `StateSnapshot.version` with a default for pre-migration checkpoints.
   - Persist the value in `Checkpoints.save` and restore it when loading.
2. **Re-register canonical objectives on restore**
   - After `objectiveStore.restore`, call a new helper that diff’s against `ObjectiveStore.objectiveMetadata` and registers any missing IDs for the saved phase.
   - For renamed/removed objectives, consider marking legacy IDs as `skipped` with a `source:"migration"` note so the ledger stays coherent.
3. **Backfill statuses for new objectives**
   - Decide policy per objective (e.g., assume `contact_source_selected` is `completed` if `applicant_profile` already was, otherwise leave `pending`).
   - Implement this mapping inside the migration helper and document it near `objectiveMetadata` to keep future changes transparent.
4. **Add regression coverage**
   - Unit-test restoring a pre-migration snapshot to ensure new objectives exist and can transition.
   - Include a scenario where an in-progress phase resumes and the LLM can complete newly added objectives without errors.

## 2. Fix Workflow Auto-Start Status Emission
1. **Use canonical enum raw values**
   - Replace the hardcoded `"inProgress"` string in `ObjectiveWorkflowEngine.checkAndAutoStartDependents` with `ObjectiveStatus.inProgress.rawValue`.
2. **Add guardrail test**
   - Actor test that asserts the engine emits valid statuses and that `StateCoordinator` transitions the objective to `in_progress` when dependencies are satisfied.
3. **Observe logs**
   - Confirm the "Invalid objective status" warning disappears and auto-started objectives now trigger `onBegin` handlers.

## 3. Propagate Rich Objective Metadata
1. **Extend tool schema**
   - Update `SetObjectiveStatusTool` to accept optional `source`, `notes`, and a generic `details` map (validated as string→string) so the LLM can pass context.
2. **Thread metadata through coordinator + store**
   - Modify `OnboardingInterviewCoordinator.updateObjectiveStatus` to forward the extra fields when publishing `.objectiveStatusUpdateRequested`.
   - Update `ObjectiveStore.setObjectiveStatus` to persist `details` (likely in the existing `notes` or by adding a dedicated field) and include them when emitting `.objectiveStatusChanged`.
3. **Teach `ObjectiveWorkflowEngine` to merge detail payloads**
   - Parse the new field(s) into `ObjectiveWorkflowContext.details`, ensuring Phase scripts receive the values they expect (e.g., `source`, `mode`, `artifact_id`).
4. **Document expected detail keys**
   - For each workflow in `PhaseOneScript`, note the detail keys the LLM should provide so prompt authors and tool-call logic stay aligned.

## 4. Enable Auto-Start Where Needed
1. **Identify objectives that should auto-start**
   - Example candidates: `contact_data_collected` (after source selection), `contact_photo_collected` (after validation), dossier seed prompts.
2. **Set `autoStartWhenReady: true`**
   - Update the relevant `ObjectiveWorkflow` definitions in `PhaseOneScript` (and future phases) to opt in once dependencies are met.
3. **Verify runtime behavior**
   - Use simulated objective updates to confirm the engine emits `in_progress` transitions automatically and Phase instructions fire without manual `set_objective_status` calls.

## 5. Consolidate Objective Definitions
1. **Choose a single authoritative data structure**
   - e.g., a `PhaseObjectiveCatalog` describing hierarchy, required flags, workflows, tool allowances, and prompt copy.
2. **Generate derived artifacts**
   - Build helper methods that produce:
     - `requiredObjectives` arrays for `PhaseScript`
     - `objectiveMetadata` entries for `ObjectiveStore`
     - Prompt sections / ledger diagrams used in developer messages.
3. **Refactor existing files**
   - Replace the hand-maintained tables in `PhaseOneScript` and `ObjectiveStore` with data loaded/generated from the catalog to prevent divergence.
4. **Add validation**
   - Introduce a lightweight test that ensures every objective referenced in prompts/workflows exists in the catalog and vice versa.

---

## Sequencing / Deployment Notes
1. Ship the snapshot migration + status fix together to unbreak existing sessions.
2. Follow with the metadata propagation & auto-start updates so the richer workflows actually communicate context.
3. Tackle the single-source-of-truth refactor once the behavior is stable, since it is larger in scope but lower immediate risk.
