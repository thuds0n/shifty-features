# Circadian Workspace Optimizer — Master Plan

## Branch
- Feature branch: `codex/circadian-workspace-optimizer`
- Base branch: `master`

---

## Vision
Evolve Shifty from a manual Night Shift toggle into an intelligent, context-aware **Circadian Workspace Optimizer** — a three-phase color engine with activity sensing, per-display calibration, ecosystem integration, and developer-first CLI tooling.

---

## Codebase Snapshot (as of 2026-03-15)

### Already Committed
| Commit | Summary |
|--------|---------|
| `e4e4c59` | Remove legacy pods, finalize internal shortcut infrastructure |
| `e3c422c` | Remove telemetry/crash-sharing UI and related app hooks |
| `dc11748` | Refine menu and preferences UX (switches, disable submenu, kelvin, whitelist) |
| `e1353c9` | Target macOS 14, remove legacy compatibility paths |

### Uncommitted (in-progress)
- **MASPreferences removal** — replaced with native `NSTabViewController`-based preferences host
- **Event.swift deletion** — dead telemetry layer removed
- **AXSwift reduction** — native `AXIsProcessTrustedWithOptions` in PrefManager; AXSwift only in BrowserManager
- **Pod install** after removing `MASPreferences+Shifty` from Podfile

