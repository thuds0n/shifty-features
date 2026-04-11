# Shifty Release Checklist

## Preflight
- Confirm working tree is clean and all intended commits are pushed.
- Verify app version/build in `Shifty/Info.plist`.
- Verify `ShiftyAppcast.xml` entry is prepared for the release version.

## Validation
- Run automated tests:
  - `xcodebuild test -project Shifty.xcodeproj -scheme Shifty -destination 'platform=macOS'`
- Run manual regression pass:
  - Startup/setup flow (first-run setup window, accessibility permissions prompt)
  - Menu bar icon and Quick Toggle behavior (left-click, right-click, Control+click)
  - Preferences window — verify all four panes open and switch correctly:
    - **General**: all toggles persist across app restarts; Night Shift schedule picker + time fields show/hide correctly; True Tone section visible only on supported hardware
    - **Shortcuts**: shortcut recorder fields accept and clear bindings; global shortcuts fire when app is backgrounded
    - **Whitelist**: active app entry updates on app switch; per-app rules toggled correctly; domain/subdomain entries displayed with correct icons
    - **About**: version string matches `Info.plist`; all link buttons open correct URLs/actions
  - Website shifting + accessibility permissions
  - Login-item (Launch at Login) toggle — verify helper correctly starts/stops
  - Disable timer (hour / custom duration) — verify Night Shift re-enables on expiry
  - Update check flow via Sparkle

## Archive
- Build archive:
  - `xcodebuild archive -project Shifty.xcodeproj -scheme Shifty -configuration Release -destination 'generic/platform=macOS' -archivePath /tmp/Shifty.xcarchive`
- Verify archive exists at `/tmp/Shifty.xcarchive`.
- Verify signing identity/team in build settings for `Shifty` target before distribution archive.

## Release
- Notarize/staple according to current distribution process.
- Publish updated `ShiftyAppcast.xml`.
- Publish release notes and tag the release commit.
