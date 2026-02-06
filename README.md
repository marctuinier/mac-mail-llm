# MailMate AI

An AI-powered macOS Mail extension that generates email replies directly inside the Mail compose toolbar. No copy-pasting between apps -- just click, generate, and insert.

<p align="center">
  <img src="MailMateAI/MailMateAI/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="MailMate AI Icon">
</p>

## Features

- **Toolbar button in Mail.app** -- click the MailMate AI icon in any compose window to open the panel
- **Custom instructions** -- type what you want to draft, or pick from saved prompt templates
- **Live streaming preview** -- see the reply being generated in real time
- **Iterative refinement** -- ask the AI to tweak the reply ("make it shorter", "add a deadline note")
- **Auto-paste** -- inserts the formatted reply directly into the compose body (with Accessibility permission)
- **Rich formatting** -- replies include proper HTML, hyperlinks, and signature
- **Background generation** -- keeps working even if you click away from the panel
- **Tone matching** -- provide sample emails so the AI learns your writing style

## Requirements

- macOS 14.0 (Sonoma) or later
- A [Google Gemini API key](https://aistudio.google.com/app/apikey) (free tier available)
- Xcode 16+ (to build from source)

## Install from DMG

1. Download `MailMateAI.dmg` from [Releases](../../releases)
2. Open the DMG and drag **MailMate AI** to **Applications**
3. Launch MailMate AI and follow the onboarding:
   - Enter your Gemini API key
   - Enable the Mail extension in System Settings > General > Login Items & Extensions
   - Grant Accessibility permission (optional, for auto-paste)
4. Open Mail, compose a new email, and click the MailMate AI icon in the toolbar

## Build from Source

```bash
git clone <this-repo>
cd mac-mail-llm/MailMateAI
open MailMateAI.xcodeproj
```

In Xcode:
1. Set your Development Team under Signing & Capabilities for both the **MailMateAI** and **MailExtension** targets
2. Build and run (Cmd+R)
3. The app installs and registers the extension automatically

## Project Structure

```
MailMateAI/
├── MailMateAI/          # Host app (SwiftUI) -- onboarding, settings, prompt management
├── MailExtension/       # Mail extension (AppKit) -- toolbar panel, Gemini client, generation
└── Shared/              # Shared code -- App Group constants, email context model
```

See [PLAN.md](PLAN.md) for detailed architecture, development log, and learnings.

## How It Works

The Mail extension uses Apple's MailKit framework (`MEComposeSessionHandler`) to add a toolbar button to Mail's compose window. When clicked, a dropdown panel appears with:

1. A text field for custom instructions
2. Saved prompt templates (configured in the host app)
3. A live preview area showing the AI-generated reply
4. Refine and Insert buttons

The extension calls the Gemini API directly (via `ExtensionGeminiClient`) with SSE streaming. Generation state is managed by a singleton (`GenerationManager`) that persists across panel open/close cycles. The host app and extension share data through an App Group container and Keychain.

## License

All rights reserved.