### Known Runtime Issue
Preferences window has had intermittent issues (blank window, disappearing toolbar icons, missing menu bar icon). Root cause: startup ordering between `AppDelegate`, `StatusMenuController.awakeFromNib`, and lazy preferences window construction. Latest fix defers preferences init. **Needs manual verification before committing.**

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    AppDelegate                          │
│  - lifecycle, status bar, CLI observer, prefs window    │
├──────────┬────────────────────────┬─────────────────────┤
│          │                        │                     │
│  StatusMenuController    NightShiftManager        CircadianWorkspace │
│  - menu build/update     - event dispatch         Coordinator        │
│  - user interaction      - color temp control     - orchestrator     │
│  - circadian toggle      - disable timers         - 60s refresh      │
│          │               - dark mode sync         - CLI dispatch     │
│          │                        │                     │
├──────────┴────────────────────────┴─────────────────────┤
│                  SystemIntegration (DI)                  │
│  nightShiftSystem · trueTone · appearance · permissions  │
│  circadianTransition · activityOverride · displayCalib   │
│  automationBridge · cliBridge · updater · loginItem      │
├─────────────────────────────────────────────────────────┤
│  RuleManager          BrowserManager      PrefManager   │
│  - app/domain rules   - URL detection     - UserDefaults│
│  - rule persistence   - AXSwift bridge    - factory defs│
└─────────────────────────────────────────────────────────┘
```

---

## Feature Roadmap

### Phase 0 — Stabilize Foundation
**Goal:** Commit the in-progress modernization and verify runtime stability.

- [ ] **0.1** Verify menu bar icon, preferences toolbar, and pane switching work after MASPreferences removal
- [ ] **0.2** Extract shortcut binding out of `PrefShortcutsViewController` into a dedicated `ShortcutBindingService` (eliminates the standalone-binder design smell)
- [ ] **0.3** Commit: `Replace MASPreferences with native AppKit preferences host`
- [ ] **0.4** Evaluate remaining dependency bloat:
  - Replace AXSwift in `BrowserManager` with a narrow native AX wrapper
  - Assess `PublicSuffix` — keep if domain-rule correctness matters, else replace with lightweight suffix check
  - Decide Sparkle fate (keep for direct download, remove for App Store-only)

---

### Phase 1 — Multi-Stage Circadian Transition Engine
**Goal:** Fully productionize the three-phase color curve.

#### Already Built ✓
- `CircadianTransitionEngine` — calculates kelvin target from time-until-bedtime
- `CircadianPhase` enum: `.daylight` (6500K) → `.evening` (4500K) → `.deepNight` (3200K)
- `CircadianCurveConfiguration` — bedtime, lead times, kelvin targets per phase
- `CircadianWorkspaceCoordinator` — orchestrates 60s refresh loop, calls `applyNow()`
- Menu toggle in `StatusMenuController`
- AppDelegate lifecycle hooks (`start()`/`stop()`)

#### Remaining Work
- [ ] **1.1** Preferences UI for circadian configuration
  - Bedtime picker (hour:minute)
  - Evening lead time slider (30 min – 4 hours)
  - Deep night lead time slider (15 min – 2 hours)
  - Per-phase kelvin target fields or a visual curve editor
  - Add a new "Circadian" preferences tab or section in General
- [ ] **1.2** Persist `CircadianCurveConfiguration` to UserDefaults (currently hardcoded defaults)
- [ ] **1.3** Smooth animated transitions when phase changes (ease kelvin over ~60s instead of jump)
- [ ] **1.4** Menu bar status indicator — show current phase name and/or countdown to next phase
- [ ] **1.5** Respect existing disable timers: if user sets a 30-min disable, circadian engine should honor it

#### Phase 1 Enhancements — Advanced Circadian Features
- [ ] **1.6** Context profiles (High Value)
  - Named configurations (e.g., "Design Work," "Late Night Coding," "Travel") with independent curve settings
  - Each profile: bedtime, evening lead, deep night lead, kelvin targets
  - Switchable via menu, preferences, or Shortcuts
  - Persist multiple profiles to UserDefaults

- [ ] **1.7** Calendar-aware bedtime (High Value)
  - Query `EventKit` for the user's last calendar event of the day
  - If a late meeting is detected, delay Deep Night phase onset by X minutes (user-configurable)
  - Runs during the 60s refresh loop — respects live calendar changes

- [ ] **1.8** Health.app bedtime sync (High Value)
  - Read user's scheduled sleep time from HealthKit (`HKSleepSampleType`)
  - Auto-populate bedtime picker in preferences instead of manual entry
  - Optional toggle: "Auto-sync bedtime from Health.app"

- [ ] **1.9** Time zone travel mode (Medium Value)
  - Detect system time zone changes (e.g., via `NSTimeZone` KVO or system notification)
  - Offer to shift circadian schedule by the UTC offset delta instead of snapping immediately
  - Helpful for users traveling across time zones — prevents immediate phase shifts

- [ ] **1.10** Keyboard shortcuts for kelvin presets (High Value)
  - Define preset kelvin levels with keyboard bindings (e.g., Cmd+Shift+1 = "Color Work" 6500K, Cmd+Shift+2 = "Reading" 4000K)
  - Quick-jump without opening menus
  - Especially valuable for designers, developers, content creators
  - Store presets in preferences (name, kelvin value, optional keyboard shortcut)

- [ ] **1.11** Menu bar popover UI upgrade (Medium Value)
  - Replace flat menu with an `NSPopover` containing:
    - Live Kelvin value and current phase arc visualization
    - Countdown timer to next phase transition
    - Quick preset buttons
    - Toggle circadian mode on/off
  - More discoverable and interactive than a traditional menu

---

### Phase 2 — Intelligent Activity Sensing
**Goal:** Auto-suspend Night Shift for media and color-critical work.

#### Already Built ✓
- `ActivityOverrideManager` — monitors workspace notifications for media apps
- Tracks VLC, IINA, QuickTime Player bundle IDs
- Temporary pause with configurable duration (1–30 min)
- `ActivitySuspendReason` enum: `.fullscreenMedia`, `.pictureInPicture`, `.temporaryPause`
- `evaluateMediaContext()` — private detection logic
- Override snapshot surfaced to coordinator via `onChange` callback

#### Remaining Work
- [ ] **2.1** Fullscreen detection refinement
  - Use `NSWindow.StyleMask.fullScreen` notifications or `NSScreen.screensHaveSeparateSpaces`
  - Handle Stage Manager / tiled fullscreen on macOS 14+
  - Detect PiP window (`NSWindow.level` or window title heuristics)
- [ ] **2.2** Expand media app list — make it user-configurable (bundle ID list in preferences)
- [ ] **2.3** Color-Critical Pause with menu bar countdown
  - Add "Pause for X minutes" submenu items (5, 10, 15, 30 min)
  - Show countdown timer in menu bar extra or tooltip
  - Auto-resume when timer expires (already partially handled by `ActivityOverrideManager`)
- [ ] **2.4** Integration with existing disable timer system in `NightShiftManager` — unify or clearly delineate circadian pause vs. manual disable

#### Phase 2 Enhancements — Additional Activity Detection
- [ ] **2.5** Camera/mic active detection (High Value)
  - Monitor camera & microphone usage (e.g., FaceTime, Zoom, Teams) using privacy indicators
  - Auto-pause Night Shift when on an active video call — users look orange on camera
  - Detect via `AVCaptureDevice` active sessions or the system camera-in-use privacy indicator
  - Auto-resume when call ends
  - User-configurable toggle in preferences

---

### Phase 3 — Per-Display Calibration & Independent Toggling
**Goal:** Allow per-monitor warmth offsets and selective shifting.

#### Already Built ✓
- `DisplayCalibrationStoring` protocol + `UserDefaultsDisplayCalibrationStore`
- `warmthOffset(for:)` / `setWarmthOffset(_:for:)` — stores per-display offsets
- `selectiveShiftDisplayIDs` — property for which displays get the circadian curve
- Registered in `SystemIntegration` container

#### Remaining Work
- [ ] **3.1** Apply offsets in `CircadianWorkspaceCoordinator.applyNow()` — currently offsets are stored but never read during the apply loop
- [ ] **3.2** Display enumeration — use `CGGetActiveDisplayList` or `NSScreen.screens` to list connected displays with identifiers
- [ ] **3.3** Per-display Night Shift control
  - Investigate CoreDisplay / DisplayServices private frameworks for per-display color temperature
  - If CBBlueLightClient only supports system-wide control, research `CGDisplaySetTransferByFormula` or ColorSync as alternatives
  - Fallback: gamma table manipulation per-display via `CGSetDisplayTransferByTable`
- [ ] **3.4** Preferences UI — display list with per-display offset sliders and "selective shift" checkboxes
- [ ] **3.5** Handle display connect/disconnect events — `CGDisplayRegisterReconfigurationCallback`
- [ ] **3.6** Persist calibration by display serial number (not display ID, which can change)

#### Phase 3 Enhancements — Display Control & Brightness
- [ ] **3.7** DDC/CI brightness control (High Value)
  - For compatible external monitors, pair color temp changes with actual brightness reduction
  - Use open-source `ddc-macos` library as reference (DDC/CI protocol)
  - When circadian curve dims (e.g., from 6500K → 3200K), also reduce brightness 100% → 70% (user-configurable)
  - Complements per-display calibration naturally
  - Graceful degradation if monitor doesn't support DDC/CI

---

### Phase 4 — Smart Home & Ecosystem Integration
**Goal:** Bridge Shifty's state to HomeKit and Shortcuts.app.

#### Already Built ✓
- `CircadianAutomationBridging` protocol defined
- `DisabledCircadianAutomationBridge` — no-op stub registered in SystemIntegration
- `publish(state:)` and `triggerDeepNightSceneIfNeeded(previous:current:)` method signatures exist
- Existing `IntentHandlers.swift` — Siri Shortcuts for Night Shift toggle, color temp, disable timer, True Tone

#### Remaining Work
- [ ] **4.1** HomeKit Bridge implementation
  - Import HomeKit framework, request home access entitlement
  - Implement `HMHomeManager` delegate to discover available scenes
  - Allow user to map circadian phases to HomeKit scenes (e.g., Deep Night → "Dim Office")
  - Replace `DisabledCircadianAutomationBridge` with `HomeKitCircadianBridge`
  - Trigger scene on phase transition in coordinator's `applyNow()`
- [ ] **4.2** App Intents (macOS 14+)
  - Expose circadian state: `GetCircadianPhaseIntent`, `GetColorTemperatureIntent`
  - Expose actions: `SetCircadianModeIntent`, `PauseCircadianIntent`, `SetBedtimeIntent`
  - Register as `AppShortcutsProvider` for Shortcuts.app discovery
  - Migrate existing `IntentHandlers.swift` from SiriKit Intents to App Intents framework
- [ ] **4.3** Focus Filter integration — auto-adjust circadian behavior per Focus mode (Sleep, Work, etc.)

---

### Phase 4.5 — iCloud Sync for Preferences (Cross-Phase Feature)
**Goal:** Sync circadian configuration and calibration across multiple Macs.

- [ ] **4.5.1** iCloud KeyValue storage
  - Adopt `NSUbiquitousKeyValueStore` for preferences sync
  - Sync data: `CircadianCurveConfiguration`, context profiles, per-display calibration offsets, app-specific rules
  - Listen for `NSUbiquitousKeyValueStoreDidChangeExternallyNotification`
  - Fallback gracefully if iCloud is unavailable

- [ ] **4.5.2** Conflict resolution
  - If user modifies settings on two Macs offline, prefer most recent timestamp
  - User can choose to "merge" or "overwrite" on sync conflict

- [ ] **4.5.3** Preferences UI
  - Toggle "Sync preferences with iCloud" in General preferences
  - Show last-sync timestamp

---

### Phase 6 — Developer-Centric CLI (`shifty-cli`)
**Goal:** Scriptable interface for external automation.

#### Already Built ✓
- `CLICommand` enum: `.queryState`, `.setTemporaryPause`, `.clearTemporaryPause`, `.toggleEnabled`
- `DistributedNotificationCLIBridge` — IPC via `DistributedNotificationCenter`
- Notification names: `io.natethompson.Shifty.cli` / `io.natethompson.Shifty.cli.response`
- `CircadianWorkspaceCoordinator.handleCLICommand(_:payload:)` dispatches commands
- `AppDelegate.observeCLICommands()` listens for incoming notifications
- `currentCLIStatePayload()` serializes state for responses

#### Remaining Work
- [ ] **6.1** Create standalone `shifty-cli` binary target
  - Add new Xcode target (command-line tool)
  - Parse arguments with `ArgumentParser` (Swift package)
  - Commands: `shifty-cli status`, `shifty-cli pause <minutes>`, `shifty-cli resume`, `shifty-cli toggle`, `shifty-cli set-temp <kelvin>`, `shifty-cli get-phase`
  - Post distributed notifications to running Shifty.app
  - Wait for response notification with timeout
  - Output JSON for scriptability (`--json` flag)
- [ ] **6.2** Install mechanism — `shifty-cli install` copies binary to `/usr/local/bin` (or preferences option)
- [ ] **6.3** Shell completions — generate for zsh/bash/fish
- [ ] **6.4** Man page or `--help` documentation

---

## Dependency Strategy

| Dependency | Current Use | Recommendation |
|------------|------------|----------------|
| AXSwift | BrowserManager URL detection | Replace with narrow native AX wrapper (Phase 0) |
| PublicSuffix | Domain/subdomain parsing | Keep if accuracy matters; lightweight alternative if not |
| Sparkle | Auto-updates | Keep for direct distribution; remove for App Store |
| MASPreferences | Preferences host | **Removed** — replaced with native AppKit (in-progress) |
| SwiftLog | Logging | Keep |
| MASShortcut | Keyboard shortcuts | Keep (used in PrefShortcutsViewController) |

### New Dependencies (anticipated)
| Dependency | Phase | Purpose |
|------------|-------|---------|
| swift-argument-parser | 6 | CLI argument parsing |
| HomeKit.framework | 4 | Smart home scene triggers |
| EventKit.framework | 1.7 | Query user's calendar for bedtime awareness |
| HealthKit.framework | 1.8 | Read user's scheduled sleep time |
| ddc-macos (or similar) | 3.7 | DDC/CI monitor brightness control |

---

## Immediate Next Steps (Priority Order)

1. **Verify and commit Phase 0** — MASPreferences removal, dead code cleanup
2. **Phase 1.1–1.2** — Circadian preferences UI + persisted configuration
3. **Phase 2.3** — Color-critical pause with countdown (high user value)
4. **Phase 3.1** — Wire up display calibration offsets in `applyNow()`
5. **Phase 6.1** — Standalone CLI binary (quick win, already has IPC)

## High-Value Feature Priorities (Recommended Early Implementation)

These features offer significant UX improvements with moderate complexity:

| Feature | Phase | Effort | Value | Rationale |
|---------|-------|--------|-------|-----------|
| **Keyboard shortcuts for presets** | 1.10 | Low | High | Designers/devs need quick color-accurate checks; simple to implement |
| **Camera/mic active detection** | 2.5 | Medium | High | Solves the "looking orange on video calls" problem; strong market pain point |
| **Context profiles** | 1.6 | Medium | High | Handles different workflows (design work, late coding, travel); reusable across all phases |
| **Calendar-aware bedtime** | 1.7 | Medium | Medium | Intelligent bedtime shifting for users with dynamic schedules |
| **Health.app sync** | 1.8 | Low | Medium | Auto-populate bedtime instead of manual entry; integrates with Apple ecosystem |
| **Menu bar popover** | 1.11 | High | Medium | More discoverable UI; enables live countdown visualization |
| **DDC/CI brightness** | 3.7 | High | Medium | Pairs color temp with brightness for cinematic darkening experience |
| **iCloud sync** | 4.5 | Medium | Medium | Multi-Mac users get seamless preference sync |

---

## Technical Risks & Open Questions

1. **Per-display color control**: `CBBlueLightClient` may only support system-wide Night Shift. Per-display control likely requires gamma table manipulation (`CGSetDisplayTransferByTable`) which bypasses Night Shift entirely. Need to prototype and validate.

2. **HomeKit entitlements**: Requires provisioning profile with HomeKit capability. May complicate open-source distribution (App Store vs. direct download).

3. **Private API stability**: `CBBlueLightClient`, `CBTrueToneClient`, and `SLSSetAppearanceThemeLegacy` are undocumented. macOS updates can break them without warning.

4. **App Intents migration**: Moving from SiriKit Intents to App Intents is a one-way migration. Existing Shortcuts using old intents will break.

5. **Startup ordering**: The `AppDelegate` → `StatusMenuController` → preferences lazy-init chain is fragile. Phase 0 should solidify this before adding more complexity.

6. **Camera/mic detection (Phase 2.5)**: Apple's privacy indicators (camera-in-use) are available on macOS 11.3+, but reliably detecting them requires either:
   - Polling `AVCaptureDevice.isConnected` per device (resource-intensive)
   - Hooking into system privacy center (limited public API)
   - May require background app refresh capability; validate scope before implementation

7. **Calendar/Health access (Phases 1.7, 1.8)**: Requires user to grant `EventKit` and `HealthKit` permissions in System Preferences. User must accept permission prompts. If denied, features gracefully degrade.

8. **DDC/CI stability (Phase 3.7)**: DDC/CI is not standardized; different monitor vendors implement differently. Some monitors don't support it at all. Must test on multiple external displays and provide graceful fallback (kelvin-only mode).

9. **iCloud sync conflicts (Phase 4.5)**: Determining "most recent" config across devices with clock skew or offline edits is non-trivial. Simple timestamp-based resolution may not always satisfy users. Consider user-facing conflict UI.

10. **Menu bar popover interaction (Phase 1.11)**: `NSPopover` has known interaction quirks (closed on certain clicks, re-appears inconsistently). May need custom window behavior or alternative approach (detachable floating window).
