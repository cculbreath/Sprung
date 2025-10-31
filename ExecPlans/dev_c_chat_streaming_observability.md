# Purpose

Improve streaming observability and logging so users receive graceful feedback during slow responses, reasoning summaries appear when available, and logs stay readable. After this work, the app will display reasoning or a fallback shimmer, batch streamed text for smoother perception, and expose concise diagnostics (including precise instrumentation). SwiftOpenAI logging will support quiet, info, verbose, and debug levels with per-token output limited to debug.

# Scope

This work touches onboarding streaming UI, instrumentation, and the SwiftOpenAI fork.

# Background and Context

Current issues:
• Reasoning summaries never appear, and we do not know whether the API omits them.
• Streaming renders character-by-character, making slow responses feel even slower.
• Logs overflow with per-token entries from SwiftOpenAI, obscuring actionable information.

# High-Level Strategy

Instrument the streaming parser to capture reasoning summaries and expose them in the UI, with graceful fallback when absent. Record latency metrics at key points and batch text rendering into readable chunks. Refactor the SwiftOpenAI fork to support quiet/info/verbose/debug levels, restricting token-level logging to debug.

# Detailed Plan

## Milestone 1 – Reasoning Summaries and Fallback

1. Update the streaming response handler to capture reasoning blocks if present. Display them in a dedicated UI element; when absent, show a shimmer placeholder (“Thinking…”).
2. Log whether reasoning summaries were received for each response to aid debugging.
3. Acceptance: run Phase 1, trigger a response, and confirm either the reasoning text or placeholder renders and consolelog.txt records whether a summary arrived.

## Milestone 2 – Latency Instrumentation and Rendering

1. Record timestamps for upload start, extraction start, extraction end, first token received, and final token rendered. Log them under a new diagnostics category.
2. Batch streaming deltas into word-level chunks with easing animation to reduce perceived slowness. Add optional status phrases (e.g., “Polishing response…”) during long silence.
3. Acceptance: check consolelog.txt for timing metrics and observe smoother streaming animations without regressions on slower hardware.

## Milestone 3 – SwiftOpenAI Logging Levels

1. Create a new branch in SwiftOpenAI-ttsfork that introduces explicit log levels (quiet, info, verbose, debug). Emit per-token deltas only at debug.
2. Update Sprung to depend on this branch and set the default logging level to info, while allowing verbose/debug for troubleshooting.
3. Acceptance: rerun Phase 1, verify token logs are absent at default levels, and confirm enabling debug restores per-token visibility. Verify the new logging level selection is reflected in consolelog.txt.

# Progress

- [x] Milestone 1 – Reasoning Summaries and Fallback
- [ ] Milestone 2 – Latency Instrumentation and Rendering
- [ ] Milestone 3 – SwiftOpenAI Logging Levels

# Validation and Acceptance

Perform a Phase 1 walkthrough: ensure reasoning summaries or placeholders display and consolelog.txt records their presence, observe smooth streaming with reduced perceived latency and review the new timing logs in consolelog.txt, and confirm SwiftOpenAI respects the new log levels—quiet/info/verbose/debug—with per-token logs appearing only in debug mode.

# Risks and Mitigations

Streaming batching must not degrade responsiveness; test on low-power hardware and expose configuration flags for quick rollback. Updating the SwiftOpenAI fork requires coordination to avoid diverging from upstream; document branch name and merge strategy. Ensure the shimmer placeholder for reasoning does not mislead users when summaries are genuinely unavailable.

# Notes

Coordinate with Developers A and B to avoid conflicts in shared UI files. Document the SwiftOpenAI branch name and instructions for switching log levels so future developers can reproduce the setup. Use consolelog.txt after each milestone to confirm logging behaves as expected.

Revision history:
- 2025-10-31: Completed Milestone 1 reasoning placeholder work and logging, verified via `xcodebuild` Debug build.
