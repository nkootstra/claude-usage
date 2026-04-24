# Claude Usage

A macOS menubar app that tracks your Claude (Code) usage in real time.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 6](https://img.shields.io/badge/Swift-6-orange)
![License](https://img.shields.io/badge/License-Apache%202.0-green)

## Features

- **Dual-percent menubar** — consumer plans show `5h% · 7d%` inline, each color-coded by threshold. Enterprise plans keep the ring gauge with monthly spend.
- **Usage cards** — 5-hour, 7-day, Sonnet, and Opus utilization at a glance
- **Enterprise support** — monthly credit spend with dollar/percentage toggle and burn rate projection
- **Burn rate alerts** — notification when projected to hit limit within 60 minutes
- **Threshold notifications** — configurable alerts at 80% and 95% usage
- **OAuth sign-in** — authenticate via your browser with your Claude account
- **Claude Code auto-detect** — picks up credentials from Claude Code if installed (file-based, no keychain prompts)
- **Token refresh** — keeps your session alive without re-authenticating
- **Auto-polling** — configurable interval (1/5/15/30 min) with exponential backoff
- **Response cache** — hydrates the menu bar instantly on launch and defers the first poll when the cached response is still fresh, so rapid restarts don't stack API calls
- **Sleep/wake aware** — pauses polling on sleep, resumes on wake
- **Light & dark mode** — system colors throughout

## Installation

### From release (recommended)

1. Download the latest `.dmg` from [Releases](../../releases)
2. Open the DMG and drag **Claude Usage** to Applications
3. Launch from Applications — it appears in your menubar

### From source

```bash
git clone https://github.com/nkootstra/claude-usage.git
cd claude-usage
swift run ClaudeUsageApp
```

### Build signed .app

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project ClaudeUsage.xcodeproj \
  -scheme ClaudeUsage \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  CODE_SIGN_STYLE="Automatic" \
  DEVELOPMENT_TEAM="YOUR_TEAM_ID" \
  build
```

The signed app will be at `build/DerivedData/Build/Products/Release/Claude Usage.app`.

## Authentication

On first launch, click **Sign in with Claude** to authenticate via your browser. The app stores your credentials locally and refreshes tokens automatically.

If you have [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed, the app can also pick up your existing session from `~/.claude/.credentials.json` — no sign-in needed.

Credential resolution order:
1. Own cached credential (from a previous sign-in)
2. Claude Code credential file (`~/.claude/.credentials.json`)
3. Claude Code keychain (silent, no prompts)

## How it works

The app polls `https://api.anthropic.com/api/oauth/usage` on a configurable interval and displays the response:

| Bucket | What it measures |
|---|---|
| 5-Hour | Rolling 5-hour usage window (resets every 5 hours) |
| 7-Day | Rolling 7-day usage across all models |
| Sonnet | 7-day usage for Sonnet models specifically |
| Opus | 7-day usage for Opus models specifically |
| Credits | Enterprise monthly spend vs limit |

The last successful response is cached at `~/Library/Application Support/cc-stats/last-usage.json` so the menu bar can render immediately on relaunch without a network round-trip. Delete that file if you want to force a clean fetch.

## Configuration

Click the gear icon in the popover to access settings:

- **Poll interval** — how often to fetch usage data (1, 5, 15, or 30 minutes)
- **Launch at login** — start automatically when you log in
- **Notification thresholds** — alert at 80% and/or 95% usage
- **Enterprise display** — toggle between dollar amount and percentage (when a monthly limit is set)

## Requirements

- macOS 14 (Sonoma) or later
- A Claude account (Pro, Max, or Enterprise)

## Development

```bash
# Run tests
swift test

# Run the app (unsigned)
swift run ClaudeUsageApp

# Build signed app locally
xcodegen generate
xcodebuild -project ClaudeUsage.xcodeproj -scheme ClaudeUsage -configuration Release
```

### CI/CD

- **CI** (`ci.yml`) — runs `swift test` on every PR and push to main
- **Release** (`release.yml`) — triggered by pushing a tag (`v*`). Builds, signs, notarizes, creates DMG, and publishes a GitHub Release

To create a release:

```bash
git tag v1.0.0
git push origin v1.0.0
```

### Code signing & releases

See [docs/SIGNING.md](docs/SIGNING.md) for the full setup guide: creating certificates, exporting `.p12`, configuring GitHub secrets, and troubleshooting.

**Quick reference — required GitHub secrets:**

| Secret | Description |
|---|---|
| `MACOS_CERTIFICATE` | Base64-encoded .p12 certificate |
| `MACOS_CERTIFICATE_PWD` | Password for the .p12 file |
| `MACOS_CERTIFICATE_NAME` | e.g. `Developer ID Application: Name (TEAM_ID)` |
| `AC_USERNAME` | Apple ID email for notarization |
| `AC_PASSWORD` | App-specific password for notarization |
| `AC_TEAM_ID` | Apple Developer Team ID |

## License

[Apache License 2.0](LICENSE)
