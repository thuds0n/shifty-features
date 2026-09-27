# Shifty Release Checklist

## Preflight
- Confirm working tree is clean and all intended commits are pushed.
- Verify `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the Shifty target build settings.
- Verify `ShiftyAppcast.xml` entry is prepared for the release version.
- Verify the root and hosted documentation agree on the minimum macOS version.
- Verify current preference and menu screenshots match the release build.

## Validation
- Run Debug and Release builds through `xcbeautify`:
  - `set -o pipefail && xcodebuild build -project Shifty.xcodeproj -scheme Shifty -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO | xcbeautify`
  - `set -o pipefail && xcodebuild build -project Shifty.xcodeproj -scheme Shifty -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO | xcbeautify`
- Run automated tests through `xcbeautify`:
  - `set -o pipefail && xcodebuild test -project Shifty.xcodeproj -scheme Shifty -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:ShiftyTests | xcbeautify`
- Run the CoreBrightness hardware tests on a real Mac (they briefly change Night Shift, then restore it):
  - `set -o pipefail && TEST_RUNNER_SHIFTY_HARDWARE_TESTS=1 xcodebuild test -project Shifty.xcodeproj -scheme Shifty -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:ShiftyTests/HardwareNightShiftTests | xcbeautify`
- Run Xcode static analysis through `xcbeautify`:
  - `set -o pipefail && xcodebuild analyze -project Shifty.xcodeproj -scheme Shifty -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO | xcbeautify`
- Run manual regression pass:
  - Startup/setup flow (first-run setup window, accessibility permissions prompt)
  - Menu bar icon and Quick Toggle behavior (left-click, right-click, Control+click)
  - Preferences window — verify all five panes open and switch correctly without the window resizing, and that the window opens centred then remembers its position:
    - **General**: all toggles persist across app restarts; Night Shift schedule picker + time fields show/hide correctly; True Tone section visible only on supported hardware
    - **Circadian**: toggle, wake time, bedtime, evening start and night warmth persist across restarts; the phase strip and status line match the menu status
    - **Shortcuts**: shortcut recorder fields accept and clear bindings; global shortcuts fire when app is backgrounded
    - **Rules**: app/domain/subdomain rules display with correct names, icons and rule types; rules added from the menu appear while the pane is open; the remove button and context menu delete a rule; the empty state shows when no rules exist
    - **About**: version string matches `Info.plist`; all link buttons open correct URLs/actions
  - Website shifting + accessibility permissions
  - Login-item (Launch at Login) toggle — verify helper correctly starts/stops
  - Disable timer (hour / custom duration) — verify Night Shift re-enables on expiry
  - Disable timer cancellation — verify the cancelled timer cannot fire a later restore event
  - Circadian mode, when included in the release — verify evening, bedtime, midnight and morning boundaries; manual pause and rule restoration; phase status
  - SiriKit/App Intents compatibility appropriate to the release
  - Supported localisations and VoiceOver operation, including the shortcut recorder
  - Update check flow via Sparkle

## Archive
- Build archive through `xcbeautify`:
  - `set -o pipefail && xcodebuild archive -project Shifty.xcodeproj -scheme Shifty -configuration Release -destination 'generic/platform=macOS' -archivePath /tmp/Shifty.xcarchive | xcbeautify`
- Verify archive exists at `/tmp/Shifty.xcarchive`.
- Verify signing identity/team in build settings for `Shifty` target before distribution archive.

## Release
- Notarize/staple according to current distribution process.
- Verify the archive and update are signed with Developer ID.
- Verify Sparkle EdDSA update signing and a staged update from the previous public version; do not publish a new DSA-only update.
- Verify the appcast minimum system version is macOS 14 or later for the new item.
- Publish updated `ShiftyAppcast.xml`.
- Publish release notes and tag the release commit.
