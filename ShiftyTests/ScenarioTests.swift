import XCTest
@testable import Shifty

/// End-to-end scenarios that wire the real `NightShiftManager`, `RuleManager` and
/// `CircadianWorkspaceCoordinator` together. Only the system edges are faked:
/// CoreBrightness, the clock, the frontmost app and the current website.
final class ScenarioTests: XCTestCase {
    private static let suiteName = "ScenarioTests"

    private var client: ScenarioNightShiftClient!
    private var context: FakeRuleContext!
    private var defaults: UserDefaults!
    private var rules: RuleManager!
    private var nightShift: NightShiftManager!

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(false, forKey: Keys.trueToneControl)
        UserDefaults.standard.set(false, forKey: Keys.isDarkModeSyncEnabled)
        defaults = UserDefaults(suiteName: Self.suiteName)
        defaults.removePersistentDomain(forName: Self.suiteName)

        client = ScenarioNightShiftClient()
        context = FakeRuleContext()
        nightShift = NightShiftManager(
            client: client,
            rampScheduler: ImmediateScenarioRampScheduler(),
            ruleManager: { [unowned self] in self.rules })
        rules = RuleManager(
            defaults: defaults,
            context: context,
            notificationCenter: NotificationCenter()
        ) { [unowned self] event in
            self.nightShift.respond(to: event)
        }
    }

    override func tearDown() {
        nightShift.invalidateDisableTimer()
        defaults.removePersistentDomain(forName: Self.suiteName)
        rules = nil
        nightShift = nil
        super.tearDown()
    }

    // MARK: Pause

    func testTurningNightShiftOnEndsARunningPause() {
        client.scheduledState = true
        client.isNightShiftEnabled = true

        startPause(minutes: 10)
        XCTAssertTrue(nightShift.isPaused)
        XCTAssertFalse(client.isNightShiftEnabled)

        nightShift.isNightShiftEnabled = true

        XCTAssertFalse(nightShift.isPaused)
        XCTAssertNil(nightShift.nightShiftDisableTimer)
        XCTAssertTrue(client.isNightShiftEnabled)
    }

    func testRuleChangesDuringAPauseDoNotEndIt() {
        client.scheduledState = true
        client.isNightShiftEnabled = true
        context.frontmost = "com.example.editor"
        rules.addCurrentAppDisableRule(bundleIdentifier: "com.example.editor")

        startPause(minutes: 10)
        rules.removeCurrentAppDisableRule(bundleIdentifier: "com.example.editor")

        XCTAssertFalse(client.isNightShiftEnabled, "The pause still holds after the rule is removed")
        nightShift.resumeFromPause()
        XCTAssertTrue(client.isNightShiftEnabled, "Resuming hands back to the schedule")
    }

    // MARK: App rules

    func testFrontAppRuleFollowsTheFrontmostAppAndRemovalRestores() {
        client.scheduledState = true
        client.isNightShiftEnabled = true
        context.frontmost = "com.example.editor"

        rules.addCurrentAppDisableRule(bundleIdentifier: "com.example.editor")
        XCTAssertFalse(client.isNightShiftEnabled, "Off while the app is in front")

        switchTo("com.apple.finder")
        XCTAssertTrue(client.isNightShiftEnabled, "Back on after switching away")

        switchTo("com.example.editor")
        XCTAssertFalse(client.isNightShiftEnabled, "Off again after switching back")

        rules.removeCurrentAppDisableRule(bundleIdentifier: "com.example.editor")
        XCTAssertTrue(client.isNightShiftEnabled, "Back on once the rule is removed")
    }

    func testRunningAppRuleAppliesWhileTheAppIsOpenInTheBackground() {
        client.scheduledState = true
        client.isNightShiftEnabled = true
        context.frontmost = "com.example.player"
        context.running = ["com.example.player", "com.apple.finder"]

        rules.addRunningAppDisableRule(bundleIdentifier: "com.example.player")
        switchTo("com.apple.finder")
        XCTAssertFalse(client.isNightShiftEnabled, "Still off while the app runs in the background")

        context.running = ["com.apple.finder"]
        rules.evaluateCurrentContext()
        XCTAssertTrue(client.isNightShiftEnabled, "Back on once the app quits")
    }

    func testManualOnRemovesTheRuleThatWasHoldingNightShiftOff() {
        client.scheduledState = true
        client.isNightShiftEnabled = true
        context.frontmost = "com.example.editor"
        rules.addCurrentAppDisableRule(bundleIdentifier: "com.example.editor")

        nightShift.isNightShiftEnabled = true

        XCTAssertTrue(client.isNightShiftEnabled)
        XCTAssertTrue(rules.currentAppDisableRuleSnapshot.isEmpty)
    }

    // MARK: Website rules

    func testSubdomainExceptionFollowsTheScheduleInsteadOfForcingNightShiftOn() {
        context.website = WebsiteContext(domain: "example.com", subdomain: "docs.example.com")
        client.scheduledState = false
        client.isNightShiftEnabled = false

        rules.addDomainDisableRule(forDomain: "example.com")
        rules.setSubdomainRule(.enabled, forSubdomain: "docs.example.com")

        XCTAssertEqual(rules.ruleForCurrentSubdomain, .enabled)
        XCTAssertFalse(rules.disableRuleIsActive)
        XCTAssertFalse(client.isNightShiftEnabled, "Daytime: the exception doesn't force Night Shift on")
        XCTAssertFalse(client.enabledCalls.contains(true))

        client.scheduledState = true
        client.isNightShiftEnabled = true
        nightShift.respond(to: .enteredScheduledNightShift)
        XCTAssertTrue(client.isNightShiftEnabled, "Night: the exception keeps Night Shift on for the subdomain")
    }

    func testDomainRuleTurnsNightShiftOffAtNightAndRemovalRestores() {
        context.website = WebsiteContext(domain: "example.com", subdomain: "example.com")
        client.scheduledState = true
        client.isNightShiftEnabled = true

        rules.addDomainDisableRule(forDomain: "example.com")
        XCTAssertFalse(client.isNightShiftEnabled)

        rules.removeDomainDisableRule(forDomain: "example.com")
        XCTAssertTrue(client.isNightShiftEnabled)
    }

    // MARK: Circadian strength

    @MainActor
    func testHandSetStrengthHoldsUntilTheNextPhaseChange() {
        client.scheduledState = true
        client.isNightShiftEnabled = true
        let harness = makeCircadian(at: time(hour: 21, minute: 30))

        harness.coordinator.applyNow()
        let eveningTarget = client.colorTemperature
        XCTAssertGreaterThan(eveningTarget, 0)

        nightShift.colorTemperature = 0.1
        harness.coordinator.holdManualStrength()
        harness.clock.now = time(hour: 21, minute: 40)
        harness.coordinator.applyNow()
        XCTAssertEqual(client.colorTemperature, 0.1, "Held within the same phase")

        harness.clock.now = time(hour: 22, minute: 20)
        harness.coordinator.applyNow()
        XCTAssertNil(harness.coordinator.manualStrengthHoldUntil)
        XCTAssertGreaterThan(client.colorTemperature, eveningTarget, "Follows the Deep Night target after the phase change")
    }

    @MainActor
    func testTurningCircadianModeOnFadesToTheTarget() {
        client.scheduledState = true
        client.isNightShiftEnabled = true
        client.colorTemperature = 0
        client.strengthWrites.removeAll()
        let harness = makeCircadian(at: time(hour: 23, minute: 30))

        harness.coordinator.applyNow()

        XCTAssertGreaterThan(client.previews.count, 10, "The change is faded through previews")
        XCTAssertEqual(client.previews, client.previews.sorted(), "The fade moves in one direction")
        XCTAssertEqual(client.strengthWrites, [1], "Only the Deep Night target is committed")
    }

    // MARK: Helpers

    private func startPause(minutes: Int) {
        let started = expectation(description: "Pause started")
        nightShift.pause(for: TimeInterval(minutes * 60))
        DispatchQueue.main.async { started.fulfill() }
        wait(for: [started], timeout: 1)
    }

    private func switchTo(_ bundleIdentifier: String) {
        context.frontmost = bundleIdentifier
        rules.evaluateCurrentContext()
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
        return calendar
    }

    private func time(hour: Int, minute: Int) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone, year: 2026, month: 8, day: 9, hour: hour, minute: minute))!
    }

    private struct CircadianHarness {
        let coordinator: CircadianWorkspaceCoordinator
        let clock: ScenarioClock
    }

    @MainActor
    private func makeCircadian(at date: Date) -> CircadianHarness {
        let clock = ScenarioClock(now: date)
        let coordinator = CircadianWorkspaceCoordinator(
            transition: CircadianTransitionEngine(calendar: calendar),
            activityOverride: IdleActivityOverride(),
            automationBridge: DisabledCircadianAutomationBridge(),
            nightShift: nightShift,
            modeStore: EnabledModeStore(),
            configurationStore: DefaultConfigurationStore(),
            clock: clock,
            refreshScheduler: ManualRefreshScheduler())
        return CircadianHarness(coordinator: coordinator, clock: clock)
    }
}

