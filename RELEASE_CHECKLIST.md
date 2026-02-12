# Shifty Release Checklist

## Preflight
- Confirm working tree is clean and all intended commits are pushed.
- Verify `pod install` has been run after any Podfile changes.
- Verify app version/build in `/Users/timothy.hudson/Developer/shifty-features/Shifty/Info.plist`.
- Verify `ShiftyAppcast.xml` entry is prepared for the release version.

## Validation
- Run automated tests:
  - `xcodebuild test -workspace Shifty.xcworkspace -scheme Shifty -destination 'platform=macOS'`
- Run manual regression pass:
  - startup/setup flow
  - menu interactions
  - shortcuts (in-focus and global)
  - website shifting + permissions
  - login-item behavior
  - update check flow

## Archive
- Build archive:
  - `xcodebuild archive -workspace Shifty.xcworkspace -scheme Shifty -configuration Release -destination 'generic/platform=macOS' -archivePath /tmp/Shifty.xcarchive`
- Verify archive exists at `/tmp/Shifty.xcarchive`.
- Verify signing identity/team in build settings for `Shifty` target before distribution archive.

## Release
- Notarize/staple according to current distribution process.
- Publish updated `ShiftyAppcast.xml`.
- Publish release notes and tag the release commit.
