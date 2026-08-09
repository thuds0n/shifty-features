# Shifty Modernisation Plan

Last audited: 9 August 2026

## Product Direction

Shifty will evolve from a menu-bar extension for Apple's system-wide Night Shift into a contextual circadian workspace optimiser. The core value should come from predictable scheduling, fast colour-critical pauses, app and website rules, and automation that remains understandable when macOS permissions or private display APIs fail.

This remains a direct-download macOS utility. Shifty currently depends on undocumented CoreBrightness and SkyLight interfaces, so Mac App Store compatibility and forward compatibility with future macOS releases must not be assumed.

## Status Legend

- **Implemented**: present in the app and covered by at least basic build verification.
- **Scaffolding**: types or wiring exist, but behaviour is incomplete, incorrect, or untested.
- **Pending**: agreed direction with no complete implementation.
- **Blocked**: no acceptable native macOS implementation is currently known.
- **Unverified**: requires runtime, hardware, permission, signing, or distribution validation.

## Audit Baseline

| Check | Status | Evidence from 9 August 2026 |
|---|---|---|
| Debug build | Implemented | Native arm64 build succeeded with code signing disabled |
| Release build | Implemented | Universal arm64/x86_64 Release build succeeded with code signing disabled |
| Unit tests | Implemented, growing | 20 tests pass: 13 circadian/workspace, 4 `NightShiftManager` and 3 `RuleManager` tests |
| Xcode static analysis | Implemented | `xcodebuild analyze` succeeded |
| Swift 5 complete-concurrency diagnostics | Pending | Build succeeds but reports extensive isolation and `Sendable` warnings |
| Swift 6 build | Blocked | Fails first in AXSwift 0.3.2; application isolation errors remain behind it |
| Visual regression pass | Unverified | Required Screen Recording and Accessibility permissions were unavailable during the audit |
| Signed archive, notarisation and Sparkle update | Unverified | Not exercised during this audit |
| CI | Pending | No CI configuration is present |

The project currently targets macOS 14 and declares Swift 5.0. Swift 6 strict concurrency is a migration goal, not the current implementation state.

## Current Product Map

### Implemented foundation

- Menu-bar Night Shift toggle, temperature slider and Apple schedule control.
- Disable timers and app, running-app, domain and subdomain rules.
- Website URL detection for supported browsers using Apple Events, Accessibility and public-suffix parsing.
- Dark Mode and True Tone integration.
- Global keyboard shortcuts.
- SwiftUI-hosted General, Shortcuts, Whitelist and About preference panes.
- Legacy SiriKit intent-definition handlers.
- SPM dependencies for AXSwift, Sparkle and SwiftDomainParser.
- Sparkle updater wiring and a login-item helper.
- Tested circadian evening/deep-night ramps with an explicit wake boundary, including midnight, daylight-saving and time-zone cases.
- Disable-timer cancellation that invalidates timer ownership and cannot emit a later restore event.

### Scaffolding, not production-ready functionality

- `CircadianWorkspaceCoordinator`, a menu toggle and a partial `WorkspacePolicy` boundary.
- Foreground-media hold state and temporary-pause neutralise/restore behaviour in `ActivityOverrideManager`.
- UserDefaults-backed display offset and selection storage.
- A no-op automation bridge.
- Dormant distributed-notification transport types without an active command listener or standalone CLI target.

### Not implemented

- Persisted circadian preferences or a Circadian preference pane.
- A fully unified transition/restoration policy shared with manual toggles, disable timers and rules.
- Real fullscreen or Picture-in-Picture detection.
- Per-display colour application.
- App Intents, interactive widgets or a standalone `shifty-cli` executable.
- Calendar, HealthKit, Focus, smart-home, Game Mode or Xcode-build awareness.

## Audit Findings

### Resolved correctness findings

