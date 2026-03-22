# Claude Usage

A macOS menubar app that tracks your Claude (Code) usage in real time.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 6](https://img.shields.io/badge/Swift-6-orange)
![License](https://img.shields.io/badge/License-Apache%202.0-green)

## Features

- **Menubar indicator** — circular ring gauge with percentage, always visible
- **Usage cards** — 5-hour, 7-day, Sonnet, and Opus utilization at a glance
- **Enterprise support** — monthly credit spend with dollar/percentage toggle and burn rate projection
- **Usage history** — area chart with adaptive time range (auto/7d/30d), stored in SQLite
- **Burn rate alerts** — notification when projected to hit limit within 60 minutes
- **Threshold notifications** — configurable alerts at 80% and 95% usage
- **CSV export** — export full history for analysis
- **Zero-setup auth** — reads Claude Code's OAuth token from Keychain automatically
- **Browser sign-in** — OAuth PKCE fallback for users without Claude Code
- **Auto-polling** — configurable interval (1/5/15/30 min) with exponential backoff
- **Sleep/wake aware** — pauses polling on sleep, resumes on wake
- **Multi-language** — English, Dutch, German, French, Spanish, Portuguese (BR & PT)
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

The app reads your OAuth token automatically if you have [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed and logged in. No setup needed.

If Claude Code is not installed, click "Sign in with Claude" in the popover to authenticate via your browser.

## How it works

The app polls `https://api.anthropic.com/api/oauth/usage` on a configurable interval and displays the response:

| Bucket | What it measures |
|---|---|
| 5-Hour | Rolling 5-hour usage window (resets every 5 hours) |
| 7-Day | Rolling 7-day usage across all models |
| Sonnet | 7-day usage for Sonnet models specifically |
| Opus | 7-day usage for Opus models specifically |
| Credits | Enterprise monthly spend vs limit |

Usage history is stored locally in `~/.config/claude-usage/history.db` (SQLite) with 30-day retention.

## Configuration

Click the gear icon in the popover to access settings:

- **Poll interval** — how often to fetch usage data (1, 5, 15, or 30 minutes)
- **Launch at login** — start automatically when you log in
- **Notification thresholds** — alert at 80% and/or 95% usage
- **Enterprise display** — toggle between dollar amount and percentage (when a monthly limit is set)

## Requirements

- macOS 14 (Sonoma) or later
- Claude Code installed (for automatic auth), or a Claude account for browser sign-in

## Development

```bash
# Run tests
swift test

# Run the app (unsigned, will prompt for keychain access)
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
