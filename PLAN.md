# MailMate AI — Project Plan & Development Log

## What the User Wants

**Core problem:** The user currently copies emails from macOS Mail.app, pastes them into the Gemini web UI, generates a reply, copies the reply back, and manually adds hyperlinks. This is tedious and repetitive.

**The solution:** A native macOS Mail extension (MailKit) that adds an AI-powered button directly in the Mail compose toolbar. When clicked, a dropdown panel appears **inside Mail** where the user can:

1. **Type a custom instruction** ("What would you like to draft?") and hit Enter to generate a reply.
2. **Click a saved prompt** — pre-configured JSON templates with instructions, links, and signatures that can be reused for common reply types (e.g., "Professional Reply", "Polite Decline", "Quick Acknowledgment").
3. **See a live preview** of the generated reply streaming in.
4. **Refine the reply** using natural language ("make it shorter", "add a note about the deadline").
5. **Insert into the email** — copies the formatted HTML to the clipboard so the user can Cmd+V paste it with hyperlinks and formatting preserved.
6. **Settings** (in the separate MailMate AI host app) to manage the API key, saved prompts, tone-of-voice email samples, and signature.

**Key principle from user feedback:** Everything should happen inside the Mail toolbar dropdown panel. No separate windows popping up. The host app is only for initial setup (API key, onboarding) and managing prompts/settings.

---

## Architecture

### Components