- **Circadian day boundary:** an explicit wake time now ends Deep Night. Tests cover both ramps, bedtime, after bedtime, midnight, morning, daylight-saving and time-zone behaviour.
- **Temporary-pause semantics:** a temporary pause now captures the current Night Shift enabled/strength state, neutralises Night Shift without rewriting persistent user intent, and restores the captured output when the pause or circadian mode ends.
- **Foreground-media naming:** the app-level heuristic now reports foreground media rather than claiming fullscreen detection. It continues to hold output; it does not neutralise Night Shift or claim PiP evidence.
- **Disable-timer ownership:** cancellation invalidates and clears the timer before restoration. A regression test proves the cancelled callback cannot restore a second time.
- **CLI property-list safety:** idle payloads omit an absent suspend reason and pass property-list validation. The unauthenticated distributed command listener is disabled until a bounded IPC design is approved.

### Remaining P1 — fix before enabling or expanding circadian mode

1. **The SwiftUI migration regressed localisation and accessibility.** Most new labels are hard-coded in English, and `prefs.whitelist` has no localisation entry, so the key itself can appear in the toolbar. The custom shortcut recorder also needs an accessibility role, label, value and keyboard-operable clear/record actions.

### P2 — foundation and release risks

1. **Swift 6 is not a switch-only upgrade.** AXSwift fails in Swift 6 mode, and complete-concurrency diagnostics identify shared mutable singletons, missing main-actor isolation and non-Sendable callback captures throughout AppKit, timers and shortcuts. Establish a main-actor boundary first, then replace or fork AXSwift.

2. **Domain coverage remains incomplete.** The pure circadian curve, temporary-pause policy, CLI idle payload and timer cancellation now have regression coverage. Coordinator timing, activity-manager lifecycle, display calibration storage, browser parsing/watchers, preference actions, shortcut persistence, timer expiry and wake handling still need tests.

3. **Scaffolding is too concentrated.** `PrefManager.swift` contains preferences, service protocols, display/system adapters, circadian domain logic, activity state, calibration storage, automation, CLI transport and coordination. Split these by responsibility before adding more integrations.

4. **Release metadata is historical.** The app is still version 1.2/build 66, both appcast copies advertise macOS 10.12.4, and update signing uses deprecated DSA metadata. Sparkle 2 recommends an EdDSA migration before a new release.

5. **Public documentation is inconsistent.** The root README says macOS 14 while the hosted English, German and Chinese pages still say macOS 10.12.4. Preference screenshots also predate the SwiftUI migration and require replacement after visual verification.

6. **The repository carries obsolete binary material.** A tracked 12 MB local `SkyLight.framework` is an old Intel/i386 framework, while the project links the system private framework. Confirm it has no archival purpose, then remove it from the repository and history only as a separate, reviewed maintenance decision.

7. **Private API failure is not a first-class state.** CoreBrightness, True Tone and SkyLight calls are abstracted behind protocols, which is a useful seam, but the UI does not expose availability/error state or a safe fallback. Private API failures must never crash launch or silently claim that a change was applied.

### P3 — maintainability issues

- Replace remaining force casts/unwraps in setup, storyboard segue and slider-to-delegate paths with guarded failures.
- Store and remove long-lived notification observers explicitly; test repeated manager creation and teardown.
- Make the whitelist reactive or clearly label it as a snapshot; it currently refreshes only on appearance.
- Clamp shortcut-based colour-temperature mutations rather than relying on the private client.
- Decide whether direct Sparkle distribution is the sole release channel; this determines updater, sandbox and entitlement work.

## Corrections to the July 2026 Proposal