// MARK: - Fakes

/// A CoreBrightness stand-in whose schedule hand-back behaves like the real client.
private final class ScenarioNightShiftClient: NightShiftSystemControlling {
    var supportsNightShift = true
    var isNightShiftEnabled = false
    var colorTemperature: Float = 0.5 {
        didSet { strengthWrites.append(colorTemperature) }
    }
    var schedule: ScheduleType = .solar
    var scheduledState = false

    var strengthWrites: [Float] = []
    private(set) var previews: [Float] = []
    private(set) var enabledCalls: [Bool] = []

    func previewColorTemperature(_ value: Float) {
        previews.append(value)
    }

    func setNightShiftEnabled(_ newValue: Bool) {
        enabledCalls.append(newValue)
        isNightShiftEnabled = newValue
    }

    func setToSchedule() {
        isNightShiftEnabled = scheduledState
    }

    func setStatusNotificationBlock(_ block: @escaping () -> Void) {
        _ = block
    }
}

private final class FakeRuleContext: RuleContextProviding {
    var frontmost: String?
    var running: [String] = []
    var website = WebsiteContext(domain: nil, subdomain: nil)

    var frontmostBundleIdentifier: String? { frontmost }
    var runningBundleIdentifiers: [String] { running + [frontmost].compactMap { $0 } }
    var isSupportedBrowserInFront: Bool { false }
    func stopBrowserWatcher() {}
    func updateForSupportedBrowser() {}
}

private final class ImmediateScenarioRampScheduler: StrengthRampScheduling {
    private final class Handle: WorkspaceRefreshTimer {
        func invalidate() {}
    }

    func run(_ values: [Float], interval: TimeInterval, step: @escaping (Float) -> Bool) -> WorkspaceRefreshTimer {
        for value in values where !step(value) {
            break
        }
        return Handle()
    }
}

private final class ScenarioClock: WorkspaceClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

private final class IdleActivityOverride: ActivityOverrideManaging {
    var currentOverride = ActivityOverrideSnapshot.none
    var onChange: ((ActivityOverrideSnapshot) -> Void)?
    func start() {}
    func stop() {}
}

private final class EnabledModeStore: CircadianModeStoring {
    var isCircadianModeEnabled = true
}

private final class DefaultConfigurationStore: CircadianConfigurationStoring {
    var configuration = CircadianCurveConfiguration.default
}

private final class ManualRefreshScheduler: WorkspaceRefreshScheduling {
    private final class Handle: WorkspaceRefreshTimer {
        func invalidate() {}
    }

    func scheduleRepeating(every interval: TimeInterval, action: @escaping () -> Void) -> WorkspaceRefreshTimer {
        Handle()
    }
}
