# Shifty

Shifty expands the built-in Night Shift feature in macOS. It can disable Night Shift for specific apps, websites and custom time periods, expose global keyboard shortcuts, synchronise Dark Mode, and fine-tune colour temperature from the menu bar.

<img src='docs/en/images/shifty-screenshot-large.png' width=70%>

Shifty is being modernised into a contextual circadian workspace optimiser. A three-phase scheduling foundation exists in the current codebase, but circadian scheduling, activity sensing, per-display calibration, App Intents and CLI tooling are not yet production-ready. The audited implementation status and delivery order live in [PLAN.md](PLAN.md).

<img src="docs/en/images/prefs-general-screenshot-shadow.png" width=60%/>

## System requirements

- macOS 14 (Sonoma) or later.
- A Mac that supports [Night Shift](https://support.apple.com/en-us/HT207513#requirements).
- Accessibility and Automation permission for website shifting.
- Website shifting supports Safari, Chrome, Chromium, Edge, Brave, Opera, Vivaldi and their variants.

Shifty uses undocumented macOS display interfaces. Compatibility can change between macOS releases, so a successful build alone does not verify Night Shift or True Tone behaviour on every Mac.

## Development

Open `Shifty.xcodeproj` directly. Dependencies are managed with Swift Package Manager.

```sh
set -o pipefail
xcodebuild build -project Shifty.xcodeproj -scheme Shifty -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO | xcbeautify

set -o pipefail
xcodebuild test -project Shifty.xcodeproj -scheme Shifty -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:ShiftyTests | xcbeautify
```

The shared scheme runs unit tests with normal app startup disabled and uses temporary suites for test preferences. The CoreBrightness hardware tests are opt-in. See the [release checklist](RELEASE_CHECKLIST.md) for the real-Mac checks.

Run the Preferences UI tests in a logged-in macOS session. They verify that bedtime edits and German keyboard shortcut assignments and removals persist across relaunches. Each test uses an isolated profile and attaches a window screenshot to the Xcode result. Use Xcode’s default DerivedData location for the UI runner.

```sh
set -o pipefail
xcodebuild test -project Shifty.xcodeproj -scheme Shifty -destination 'platform=macOS' -parallel-testing-enabled NO CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= -only-testing:ShiftyUITests | xcbeautify
```

The opt-in Chrome acceptance test opens an Incognito window, drives the live browser watcher, and checks the Rules pane using a temporary profile and simulated Night Shift output. Use a Debug build that already has macOS Accessibility and Automation access to Chrome. The test checks for these permissions without requesting them.

```sh
set -o pipefail
TEST_RUNNER_SHIFTY_LIVE_CHROME_TEST=1 xcodebuild test -project Shifty.xcodeproj -scheme Shifty -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:ShiftyUITests/PreferencesTests/testLiveChromeTabsApplyAndClearWebsiteRule | xcbeautify
```

Shifty is free and open source under the GPLv3 licence. Contributions are welcome.

If you'd like to help translate Shifty into other languages, you can contribute [here](https://shifty.natethompson.io/translate).