| Component | Purpose |
|-----------|---------|
| **MailMateAI** (host app) | SwiftUI macOS app for onboarding, API key management, saved prompts, tone samples, settings. Installed to `/Applications`. |
| **MailExtension** (appex) | MailKit extension embedded in the host app. Provides the compose toolbar button and dropdown panel UI. Runs out-of-process via XPC. |
| **Shared/** | Code shared between both targets (AppGroupConstants, EmailContextModel). |

### Communication & Data Flow

```
Mail.app
  └── MailExtension.appex (XPC process)
        ├── ComposeSessionHandler: captures email context (subject, from, body, recipients)
        │   └── Writes to App Group container: email-context.json
        ├── ToolbarViewController: the dropdown panel UI
        │   ├── Reads email context from App Group
        │   ├── Reads saved prompts from App Group (prompts.json)
        │   ├── Reads API key from shared Keychain
        │   ├── Calls Gemini API directly (ExtensionGeminiClient)
        │   ├── Shows live streaming preview
        │   ├── Copies HTML+RTF to NSPasteboard for insertion
        │   └── Opens mailmate-ai:// URLs to launch host app for settings
        └── MailExtensionPrincipal: entry point, returns ComposeSessionHandler

MailMateAI.app (host)
  ├── Manages Keychain (API key storage)
  ├── Manages App Group files (prompts.json, tone-samples.json)
  ├── Registers mailmate-ai:// URL scheme
  └── Provides UI for onboarding, settings, prompt editing
```

### Key Technologies

- **MailKit (MEComposeSessionHandler, MEExtensionViewController)** — Apple's Mail extension framework
- **App Group container** (`UD763H597N.group.com.mailmate.ai`) — shared file storage between app and extension
- **Keychain Services** — secure API key storage (shared via keychain-access-groups entitlement)
- **NSPasteboard** — rich text (HTML + RTF + plain text) clipboard for inserting replies
- **Gemini API** (google generativelanguage REST) — AI generation with SSE streaming
- **AppKit (NSStackView, NSTextField, NSTextView, NSScrollView)** — extension panel UI (not SwiftUI — extensions use NSViewController)

---

## File Structure

```
MailMateAI/
├── MailMateAI.xcodeproj/
├── MailMateAI/                    # Host app target
│   ├── App.swift                  # SwiftUI app entry point
│   ├── ContentView.swift          # Main app window + URL scheme handler
│   ├── Info.plist                 # URL scheme registration (mailmate-ai://)
│   ├── MailMateAI.entitlements    # Sandbox, App Group, network, Apple Events
│   ├── Models/
│   │   ├── EmailContext.swift     # Codable model for email context
│   │   ├── SavedPrompt.swift      # Codable model for saved prompts
│   │   └── ToneSample.swift       # Codable model for tone samples
│   ├── Resources/
│   │   └── default-prompts.json   # Default saved prompts
│   ├── Services/
│   │   ├── GeminiService.swift    # Full Gemini client (host app, unused now for generation)
│   │   ├── KeychainService.swift  # Keychain read/write
│   │   ├── MailBridgeService.swift    # AppleScript bridge (for host app insertion)
│   │   ├── PasteboardService.swift    # HTML-to-pasteboard
│   │   └── SharedDataService.swift    # App Group data management
│   └── Views/
│       ├── ChatEditView.swift         # Refine UI (host app)
│       ├── ComposeAssistantView.swift # Compose panel (host app — legacy, mostly unused now)
│       ├── OnboardingView.swift       # First-run onboarding
│       ├── SavedPromptsView.swift     # Manage saved prompts
│       └── SettingsView.swift         # API key, model, signature settings
├── MailExtension/                 # Extension target
│   ├── ComposeSessionHandler.swift    # MEComposeSessionHandler — captures email context
│   ├── ExtensionGeminiClient.swift    # Lightweight Gemini API client for the extension
│   ├── MailExtensionPrincipal.swift   # MEExtension entry point
│   ├── ToolbarViewController.swift    # The dropdown panel UI (idle → generating → preview → inserted)
│   ├── Info.plist                     # Extension config (capabilities, icon)
│   └── MailExtension.entitlements     # Sandbox, App Group, network, keychain
└── Shared/
    ├── AppGroupConstants.swift        # Shared constants (App Group ID, file paths, keys)
    └── EmailContextModel.swift        # Shared email context struct (used by extension to write JSON)
```

---

## Development Log

### Phase 1: Initial Build
- Set up Xcode project with host app + Mail extension targets
- Created all models, services, and views
- Implemented Gemini API streaming client
- Created onboarding flow, settings, saved prompts management
- Built `ComposeSessionHandler` to capture email context via MailKit
- Built `ToolbarViewController` as the extension's toolbar button

### Phase 2: Getting the Extension to Appear in Mail
**This was the hardest part.** Multiple issues had to be resolved:

1. **project.pbxproj corruption** — `remoteGlobalIDString` pointed to the product reference instead of the native target, causing internal Xcode build errors.
2. **Method signature renames** — MailKit renamed `handlerForComposeSession` → `handler(for:)` and `viewControllerForSession` → `viewController(for:)` between OS versions.
3. **Code signing** — Ad-hoc signing doesn't work for Mail extensions. Requires a proper Apple Developer Team ID.
4. **Team ID mismatch** — Xcode auto-generated provisioning profiles used team `UD763H597N`, but the code had `D35JB5CDG2` hardcoded in App Group IDs and entitlements. The extension was invisible to Mail because the App Group wasn't properly provisioned.
5. **Info.plist `MEExtensionCapabilities`** — Initially declared as a `<dict>` (caused Mail.app crash: `componentsJoinedByString:` unrecognized selector). Mail expects an `<array>` of strings. Fixed to `<array><string>MEComposeSessionHandler</string></array>`.
6. **Extension not enabled** — Even after discovery, the extension was disabled by default. Required `pluginkit -e use -i com.mailmate.ai.MailExtension` to enable.
7. **Stale registrations** — LaunchServices and pluginkit cached old/broken versions. Required `lsregister -f -R -trusted` and xattr clearing.

**Lesson learned:** Mail extension development requires extremely precise entitlements, code signing, and Info.plist configuration. There is essentially zero useful error messaging — you have to dig through `log show` and `sfltool dumpbtm` to figure out what went wrong.

### Phase 3: Toolbar Panel Was Empty
After the extension appeared in Mail, clicking the toolbar button showed an empty panel. The `ToolbarViewController` was just a blank view that launched the host app via URL scheme.

**User feedback:** "I would have expected a text box... and saved prompts right there."

**Solution:** Completely redesigned the architecture. Instead of the extension being a thin button that launches the host app:
- Added `com.apple.security.network.client` entitlement to the extension
- Added `keychain-access-groups` entitlement so the extension can read the API key
- Created `ExtensionGeminiClient.swift` — a lightweight Gemini streaming client that runs inside the extension
- Rebuilt `ToolbarViewController` as a full multi-state UI:
  - **Idle:** prompt field + saved prompts list
  - **Generating:** spinner + live text preview
  - **Preview:** rendered HTML + refine field + Insert/Start Over buttons
  - **Inserted:** clipboard confirmation + "press Cmd+V" instruction

### Phase 4: Panel Overflow
The dropdown panel has a fixed viewport (~300px). With 5 saved prompts, the content overflowed and buttons were cut off.

**User feedback:** "I can't see everything in the Viewer... the buttons don't show."

**Solution:**
- Reduced all padding (14→8), spacing (10→6), font sizes (13→11/12)
- Removed the multi-line instruction description from prompt rows — now single-line with just the name + chevron (~28px each instead of ~48px)
- Put saved prompts in a scrollable inner list capped at 160px
- Explicit view size constraint: 320x280
- Moved Settings gear to the header row (inline with title) instead of a separate button at the bottom
- Preview state: capped HTML preview scroll to 130px, kept refine field + buttons compact

### Phase 5: Email Context Not Captured (Critical Fix)
The extension was not ingesting the original email body when replying, producing generic responses.

**Root cause:** `MEComposeSession.mailMessage.rawData` refers to the *outgoing draft*, which is always `nil` at generation time. The original email being replied to lives at `session.composeContext.originalMessage`.

**Solution:**
- Moved context extraction from `ComposeSessionHandler.mailComposeSessionDidBegin` to `ToolbarViewController.refreshEmailContext()`, called at generation time
- Read `session.composeContext.originalMessage.rawData` for the MIME body of the original email
- Use `composeContext.action` (`.reply`, `.replyAll`, `.forward`) instead of subject prefix heuristics
- Extract `originalFrom` from the original message for the AI prompt
- Improved MIME parser: handle `\r\n` vs `\n` line endings, quoted-printable decoding, nested multipart boundaries

### Phase 6: Preview Text Invisible on Dark Backgrounds (Two Root Causes)
Generated HTML rendered as invisible text in the preview pane.

**Root cause 1 — NSAttributedString foreground color:** HTML conversion embeds per-character `foregroundColor: black` attributes that override the `NSTextView.textColor` setting on dark backgrounds.

**Root cause 2 — NSTextView zero height:** The text view had `translatesAutoresizingMaskIntoConstraints = false` with no height constraint, collapsing to 0px height inside the scroll view. Confirmed via debug logs: `tvFrame: "(0.0, 0.0, 300.0, 0.0)"`.

**Root cause 3 — Gemini markdown code fences:** Gemini wraps HTML output in `` ```html ... ``` `` markdown fences. The NSAttributedString HTML parser interprets these as literal text, not HTML tags — so the content renders as raw text starting with `` ```html ``.

**Solutions:**
- `forceLabelColor(on:)` utility to strip all foreground colors and apply `NSColor.labelColor`
- Configured NSTextView with `isVerticallyResizable = true`, `autoresizingMask = [.width]`, unbounded container size, and `sizeToFit()` — the standard pattern for NSTextView inside NSScrollView
- `stripCodeFences()` in `ExtensionGeminiClient` that removes opening `` ```html `` and closing `` ``` `` from API responses
- Applied fence stripping to both the final result and the live streaming preview

### Phase 7: State Lost When Panel Dismissed
Clicking away from the Mail toolbar popover dismissed the panel, deallocating the `ToolbarViewController` and losing all generation state. If the user clicked away during generation, the API call would stop. If they clicked away during preview, the generated text would be lost.

**Root cause:** All state (panelState, generatedHTML, geminiClient) lived on the `ToolbarViewController` instance, which Mail.app recreates every time the popover opens.

**Solution — GenerationManager singleton:**
- Created `GenerationManager.swift` — a singleton that owns the Gemini client, generation Task, and current state (idle/generating/preview/error)
- Generation runs in `Task.detached` so it survives view controller deallocation
- Results are cached to the App Group container (`last-generation.json`) with a 10-minute TTL
- `ToolbarViewController` is now a thin UI layer that reads state from `GenerationManager` on `viewWillAppear` and renders accordingly
- On reopen during generation: re-renders spinner, re-attaches streaming callback, resumes polling
- On reopen after completion: immediately shows preview with the cached result

### Phase 8: Auto-Paste and Refine Flow
**Auto-paste:** Instead of requiring the user to manually Cmd+V, the "Insert into Email" button now:
1. Copies HTML+RTF+plaintext to the clipboard
2. Waits 300ms for the popover to dismiss
3. Simulates a Cmd+V keystroke via `CGEvent` to paste into the compose body

This requires Accessibility permission, which is requested during onboarding. Falls back to manual paste if permission isn't granted.

**Refine flow fix:** The "Tell me what to change..." field now correctly triggers a refinement through the `GenerationManager`, preserving conversation history. If the popover dismisses during refinement, the generation continues in the background and the result appears when the panel is reopened.

---

## Ongoing Issues & Learnings

### Mail Extension Constraints
- **No SwiftUI** in extension view controllers — must use AppKit (NSView, NSStackView, etc.)
- **No direct compose body access** — sandboxed extensions can't programmatically write to the Mail compose window. Must use clipboard + CGEvent paste.
- **Fixed panel size** — Mail controls the popover dimensions. Content must fit ~300px height.
- **Panel lifecycle** — Mail recreates the ToolbarViewController on every popover open. All persistent state must live outside the VC (singleton or file-based).
- **XPC process** — extension runs in a separate process. All data sharing via App Group files or Keychain.
- **Entitlements are critical** — any mismatch between provisioning profile, entitlements file, and App Group ID silently breaks everything.
- **Gemini markdown wrapping** — the Gemini API wraps HTML responses in markdown code fences even when explicitly told not to. Must strip these programmatically.

### What Works Now
- Extension appears in Mail toolbar with custom app icon
- Dropdown shows prompt field + saved prompts
- Clicking a saved prompt (or typing custom instruction + Generate) calls Gemini API
- Live streaming preview shows during generation
- Generation continues in background when panel is dismissed
- State persists across panel open/close cycles (generating, preview, error)
- Preview shows rendered HTML with proper dark mode colors
- Refine allows iterative editing via natural language with conversation memory
- Insert auto-pastes into the compose body via CGEvent (with Accessibility permission)
- Falls back to clipboard for manual Cmd+V if no Accessibility permission
- Host app manages API key, prompts, tone samples, settings
- Onboarding walks through API key, extension enablement, and accessibility permission

### What's Next (Potential)
- Inline editing of the generated text in the preview
- Indicator showing which email context was captured
- Better error handling for API failures
- Support for multiple Gemini models in the extension dropdown
- Keyboard shortcut to trigger generation
- Notification when background generation completes

---

## User's Core Preferences
1. **Everything in-panel** — no separate windows, no app switching
2. **Native macOS look and feel** — should feel like it belongs in Mail (Tahoe style)
3. **Fast and minimal** — click saved prompt → get reply → auto-paste
4. **Links and formatting** — replies should have proper hyperlinks, not just text
5. **Iterative refinement** — be able to tweak the reply before inserting
6. **Tone of voice** — AI should learn from example emails the user provides
7. **Background generation** — should keep working even when clicking away
8. **State persistence** — don't lose work when the popover closes

---

## File Structure (Updated)

```
MailExtension/
├── ComposeSessionHandler.swift    # MEComposeSessionHandler — passes session to ToolbarVC
├── ExtensionGeminiClient.swift    # Gemini API client with code fence stripping
├── GenerationManager.swift        # Singleton: owns generation state, survives VC lifecycle
├── MailExtensionPrincipal.swift   # MEExtension entry point
├── ToolbarViewController.swift    # Thin UI layer — reads state from GenerationManager
├── Info.plist
└── MailExtension.entitlements
```

---

*Last updated: February 6, 2026 — app icon, background generation, auto-paste, refine fix, onboarding improvements*
