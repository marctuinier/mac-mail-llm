# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

No unreleased changes.

---

## Released

### [1.3.3](https://github.com/marctuinier/mac-mail-llm/compare/v1.3.2...v1.3.3) - 2026-03-30

#### Fixed

- **Extension now works without the host app running**: The Mail extension no longer requires the MailMate AI app to be open. The API key is now stored in a shared Keychain access group accessible by both the host app and the extension independently.
- Added `keychain-access-groups` entitlement to the host app (the extension already had it).
- One-time migration automatically moves any existing API key to the shared Keychain access group on first launch.
- Bumped `CFBundleVersion` (build number) to fix extension registration not updating between releases.

### [1.3.2](https://github.com/marctuinier/mac-mail-llm/compare/v1.3.1...v1.3.2) - 2026-03-12

#### Added

- **Cancel button during generation**: A Cancel button now appears alongside the thinking/writing phase label. Clicking it immediately stops the in-flight API request and returns to the home screen — no errors, no stale state.
- **Context-aware free-text drafting**: When you type a freeform instruction in the "What would you like to draft?" field, the AI now automatically receives all your saved prompts as background reference knowledge. This means it can pull in tone, links, product details, and templates from your saved prompts without you having to explicitly select one.

### [1.3.1](https://github.com/marctuinier/mac-mail-llm/compare/v1.3.0...v1.3.1) - 2026-03-07

#### Added

- **Multi-window compose support**: Each compose window now gets its own independent generation session. You can open 3 reply windows, generate AI drafts in each, and they won't interfere with each other.
- **Email body extraction fallbacks**: When MailKit's `rawData` is unavailable (common with certain IMAP/Exchange messages), the extension now attempts Accessibility API and AppleScript scraping as fallbacks.
- **Per-session debug logs**: Each generation request now writes a standalone `session-log-<timestamp>.json` file for easier debugging, alongside the rolling `flow-log.json`.

#### Changed

- `GenerationManager` refactored from a singleton to per-session instances keyed by `MEComposeSession` context ID. Sessions are created on compose window open and cleaned up on close.
- Call History in the host app now updates in real time via `DistributedNotificationCenter` with `suspensionBehavior: .deliverImmediately`, plus a 5-second polling fallback.
- Extraction diagnostics now log the exact source used (`originalMessage.rawData`, `cachedOriginalRawData`, `composeMsg.rawData`, `applescript`, or `none`).

#### Fixed

- Fixed Call History not updating until the host app was clicked — notifications are now delivered even when the app is in the background.
- Fixed stale email context from a previous compose window being used when `rawData` was unavailable — cached data is now cleared at the start of each new session.

### [1.3.0](https://github.com/marctuinier/mac-mail-llm/compare/v1.2.1...v1.3.0) - 2026-03-06

#### Added

- **Gemini Native Thinking / Reasoning**: The AI's reasoning process is now visible in the extension panel during both initial generation and refinement. Uses Gemini's native `thinking_config` API for genuine multi-step reasoning.
- Thinking streams live in italic text, then transitions seamlessly to the email output — the full panel is used edge-to-edge.
- Dynamic phase label shows "Thinking..." during reasoning and "Writing..." during email generation.
- **Auto-Retry on Errors**: Transient network errors, timeouts, and API rate limits (429/5xx) are automatically retried up to 2 times with increasing delays. Request timeout increased to 120s.
- **Retry Button**: When generation fails, a "Retry" button appears alongside "Start Over", preserving the last request context so you can retry without re-entering everything.
- **Call History / Audit Log**: New "Call History" tab in the host app sidebar showing a table of all past generation and refinement calls, with status (green/red), date/time, model, token usage, and estimated cost.
- Click any row to open a detail view with full instruction, AI thinking, generated output, and metadata.
- "Copy Instruction" button on the detail view for easy retry via the Mail extension.
- Token usage tracking: `usageMetadata` (prompt tokens, candidate tokens, thinking tokens, total tokens) is now captured from the Gemini API streaming response.
- Estimated cost calculation based on published Gemini API pricing per model.
- Call duration tracking for each generation and refinement request.
- Live refresh: the Call History table updates automatically when the Mail extension completes a new call.
- "Clear History" button to wipe all stored call records.

#### Changed

