# Phase 8 — NotificationCenter Cleanup

Status: ✅ Complete  
Branch: `refactor/phase-1-di-skeleton`  
Date: 2025-10-09

## Objective
- Trim NotificationCenter usage down to the sanctioned macOS menu/toolbar bridge and document the remaining surface.
- Replace legacy notification-driven sheet toggles with SwiftUI bindings.
- Remove unused observers (e.g., `RefreshJobApps`) to tighten store lifetimes.

## Changes
- Deleted the dormant `RefreshJobApps` Combine subscription from `JobAppStore`; the store now exposes `refreshJobApps()` without background observers (`DataManagers/JobAppStore.swift:37`).
- Bound the resume revision sheet directly to `ResumeReviseViewModel.showResumeRevisionSheet`, removing `.show/.hideResumeRevisionSheet` notifications and associated listeners (`App/Models/AppSheets.swift:32`, `Resumes/AI/Services/ResumeReviseViewModel.swift:23`).
- Pruned the unused notification names from the command registry to keep the sanctioned list focused on menu/toolbar and cross-window actions (`App/Views/MenuCommands.swift:12`).
- Added architecture notes clarifying why `MenuNotificationHandler` continues to use `NotificationCenter` for AppKit bridging and discouraging ad-hoc additions (`App/Views/MenuNotificationHandler.swift:11`).

## Validation
- `xcodebuild -project PhysCloudResume.xcodeproj -scheme PhysCloudResume build`

## Next
- Review remaining NotificationCenter posts in feature views (e.g., TTS, toolbar triggers) during later phases to confirm they align with the documented bridge.
