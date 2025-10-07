# Deferred Backup & Restore — Requirements and Plan

Goal
- Ensure user SwiftData content is preserved automatically before schema changes and is easy to back up/restore on demand, without disrupting normal app usage.

Current State (implemented)
- Preflight backup on startup (once per 24h) before opening/migrating the store
  - Code: `SwiftDataBackupManager.performPreflightBackupIfNeeded()` called before model container creation.
  - File patterns copied from Application Support: `.sqlite`, `.sqlite-shm`, `.sqlite-wal`, and `default.store` variants.
  - Destination: `~/Library/Application Support/PhysCloudResume_Backups/<ISO8601 timestamp>/`.
  - Restore helper: `SwiftDataBackupManager.restoreMostRecentBackup()` (manual, destructive overwrite).

Requirements
- Functional
  - Automatic daily backup before any migration or schema access.
  - Manual “Backup Now” and “Restore” controls in Settings (with confirmations and safety warnings).
  - Back up all store artifacts required for full recovery.
  - Clear success/error reporting and discoverable logs.
- Non‑Functional
  - Zero performance impact on the critical path (run once/day; async where possible).
  - Storage bounded (retention policy) to avoid unbounded disk growth.
  - Platform‑friendly: no extra entitlements; works in sandboxed macOS app context.

Data Model & Files
- Source: `Application Support` (SwiftData default store location)
- Targets: all SwiftData store files (`*.sqlite`, `*.sqlite-shm`, `*.sqlite-wal`, `default.store*`).
- Destination: App Support/`PhysCloudResume_Backups/` with timestamped folders.

Plan (phased)
- Phase A (implemented)
  - Add `SwiftDataBackupManager` and call preflight backup before opening/migrating the store.
  - Provide a basic restore helper for manual recovery.
- Phase B (UI integration)
  - Settings → “Data Safety” section:
    - Buttons: “Backup Now…”, “Restore Latest…”, “Open Backups Folder…”.
    - Confirmations for restore (destructive), with backup path display.
    - Show last backup timestamp and the number of existing backups.
  - Menu command (optional) for “Open Backups Folder”.
- Phase C (operational polish)
  - Retention policy (e.g., keep last 7 daily backups + last 3 weekly)
  - Optional compression (.zip) for each backup folder (tradeoff: CPU vs. disk)
  - Progress notifications and error surfaces in UI.
  - In‑app log viewer link or “Copy diagnostics” for backup/restore runs.

UX & Safety
- Backup Now: runs on a background task; show spinner/toast, then “Backup created at <path>”.
- Restore Latest: requires two confirmations; suggests quitting and re‑launching on completion.
- Open Backups Folder: opens Finder to `PhysCloudResume_Backups` root.

Testing Strategy
- Unit/integration (in CI or local harness):
  - Use a temporary directory override (dependency‑injected) for Application Support.
  - Seed fake store files, run backup, verify file set and contents copied.
  - Simulate restore: delete sources, restore latest, verify files match.
- Manual app validation:
  - Ensure preflight backup fires once/day and logs path.
  - Trigger migration after backup (no data loss).

Risks & Mitigations
- Large stores → slow copies: show progress and run async; add size checks; optional compression.
- Partial copies on crash: copy to temp then atomically move into place.
- Disk usage: enforce retention policy; allow user override in Settings.
- Sandbox path variance: rely on `FileManager.default.urls(for:.applicationSupportDirectory, ...)` only.

Security & Privacy
- Backups include personal data (resumes, notes). Never upload automatically.
- Store backups under user account only; respect file permissions.
- Optionally redact PII when exporting diagnostics (separate task).

Future Enhancements
- Versioned metadata file per backup (schema, app version, size, counts).
- Backup templates (once templates move to SwiftData) alongside the store.
- Scheduled backups (weekly) with user‑configurable cadence.

Summary
- Data safety is enforced by automatic preflight backups and a simple manual restore path.
- Next work: UI hooks (Settings), retention policy, and optional compression.