| Proposal | Audit conclusion |
|---|---|
| Swift 6 as the current stack | Incorrect. The project is Swift 5.0 and needs a staged concurrency migration. |
| Three-phase engine is built | Only scaffolding. The overnight calculation and coordination semantics are not production-ready. |
| `NSWorkspace`/`NSScreen` can detect other apps' fullscreen/PiP state | Insufficient. AppKit window notifications describe Shifty's own process; cross-process inspection needs Accessibility, ScreenCaptureKit, or heuristics and explicit privacy handling. |
| Per-display Night Shift | Unproven. CoreBrightness is system-wide. Core Graphics gamma tables are a distinct experimental backend that can conflict with calibration and must restore tables safely. |
| Direct HomeKit integration | Blocked for the native macOS target: the installed macOS SDK has no HomeKit module. Prefer user-authored Shortcuts/App Intents, a companion Apple-platform app, or a separately chosen smart-home service. |
| App Intents and widgets | Feasible on macOS 14, but neither is implemented. Migrate legacy SiriKit intents before adding a widget. |
| Health-based bedtime | Technically feasible with HealthKit on macOS 14, but it requires sensitive-data entitlement, permission, privacy design and robust handling of missing/ambiguous sleep samples. It is not a low-effort feature. |
| Xcode build/Game Mode awareness | Research only. Do not promise these until a stable public signal and a useful restoration policy are demonstrated. |
| Camera/microphone privacy-indicator detection | Research only. Do not scrape system privacy indicators or infer call state without a supported API and explicit user consent. |

## Architecture Direction

Keep AppKit for the menu-bar lifecycle and private-system bridges, SwiftUI for preferences and future widgets, and isolate the product state from both.

```text
AppDelegate / StatusMenuController / App Intents / CLI
                         |
              WorkspaceStateController (@MainActor)
                         |
       Policy engine: schedule + user override + rules
                         |
      NightShiftBackend / ActivitySignals / Automation
                         |
       Private CoreBrightness implementation + fakes
```

Required boundaries:

- `CircadianSchedule`: pure, deterministic date-to-target calculation.
- `WorkspacePolicy`: resolves competing inputs into one desired state and restoration action.
- `NightShiftBackend`: capability, read, apply, preview, restore and error reporting.
- `ActivitySignalProvider`: reports evidence, confidence and permission state; it does not decide colour policy.
- `ConfigurationStore`: versioned `Codable` settings with migration tests.
- `AutomationTransport`: App Intents and CLI adaptors over the same policy API.

All UI-facing state and AppKit integration should be main-actor isolated. Pure schedule calculations can remain value types and be tested independently.

## Delivery Plan

### Phase 0 — stabilise the shipped utility

- [x] Fix timer invalidation and add timer/restore tests.
- [ ] Fix missing preference localisation, migrate new UI copy to localisation keys and add all supported translations.
- [ ] Make the shortcut recorder accessible and validate keyboard/VoiceOver operation.
- [ ] Add CI for Debug build, Release build and unit tests using macOS 14+.
- [ ] Complete a permission-aware visual pass across the menu and all four preference panes.
- [ ] Refresh hosted requirements and screenshots.
- [ ] Decide direct-download distribution, then migrate Sparkle from DSA to EdDSA and validate a signed test update.
- [ ] Remove obsolete local framework/binary references once their purpose is confirmed.

Exit criteria: build, tests, CI, visual checklist, signed archive and update path are green; existing utility behaviour has no known P1 defect.

### Phase 1 — make circadian mode correct and configurable

- [ ] Split circadian, activity, display, automation and CLI code out of `PrefManager.swift`.
- [x] Add schedule tests: before evening, both ramps, bedtime, after bedtime, midnight, morning, DST and time-zone changes.
- [x] Define the morning/daylight transition.
- [ ] Define user-override precedence across all state sources.
- [ ] Implement a single policy controller shared by schedule, rules, temporary pauses and manual controls.
- [ ] Persist versioned configuration: bedtime/wake time, lead times and bounded Kelvin targets.
- [ ] Add a compact Circadian preference pane and menu phase/countdown status.
- [x] Restore the exact prior Night Shift output when a temporary pause ends.
- [ ] Ramp output smoothly and extend restoration precedence across every override type.
- [ ] Add coordinator tests with fake clock, fake backend and fake activity provider.

