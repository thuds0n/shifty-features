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
| Unit tests | Implemented, growing | 50 tests pass: 28 circadian/workspace, 14 `NightShiftManager`/policy/ramp, 6 `RuleManager` and 2 preference localisation/accessibility tests |
| Xcode static analysis | Implemented | `xcodebuild analyze` succeeded |
| Swift 5 complete-concurrency diagnostics | Pending | Build succeeds but reports extensive isolation and `Sendable` warnings |
| Swift 6 build | Blocked | Fails first in AXSwift 0.3.2; application isolation errors remain behind it |
| Visual regression pass | Partially verified | The menu and all four English preference panes render correctly with Screen Recording and Accessibility granted; full interaction and every localisation remain pending |
| Signed archive, notarisation and Sparkle update | Unverified | Not exercised during this audit |
| CI | Configured, not yet run | GitHub Actions (`.github/workflows/ci.yml`): Debug build and unit tests, universal Release build and static analysis on pushes to `master` and pull requests; all steps pass locally |

The project currently targets macOS 14 and declares Swift 5.0. Swift 6 strict concurrency is a migration goal, not the current implementation state.

## Current Product Map

### Implemented foundation

- Menu-bar Night Shift toggle, temperature slider and Apple schedule control.
- Disable timers and app, running-app, domain and subdomain rules.
- Website URL detection for supported browsers using Apple Events, Accessibility and public-suffix parsing.
- Dark Mode and True Tone integration.
- Global keyboard shortcuts.
- SwiftUI-hosted General, Circadian, Shortcuts, Rules and About preference panes. The Rules pane updates live and removes individual rules.
- Legacy SiriKit intent-definition handlers.
- Localised SwiftUI preference panes in English, German, French, Russian and Simplified Chinese.
- A keyboard-operable shortcut recorder with VoiceOver role, label, value, help and an explicit clear action.
- SPM dependencies for AXSwift, Sparkle and SwiftDomainParser.
- Sparkle updater wiring and a login-item helper.
- Tested circadian evening/deep-night ramps with an explicit wake boundary, including midnight, daylight-saving and time-zone cases.
- Disable-timer cancellation that invalidates timer ownership and cannot emit a later restore event.

### Scaffolding, not production-ready functionality

- An injectable, main-actor `CircadianWorkspaceCoordinator`, a menu toggle and a partial `WorkspacePolicy` boundary.
- `NightShiftPolicy`: one on/off decision for pauses, rules, manual changes and the macOS schedule, applied by `NightShiftManager` only when the decision changes or the system drifts from it.
- Versioned, validated persistence of the circadian curve (bedtime, wake time, lead times and bounded Kelvin targets).
- A menu status line under Circadian Mode showing the current phase, target Kelvin and the next phase change (macOS 14.4 and later; a tooltip on earlier versions).
- A Circadian preference pane with a 24-hour phase strip, live status, wake time, bedtime, evening start and night warmth. All preference panes share one window size, and the window opens centred and remembers its position.
- Foreground-media hold state in `ActivityOverrideManager`. Pauses are a single timed pause owned by `NightShiftManager` and shared by the menu, shortcuts, Shortcuts actions and the CLI transport.
- UserDefaults-backed display offset and selection storage.
- A no-op automation bridge.
- Dormant distributed-notification transport types without an active command listener or standalone CLI target.

### Not implemented

- A fully unified transition/restoration policy shared with manual toggles, disable timers and rules.
- Real fullscreen or Picture-in-Picture detection.
- Per-display colour application.
- App Intents, interactive widgets or a standalone `shifty-cli` executable.
- Calendar, HealthKit, Focus, smart-home, Game Mode or Xcode-build awareness.

## Audit Findings

### Resolved correctness findings

- **Circadian day boundary:** an explicit wake time now ends Deep Night. Tests cover both ramps, bedtime, after bedtime, midnight, morning, daylight-saving and time-zone behaviour.
- **Temporary-pause semantics:** there is one timed pause. It turns Night Shift off without rewriting persistent user intent; when it ends, `NightShiftPolicy` decides the state from rules, the last manual choice and the schedule, and the strength is untouched throughout.
- **Foreground-media naming:** the app-level heuristic now reports foreground media rather than claiming fullscreen detection. It continues to hold output; it does not neutralise Night Shift or claim PiP evidence.
- **Disable-timer ownership:** cancellation invalidates and clears the timer before restoration. A regression test proves the cancelled callback cannot restore a second time.
- **CLI property-list safety:** idle payloads omit an absent suspend reason and pass property-list validation. The unauthenticated distributed command listener is disabled until a bounded IPC design is approved.
- **SwiftUI localisation and accessibility:** all preference copy now uses semantic localisation keys across the five supported languages. The Rules (formerly Whitelist) toolbar label resolves correctly, and the shortcut recorder supports focus, keyboard recording/clearing and explicit accessibility state.
- **Circadian architecture concentration:** preferences, scheduling, policy, activity, calibration, automation, dormant CLI transport and coordination now have focused source files. The coordinator accepts fake clock, mode-store, timer, activity, automation and Night Shift dependencies; lifecycle, output restoration and CLI behaviour have regression coverage.
- **Initial main-actor boundary:** the app delegate, status-menu controller, shortcut binding manager and circadian coordinator now explicitly own their UI-facing work on the main actor. This is a foundation rather than completion of the Swift 6 migration.