- Refinement now reuses the original system prompt context and explicitly instructs Gemini to keep the current reply intact unless the user asks for a rewrite or restructure.
- `ExtensionGeminiClient.streamGenerate` now returns a `GenerationResult` struct containing the generated text, usage metadata, and thinking text.
- `GenerationManager` writes a `CallRecord` to the shared App Group container after every generation or refinement call (both success and failure).
- Extension panel UI uses tighter spacing and edge-to-edge layout for a cleaner, more native feel.

### [1.2.1](https://github.com/marctuinier/mac-mail-llm/compare/v1.2.0...v1.2.1) - 2026-03-05

#### Changed

- Rich prompts (500+ characters) are now passed verbatim to Gemini as the system instruction, making prompt handling format-agnostic. Users can write prompts in JSON, markdown, plain text, or any format — no more internal parsing or key detection.
- Replaced the structured prompt parser with a simple length-based threshold. This mirrors the experience of pasting a prompt into Gemini's web chat.

#### Fixed

- HTML-only emails (no `text/plain` MIME part) now have their body correctly converted to plain text at the extraction level, ensuring Gemini always receives the full email thread content.
- Base64-encoded MIME parts are now decoded during email body extraction.
- Emails from Outlook and other clients that only provide HTML bodies no longer result in empty context being sent to Gemini.

#### Removed

- Debug diagnostic logging removed from production builds.
- `StructuredPrompt` struct and all associated JSON parsing logic removed in favor of the simpler passthrough approach.

### [1.2.0](https://github.com/marctuinier/mac-mail-llm/compare/v1.1.1...v1.2.0) - 2026-03-04

#### Added

- Gemini 3.x model support: `gemini-3.1-pro-preview`, `gemini-3.1-flash-lite-preview`, `gemini-3-flash-preview` added to model picker.
- `gemini-2.5-flash-lite` added to model picker.
- README refreshed with badges (Swift, platform, Gemini API, license) and cleaner layout.
- `CHANGELOG.md` following [Keep a Changelog](https://keepachangelog.com) format.

#### Fixed

- Invalid stored model names (e.g. from preview API changes) are now auto-corrected on settings load instead of causing API 404 errors.

### [1.1.1](https://github.com/marctuinier/mac-mail-llm/compare/v1.1...v1.1.1) - 2026-02-06

#### Changed

- Extension panel now dynamically resizes to fit its content, eliminating the large empty space above the UI.
- Auto-paste delay increased from 0.3s to 0.6s for more reliable focus restoration after popover dismissal.
- Confirmation message now shows "Inserted into email!" when auto-paste succeeds, or "Copied to clipboard" with instructions when Accessibility permission is unavailable.

#### Fixed

- Auto-paste now checks `AXIsProcessTrusted()` before attempting keystroke simulation, preventing silent failures.
- Added 50ms pause between key-down and key-up events for more reliable Cmd+V simulation.

### [1.1.0](https://github.com/marctuinier/mac-mail-llm/compare/v1.0...v1.1) - 2026-02-06

#### Added

- Structured prompt intelligence: rich JSON prompts are now parsed and woven into the Gemini system prompt as dedicated sections instead of being dumped as raw text.
- `Local.xcconfig` build configuration: developers configure their Team ID and App Group ID in a single gitignored file instead of editing multiple project files.
- `Local.xcconfig.example` template committed for new developers.

#### Changed

- System prompt for structured prompts now includes sender identity, tone guidelines, factual context, talking points, reply templates, and situation-specific templates as labeled sections.
- Entitlements files now use `$(APP_GROUP_ID)` build variable resolved from xcconfig.
- `AppGroupConstants.appGroupID` reads from Info.plist at runtime, with fallback to placeholder.
- `DEVELOPMENT_TEAM` removed from per-target build settings; now provided exclusively by xcconfig.
- README build instructions updated to use `Local.xcconfig` workflow.

### [1.0.2](https://github.com/marctuinier/mac-mail-llm/compare/v1.0.1...v1.0) - 2026-02-06

#### Changed

- Replaced hardcoded Team ID and App Group ID with configurable placeholders across the project.
- README updated with generic clone URL and explicit build steps for Team ID configuration.

#### Fixed

- Debug logging now uses `AppGroupConstants.appGroupID` instead of hardcoded App Group ID.

### [1.0.1](https://github.com/marctuinier/mac-mail-llm/compare/v1.0.0...v1.0.1) - 2026-02-06

#### Added

- Screenshots and detailed installation instructions in README.
- Asset images for app overview and extension panel.

### [1.0.0](https://github.com/marctuinier/mac-mail-llm/releases/tag/v1.0) - 2026-02-06

#### Added

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

