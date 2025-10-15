# Sprung Roadmap

The near-term plan focuses on stabilising the open-source release and expanding
feature coverage.

## 0.1 Launch (Public Release)
- ✅ Sanitize personal data and remove private assets from the repository.
- ✅ Document third-party dependencies and update licensing.
- ☐ Publish build/test instructions and seed issues for early contributors.

## 0.2 Quality Baseline
- Add automated CI (GitHub Actions running `xcodebuild test`).
- Backfill unit tests for resume template generation and AI DTO parsing.
- Introduce sample data bundles to make first-run onboarding smoother.

## 0.3 Feature Enhancements
- Support additional LLM providers via the existing façade.
- Expand cover letter committee workflow with pluggable scoring heuristics.
- Refine SwiftData schema migrations with compatibility tests.

## Longer-Term Ideas
- Explore a backend proxy for managed API keys and usage analytics.
- Build SwiftData persistence for multi-turn LLM conversations.
- Add localization support for non-US resumes and cover letters.
