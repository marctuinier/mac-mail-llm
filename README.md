# MailMate AI

An AI-powered macOS Mail extension that generates email replies directly inside the Mail compose toolbar. No copy-pasting between apps -- just click, generate, and insert.

<p align="center">
  <img src="assets/icon.png" width="128" alt="MailMate AI Icon">
</p>

## Screenshots

| Host App -- Manage Saved Prompts | Mail Extension -- Compose Toolbar Panel |
|---|---|
| ![App Overview](assets/app-overview.png) | ![Extension Panel](assets/extension-panel.png) |

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

## Installation

### 1. Download and install

Download `MailMateAI.dmg` from the [latest release](../../releases/latest), open it, and drag **MailMate AI** into your **Applications** folder.

### 2. Launch and enter your API key

Open MailMate AI from Applications. The onboarding wizard will ask you to paste your **Gemini API key**. You can get a free key from [Google AI Studio](https://aistudio.google.com/app/apikey).

### 3. Enable the Mail extension

The extension needs to be enabled in two places:

**System Settings:**
1. Open **System Settings** > **General** > **Login Items & Extensions**
2. Find **MailMate AI** and click the **(i)** info button
3. Toggle on the **Mail Extensions** checkbox

**Mail.app (if needed):**
1. Open **Mail** > **Settings** > **Extensions**
2. Enable **MailMate AI Extension**

### 4. Grant Accessibility permission (optional)

For **auto-paste** (so you don't have to press Cmd+V manually):
1. Open **System Settings** > **Privacy & Security** > **Accessibility**
2. Add **MailMate AI** to the list

This step is optional -- without it, the generated reply is copied to your clipboard and you paste it manually with Cmd+V.

## How It Works

1. **Compose an email** in Mail -- either a new message or a reply
2. **Click the MailMate AI icon** in the compose toolbar (the MM icon)
3. **Type an instruction** ("Reply professionally and mention the Thursday deadline") or **click a saved prompt**
4. **Watch the live preview** as the AI generates your reply using the email context
5. **Refine if needed** -- type "make it shorter" or "add a note about the budget" and click Refine
6. **Click Insert into Email** -- the formatted reply is pasted directly into the compose body

The extension reads the original email content (subject, sender, body) and feeds it to the Gemini API along with your instruction. The generated reply includes proper HTML formatting, hyperlinks, and your signature.

## Build from Source

```bash
git clone https://github.com/<owner>/mac-mail-llm.git
cd mac-mail-llm/MailMateAI
open MailMateAI.xcodeproj
```

Replace `<owner>` with the repository owner (e.g. your GitHub username or the fork you use).

Before building:
1. **Create `Local.xcconfig`** -- copy the example file and fill in your Team ID:
   ```bash
   cp Local.xcconfig.example Local.xcconfig
   ```
   Then edit `Local.xcconfig` and replace `YOUR_TEAM_ID` with your [Apple Developer Team ID](https://developer.apple.com/account#MembershipDetailsCard).
2. In the [Apple Developer portal](https://developer.apple.com/account/resources/identifiers/list/applicationGroup), create an **App Group** with identifier `<YOUR_TEAM_ID>.group.com.mailmate.ai` (using the same Team ID).
3. Build and run (Cmd+R) in Xcode. The xcconfig provides both `DEVELOPMENT_TEAM` and `APP_GROUP_ID` automatically.

Requires Xcode 16+.

## Project Structure

```
MailMateAI/
├── MailMateAI/          # Host app (SwiftUI) -- onboarding, settings, prompt management
├── MailExtension/       # Mail extension (AppKit) -- toolbar panel, Gemini client, generation
└── Shared/              # Shared code -- App Group constants, email context model
```

See [PLAN.md](PLAN.md) for detailed architecture, development log, and technical learnings.

## License

All rights reserved.