Exit criteria: circadian mode can run for multiple days without a boundary jump, honours all override types, restores predictably and is fully configurable.

### Phase 2 — automation and fast manual workflows

- [ ] Migrate the legacy intent-definition handlers to App Intents while preserving an explicit compatibility decision for existing shortcuts.
- [ ] Expose status, enable/disable, pause/resume and set-temperature actions through one policy API.
- [ ] Build `shifty-cli` only after choosing a bounded IPC contract; prefer authenticated/local XPC over unauthenticated distributed mutation notifications.
- [ ] Provide stable JSON output, exit codes, timeouts and shell completions.
- [ ] Add an interactive widget only after App Intents are stable.
- [ ] Make 5/15/30-minute colour-critical pause the first high-value workflow; reuse the unified override model.

### Phase 3 — activity sensing as opt-in evidence

- [ ] Start with user-configurable app rules and explicit “pause while this app is frontmost” behaviour.
- [ ] Prototype fullscreen/PiP evidence with Accessibility and, only if justified, ScreenCaptureKit.
- [ ] Surface permission and confidence states; never label a foreground-app heuristic as fullscreen.
- [ ] Test Stage Manager, tiled windows, multiple Spaces, browser video, PiP and app termination.
- [ ] Keep camera/microphone, Xcode-build and Game Mode signals out of product scope until a supported source is proven.

### Phase 4 — display research

- [ ] Enumerate displays and persist stable hardware identity separately from transient display IDs.
- [ ] Build read-only diagnostics before exposing controls.
- [ ] Prototype Core Graphics gamma-table output behind an experimental backend with capture/restore, display-reconfiguration handling and crash recovery.
- [ ] Validate interactions with Night Shift, True Tone, ColorSync profiles, HDR/XDR, sleep/wake and display hot-plugging.
- [ ] Proceed to per-display controls only if the prototype is stable and visually measurable on representative hardware.

Per-display warmth remains research, not a committed product capability.

### Phase 5 — optional contextual integrations

- [ ] EventKit-aware schedule adjustment, with permission and stale-data handling.
- [ ] HealthKit sleep-sample assistance only after a privacy review; it should suggest a schedule, not silently rewrite it.
- [ ] Context profiles if real workflows cannot be expressed through the core policy.
- [ ] Smart-home integration through user-authored Shortcuts or a separately approved companion/service architecture.
- [ ] iCloud preference sync only after configuration versioning and conflict semantics exist.

## Dependency Strategy

| Dependency/interface | Decision |
|---|---|
| AXSwift 0.3.2 | Replace or maintain a narrow native wrapper during Swift 6 migration; current package blocks Swift 6. |
| SwiftDomainParser 1.1.0 | Keep for correct registrable-domain parsing unless tests demonstrate a smaller equivalent. |
| Sparkle 2.9.1 | Keep only for direct distribution; migrate update signing to EdDSA. |
| CoreBrightness/SkyLight | Isolate, capability-check and treat as unstable private backends. |
| `swift-argument-parser` | Add only when a standalone CLI target is approved. |
| HealthKit/EventKit | Apple frameworks; add only with feature-specific privacy and permission work. |
| HomeKit | Do not add to the native macOS target; unavailable in the installed macOS SDK. |

## Immediate Next Slice

The correctness core is now implemented and covered by regression tests. Continue Phase 0 and the architecture foundation of Phase 1 in this order:

1. Restore localisation and accessibility in the SwiftUI preferences, including the Whitelist label and shortcut recorder.
2. Split circadian, activity, display, automation and dormant CLI types out of `PrefManager.swift`.
3. Establish main-actor ownership for AppKit/UI state and introduce fake clock/backend/activity seams for coordinator tests.
4. Extend `WorkspacePolicy` precedence across rules, disable timers and manual controls.
5. Add CI, then complete the permission-aware visual pass and signed Sparkle release validation.

Do not start HomeKit, per-display gamma control, calendar/health integration, widgets or a CLI target until this slice is complete.
