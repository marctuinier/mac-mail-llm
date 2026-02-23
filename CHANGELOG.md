# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.1] - 2026-02-06

### Changed

- Extension panel now dynamically resizes to fit its content, eliminating the large empty space above the UI.
- Auto-paste delay increased from 0.3s to 0.6s for more reliable focus restoration after popover dismissal.
- Confirmation message now shows "Inserted into email!" when auto-paste succeeds, or "Copied to clipboard" with instructions when Accessibility permission is unavailable.

### Fixed

- Auto-paste now checks `AXIsProcessTrusted()` before attempting keystroke simulation, preventing silent failures.
- Added 50ms pause between key-down and key-up events for more reliable Cmd+V simulation.

## [1.1.0] - 2026-02-06

### Added

- Structured prompt intelligence: rich JSON prompts (with `sender_profile`, `key_talking_points`, `standard_replies`, `logic_tree_responses`) are now parsed and woven into the Gemini system prompt as dedicated sections instead of being dumped as raw text.
- `Local.xcconfig` build configuration: developers configure their Team ID and App Group ID in a single gitignored file instead of editing multiple project files.
- `Local.xcconfig.example` template committed for new developers.

### Changed

- System prompt for structured prompts now includes sender identity, tone guidelines, factual context, talking points, reply templates, and situation-specific templates as labeled sections.
- User message for structured prompts replaced raw JSON dump with a concise directive instructing Gemini to interpret the structured context.
- Entitlements files now use `$(APP_GROUP_ID)` build variable resolved from xcconfig.
- `AppGroupConstants.appGroupID` reads from Info.plist at runtime, with fallback to placeholder.
- `DEVELOPMENT_TEAM` removed from per-target build settings; now provided exclusively by xcconfig.
- README build instructions updated to use `Local.xcconfig` workflow.

## [1.0.2] - 2026-02-06

### Changed

- Replaced hardcoded Team ID and App Group ID with `YOUR_TEAM_ID` placeholder across `AppGroupConstants.swift`, both entitlements files, `project.pbxproj`, and `PLAN.md`.
- Signature placeholder changed from personal name to "Your Name" in `SavedPromptsView`.
- README updated with generic clone URL and explicit build steps for Team ID configuration.
- Commit message and authorship cleaned up for professional distribution.

### Fixed

- Debug logging in `ToolbarViewController` now uses `AppGroupConstants.appGroupID` instead of hardcoded App Group ID.

## [1.0.1] - 2026-02-06

### Added

- Screenshots and detailed installation instructions in README.
- Asset images for app overview and extension panel.

## [1.0.0] - 2026-02-06

### Added

- macOS Mail extension with toolbar button in compose window.
- Gemini API integration with streaming response generation.
- Saved prompt templates with custom instructions, links, and signatures.
- Live streaming preview of AI-generated replies.
- Iterative refinement: ask the AI to modify the generated reply.
- Background generation that survives panel dismissal via `GenerationManager` singleton.
- Auto-paste into compose body using `CGEvent` keystroke simulation (requires Accessibility permission).
- Rich text clipboard support (HTML, RTF, plain text).
- Tone matching via uploaded email samples.
- MIME parsing for extracting original email context from replies.
- SwiftUI host app with onboarding wizard, prompt management, and settings.
- Keychain-based API key storage.
- App Group container for host app / extension communication.
- Custom app icon and toolbar icon.
- DMG packaging for distribution.

[unreleased]: https://github.com/marctuinier/mac-mail-llm/compare/v1.1.1...HEAD
[1.1.1]: https://github.com/marctuinier/mac-mail-llm/compare/v1.1...v1.1.1
[1.1.0]: https://github.com/marctuinier/mac-mail-llm/compare/v1.0...v1.1
[1.0.2]: https://github.com/marctuinier/mac-mail-llm/compare/v1.0.1...v1.0
[1.0.1]: https://github.com/marctuinier/mac-mail-llm/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/marctuinier/mac-mail-llm/releases/tag/v1.0