### P1 status

The P1 findings from the 9 August audit are resolved in the current branch. Phase 0 release validation and the remaining P2 architecture/release risks still block a production release.

### P2 — foundation and release risks

1. **Swift 6 is not a switch-only upgrade.** AXSwift fails in Swift 6 mode, and complete-concurrency diagnostics identify shared mutable singletons, missing main-actor isolation and non-Sendable callback captures throughout AppKit, timers and shortcuts. Establish a main-actor boundary first, then replace or fork AXSwift.

2. **Domain coverage remains incomplete.** The pure circadian curve, on/off and pause policy, coordinator lifecycle and injected timing, CLI payload and toggling, timer cancellation, preference localisation and shortcut-recorder keyboard behaviour now have regression coverage. Activity-manager lifecycle, display calibration storage, browser parsing/watchers, preference actions, shortcut persistence, timer expiry and wake handling still need tests.

3. **Release metadata is historical.** The app is still version 1.2/build 66, both appcast copies advertise macOS 10.12.4, and update signing uses deprecated DSA metadata. Sparkle 2 recommends an EdDSA migration before a new release.

4. **Public documentation is inconsistent.** The root README says macOS 14 while the hosted English, German and Chinese pages still say macOS 10.12.4. Preference screenshots also predate the SwiftUI migration and require replacement after visual verification.

5. **The repository carries obsolete binary material.** A tracked 12 MB local `SkyLight.framework` is an old Intel/i386 framework, while the project links the system private framework. Confirm it has no archival purpose, then remove it from the repository and history only as a separate, reviewed maintenance decision.

6. **Private API failure is not a first-class state.** CoreBrightness, True Tone and SkyLight calls are abstracted behind protocols, which is a useful seam, but the UI does not expose availability/error state or a safe fallback. Private API failures must never crash launch or silently claim that a change was applied.

### P3 — maintainability issues

- Replace remaining force casts/unwraps in setup, storyboard segue and slider-to-delegate paths with guarded failures.
- Store and remove long-lived notification observers explicitly; test repeated manager creation and teardown.
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
- `NightShiftPolicy` and `NightShiftStrengthPolicy` (in `WorkspacePolicy.swift`): pure resolvers for on/off and strength with documented precedence.
- `NightShiftBackend`: capability, read, apply, preview, restore and error reporting.
- `ActivitySignalProvider`: reports evidence, confidence and permission state; it does not decide colour policy.
- `ConfigurationStore`: versioned `Codable` settings with migration tests.
- `AutomationTransport`: App Intents and CLI adaptors over the same policy API.

All UI-facing state and AppKit integration should be main-actor isolated. Pure schedule calculations can remain value types and be tested independently.

## Delivery Plan

### Phase 0 — stabilise the shipped utility

- [x] Fix timer invalidation and add timer/restore tests.
- [x] Fix missing preference localisation, migrate new UI copy to localisation keys and add all supported translations.
- [x] Make the shortcut recorder keyboard-operable and expose tested VoiceOver semantics.
- [x] Add CI for Debug build, Release build and unit tests using macOS 14+. Confirm the first hosted run is green.
- [ ] Complete a permission-aware visual pass across the menu and all four preference panes.
- [ ] Refresh hosted requirements and screenshots.
- [ ] Decide direct-download distribution, then migrate Sparkle from DSA to EdDSA and validate a signed test update.
- [ ] Remove obsolete local framework/binary references once their purpose is confirmed.

Exit criteria: build, tests, CI, visual checklist, signed archive and update path are green; existing utility behaviour has no known P1 defect.

### Phase 1 — make circadian mode correct and configurable

- [x] Split circadian, activity, display, automation and CLI code out of `PrefManager.swift`.
- [x] Add schedule tests: before evening, both ramps, bedtime, after bedtime, midnight, morning, DST and time-zone changes.
- [x] Define the morning/daylight transition.
- [x] Define user-override precedence across all state sources: a pause, then app/website rules, then a manual on/off (held until the next scheduled start or end), then the macOS schedule. A hand-set strength holds until the next circadian phase change.
- [x] Implement a single policy controller shared by schedule, rules, temporary pauses and manual controls: `NightShiftPolicy` decides on/off and `NightShiftStrengthPolicy` decides strength, from one pause model.
- [x] Persist versioned configuration: bedtime/wake time, lead times and bounded Kelvin targets.
- [x] Add menu phase and next-transition status.
- [x] Add a compact Circadian preference pane.
- [x] Restore Night Shift predictably when a pause ends: the policy re-derives on/off and the strength is never changed by a pause.
- [x] Ramp output smoothly and extend restoration precedence across every override type: strength changes of 2% or more fade over three seconds using previews and commit once, and every override restores through the shared on/off and strength policies.
- [x] Add coordinator tests with fake clock, fake backend and fake activity provider.

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

The correctness, preference-compliance and initial architecture slices are now implemented and covered by tests. Continue Phase 0 and Phase 1 in this order:

1. Confirm the first hosted CI run is green.
2. Add activity lifecycle, display calibration and browser watcher tests around the remaining foundation seams.
3. Complete full interaction and non-English visual passes.
4. Refresh hosted documentation and screenshots, then validate the signed archive and Sparkle update path.

Do not start HomeKit, per-display gamma control, calendar/health integration, widgets or a CLI target until this slice is complete.
