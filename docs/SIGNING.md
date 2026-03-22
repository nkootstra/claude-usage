# Code Signing & Release Setup

This guide walks through setting up code signing and notarization for distributing Claude Usage as a signed `.dmg`.

## Prerequisites

- An [Apple Developer account](https://developer.apple.com) ($99/year)
- A **Developer ID Application** certificate (not "Apple Development" — that's for testing only)
- Xcode command line tools installed

## 1. Create a Developer ID Application Certificate

If you don't have one yet:

1. Go to [developer.apple.com/account/resources/certificates](https://developer.apple.com/account/resources/certificates/list)
2. Click **+** to create a new certificate
3. Select **Developer ID Application**
4. Follow the instructions to create a Certificate Signing Request (CSR) from Keychain Access
5. Download and double-click the certificate to install it

Verify it's installed:

```bash
security find-identity -v -p codesigning
```

You should see something like:

```
1) ABC123... "Developer ID Application: Your Name (TEAM_ID)"
```

> **Important:** You need "Developer ID Application", not "Apple Development". Only Developer ID certificates work for distribution outside the App Store.

## 2. Export the Certificate as .p12

1. Open **Keychain Access** (`/Applications/Utilities/Keychain Access.app`)
2. Go to **login** keychain → **My Certificates**
3. Find **"Developer ID Application: Your Name (TEAM_ID)"**
4. Right-click → **Export...**
5. Save as `.p12` format
6. **Set a strong password** — you'll need this for `MACOS_CERTIFICATE_PWD`

## 3. Base64-Encode the Certificate

```bash
base64 < ~/Desktop/Certificates.p12 | pbcopy
```

The base64 string is now on your clipboard. This is the value for `MACOS_CERTIFICATE`.

## 4. Create an App-Specific Password

Notarization requires an app-specific password (not your regular Apple ID password):

1. Go to [appleid.apple.com](https://appleid.apple.com)
2. Sign in → **Sign-in and Security** → **App-Specific Passwords**
3. Click **+** → name it "GitHub Actions" → **Create**
4. Copy the generated password (format: `xxxx-xxxx-xxxx-xxxx`)

This is the value for `AC_PASSWORD`.

## 5. Find Your Team ID

Your Team ID is in parentheses in the certificate name:

```
"Developer ID Application: Your Name (WQ8V5KRNUG)"
                                       ^^^^^^^^^^
                                       This is your Team ID
```

Or find it at [developer.apple.com/account](https://developer.apple.com/account) → Membership Details.

## 6. Add GitHub Secrets

Go to your repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**.

Add these 6 secrets:

| Secret | Value | Example |
|---|---|---|
| `MACOS_CERTIFICATE` | Base64-encoded .p12 file | `MIIFbTCCBFWg...` (long string) |
| `MACOS_CERTIFICATE_PWD` | Password from step 2 | `your-p12-password` |
| `MACOS_CERTIFICATE_NAME` | Full certificate name | `Developer ID Application: Your Name (TEAM_ID)` |
| `AC_USERNAME` | Apple ID email | `you@example.com` |
| `AC_PASSWORD` | App-specific password from step 4 | `xxxx-xxxx-xxxx-xxxx` |
| `AC_TEAM_ID` | Team ID from step 5 | `WQ8V5KRNUG` |

## 7. Create a Release

Once secrets are configured, create a release by pushing a tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The `release.yml` workflow will:

1. Run all tests
2. Build the app with xcodegen + xcodebuild
3. Sign with your Developer ID certificate
4. Create a `.dmg` with Applications symlink
5. Submit to Apple for notarization
6. Staple the notarization ticket to the DMG
7. Create a GitHub Release with the DMG attached

## Local Signing

To build a signed app locally without CI:

```bash
# Generate Xcode project
xcodegen generate

# Build and sign
xcodebuild -project ClaudeUsage.xcodeproj \
  -scheme ClaudeUsage \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  CODE_SIGN_STYLE="Automatic" \
  DEVELOPMENT_TEAM="YOUR_TEAM_ID" \
  build

# Verify signature
codesign -dvv build/DerivedData/Build/Products/Release/ClaudeUsage.app
```

## Troubleshooting

**"No identity found"** — Your certificate isn't installed or has expired. Check with `security find-identity -v -p codesigning`.

**"bundle format unrecognized"** — The framework target needs `GENERATE_INFOPLIST_FILE: YES` in `project.yml`. This is already configured.

**Notarization fails** — Ensure you're using a "Developer ID Application" certificate, not "Apple Development". Check that your app-specific password is valid.

**Stapling fails** — Apple's servers can be slow to propagate. The workflow retries 5 times with 30-second delays.
