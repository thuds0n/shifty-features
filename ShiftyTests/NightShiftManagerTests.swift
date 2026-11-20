import AppKit
import XCTest
@testable import Shifty

final class NightShiftManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var pauseTimer: ManualPauseTimer!
    private var wakeNotifications: NotificationCenter!

    override func setUpWithError() throws {
        defaults = try makeIsolatedDefaults()
        pauseTimer = ManualPauseTimer()
        wakeNotifications = NotificationCenter()
    }

    private func makeManager(
        client: FakeNightShiftClient,
        rampScheduler: StrengthRampScheduling = TimerStrengthRampScheduler()
    ) -> NightShiftManager {
        let rules = RuleManager(
            defaults: defaults,
            context: FakeRuleContext(),
            notificationCenter: NotificationCenter()
        ) { _ in }
        return NightShiftManager(
            client: client,
            rampScheduler: rampScheduler,
            defaults: defaults,
            makePauseTimer: pauseTimer.schedule,
            wakeNotificationCenter: wakeNotifications,
            ruleManager: { rules }
        )
    }

    func testUserEnabledNightShiftSetsClientStateAndUserSet() {
        let client = FakeNightShiftClient()
        let manager = makeManager(client: client)

        manager.respond(to: .userEnabledNightShift)

        XCTAssertEqual(manager.userSet, .on)
        XCTAssertEqual(manager.nightShiftDisableTimerState, .off)
        XCTAssertEqual(client.setNightShiftEnabledCalls.last, true)
    }

    func testUserDisabledNightShiftSetsClientStateAndUserSet() {
        let client = FakeNightShiftClient()
        let manager = makeManager(client: client)

        manager.respond(to: .userDisabledNightShift)

        XCTAssertEqual(manager.userSet, .off)
        XCTAssertEqual(client.setNightShiftEnabledCalls.last, false)
    }

    func testDisableRuleDeactivatedRestoresScheduleWhenUserNotSet() {
        let client = FakeNightShiftClient()
        let manager = makeManager(client: client)
        manager.userSet = .notSet
        manager.nightShiftDisableTimerState = .off

        manager.respond(to: .nightShiftDisableRuleDeactivated)

        XCTAssertEqual(client.setToScheduleCallCount, 1)
    }

    func testInvalidatingDisableTimerCancelsItsLaterRestoreEvent() {
        let client = FakeNightShiftClient()
        let manager = makeManager(client: client)

        manager.pause(for: 600)
        XCTAssertTrue(manager.isPaused)
        manager.invalidateDisableTimer()

        XCTAssertFalse(pauseTimer.timer.isValid)
        XCTAssertNil(manager.nightShiftDisableTimer)
        XCTAssertEqual(manager.nightShiftDisableTimerState, .off)
        XCTAssertEqual(client.setToScheduleCallCount, 1)

        pauseTimer.deliverExpiry()
        XCTAssertEqual(client.setToScheduleCallCount, 1)
    }

    func testWakeReconcilesAnActivePauseAgainstTheSchedule() {
        let client = FakeNightShiftClient()
        let manager = makeManager(client: client)
        manager.pause(for: 600)
        client.scheduledState = true
        client.isNightShiftEnabled = true

        wakeNotifications.post(name: NSWorkspace.didWakeNotification, object: nil)

        XCTAssertTrue(manager.isPaused)
        XCTAssertFalse(client.isNightShiftEnabled)
    }

    func testWakeRepairsDriftWithAnUnchangedFollowScheduleDecision() {
        let client = FakeNightShiftClient()
        client.scheduledState = true
        client.isNightShiftEnabled = true
        let manager = makeManager(client: client)
        manager.respond(to: .scheduleChanged)

        client.isNightShiftEnabled = false
        wakeNotifications.post(name: NSWorkspace.didWakeNotification, object: nil)

        XCTAssertTrue(manager.isNightShiftEnabled)
        XCTAssertEqual(client.setToScheduleCallCount, 2)

        wakeNotifications.post(name: NSWorkspace.didWakeNotification, object: nil)
        XCTAssertEqual(client.setToScheduleCallCount, 2, "An already-correct wake needs no write")
    }

    func testWakeDuringPauseDropsManualChoiceWhenScheduleStarts() {
        let client = FakeNightShiftClient()
        let manager = makeManager(client: client)
        manager.setNightShiftEnabled(to: false)
        manager.pause(for: 600)

        client.scheduledState = true
        wakeNotifications.post(name: NSWorkspace.didWakeNotification, object: nil)

        XCTAssertTrue(manager.isPaused)
        XCTAssertFalse(client.isNightShiftEnabled)
        XCTAssertEqual(manager.userSet, .notSet)
        pauseTimer.deliverExpiry()
        XCTAssertTrue(client.isNightShiftEnabled)
    }

    func testWakeDuringPauseKeepsManualChoiceWhenScheduleDoesNotChange() {
        let client = FakeNightShiftClient()
        client.scheduledState = true
        client.isNightShiftEnabled = true
        let manager = makeManager(client: client)
        manager.setNightShiftEnabled(to: false)
        manager.pause(for: 600)

        wakeNotifications.post(name: NSWorkspace.didWakeNotification, object: nil)
        pauseTimer.deliverExpiry()

        XCTAssertEqual(manager.userSet, .off)
        XCTAssertFalse(client.isNightShiftEnabled)
    }

    // MARK: Policy precedence

    func testPolicyPrecedence() {
        func output(paused: Bool = false, rule: Bool = false, manual: UserSet = .notSet) -> NightShiftOutput {
            NightShiftPolicy.output(for: NightShiftPolicyInputs(isPaused: paused, isDisableRuleActive: rule, manualOverride: manual))
        }

        XCTAssertEqual(output(), .followSchedule)
        XCTAssertEqual(output(manual: .on), .on)
        XCTAssertEqual(output(manual: .off), .off)
        XCTAssertEqual(output(rule: true, manual: .on), .off, "A rule outranks a manual on")
        XCTAssertEqual(output(paused: true, manual: .on), .off, "A pause outranks a manual on")
        XCTAssertEqual(output(paused: true, rule: true), .off)
    }

    // MARK: Reconciliation

    func testScheduleStartDuringAPauseIsForcedBackOff() {
        let client = FakeNightShiftClient()
        let manager = makeManager(client: client)
        manager.nightShiftDisableTimerState = .custom(endDate: Date().addingTimeInterval(600))
        manager.respond(to: .nightShiftDisableTimerStarted)

        client.isNightShiftEnabled = true
        client.scheduledState = true
        manager.respond(to: .enteredScheduledNightShift)

        XCTAssertEqual(client.setNightShiftEnabledCalls.last, false)
        XCTAssertFalse(client.isNightShiftEnabled)
    }

    func testUnchangedDecisionDoesNotCallCoreBrightnessAgain() {
        let client = FakeNightShiftClient()
        let manager = makeManager(client: client)

        manager.respond(to: .userDisabledNightShift)
        manager.respond(to: .nightShiftEnableRuleDeactivated)
        manager.respond(to: .nightShiftDisableRuleDeactivated)

        XCTAssertEqual(client.setNightShiftEnabledCalls, [false])
        XCTAssertEqual(client.setToScheduleCallCount, 0)
    }

    func testScheduleChangeAlwaysHandsControlBackToTheSchedule() {
        let client = FakeNightShiftClient()
        let manager = makeManager(client: client)
        manager.respond(to: .nightShiftDisableRuleDeactivated)

        manager.respond(to: .scheduleChanged)

        XCTAssertEqual(manager.userSet, .notSet)
        XCTAssertEqual(client.setToScheduleCallCount, 2)
    }

    func testTurningNightShiftOnCancelsARunningPause() {
        let client = FakeNightShiftClient()
        let manager = makeManager(client: client)
        manager.pause(for: 600)
        XCTAssertTrue(manager.isPaused)

        manager.respond(to: .userEnabledNightShift)

        XCTAssertNil(manager.nightShiftDisableTimer)
        XCTAssertEqual(manager.nightShiftDisableTimerState, .off)
        XCTAssertEqual(client.setNightShiftEnabledCalls.last, true)
    }

    func testPauseHoldsAgainstOtherEventsAndEndsBackOnTheManualChoice() {
        let client = FakeNightShiftClient()
        let manager = makeManager(client: client)
        manager.respond(to: .userEnabledNightShift)
        manager.pause(for: 600)
        XCTAssertTrue(manager.isPaused)
        XCTAssertFalse(client.isNightShiftEnabled)

        manager.respond(to: .nightShiftDisableRuleDeactivated)
        XCTAssertFalse(client.isNightShiftEnabled, "Other events must not end the pause early")

        pauseTimer.deliverExpiry()
        XCTAssertFalse(manager.isPaused)
        XCTAssertTrue(client.isNightShiftEnabled, "The manual on made before the pause still applies")
    }

    // MARK: Strength ramp

    func testRampEasesToTheExactTargetAndSkipsSmallChanges() {
        let values = StrengthRamp.values(from: 0.2, to: 0.8)
        XCTAssertEqual(values.count, 90)
        XCTAssertEqual(values.last, 0.8)
        XCTAssertEqual(values, values.sorted(), "Moves in one direction")
        XCTAssertTrue(StrengthRamp.values(from: 0.5, to: 0.51).isEmpty)
    }

    func testLargeStrengthChangeFadesWithPreviewsAndCommitsOnce() {
        let client = FakeNightShiftClient()
        client.isNightShiftEnabled = true
        client.colorTemperature = 0.2
        client.clearRecordedWrites()
        let manager = makeManager(client: client, rampScheduler: ImmediateRampScheduler())

        manager.applyWorkspacePolicyDecision(.applyStrength(0.8))

        XCTAssertEqual(client.previewValues.count, 89)
        XCTAssertEqual(client.colorTemperature, 0.8)
        XCTAssertEqual(client.colorTemperatureWrites, [0.8])
    }

    func testSmallStrengthChangeIsAppliedDirectly() {
        let client = FakeNightShiftClient()
        client.isNightShiftEnabled = true
        client.colorTemperature = 0.5
        client.clearRecordedWrites()
        let manager = makeManager(client: client, rampScheduler: ImmediateRampScheduler())

        manager.applyWorkspacePolicyDecision(.applyStrength(0.51))

        XCTAssertTrue(client.previewValues.isEmpty)
        XCTAssertEqual(client.colorTemperatureWrites, [0.51])
    }

    func testFadeStopsWhenNightShiftTurnsOff() {
        let client = FakeNightShiftClient()
        client.isNightShiftEnabled = true
        client.colorTemperature = 0.2
        client.onPreview = { if client.previewValues.count == 10 { client.isNightShiftEnabled = false } }
        client.clearRecordedWrites()
        let manager = makeManager(client: client, rampScheduler: ImmediateRampScheduler())

        manager.applyWorkspacePolicyDecision(.applyStrength(0.8))

        XCTAssertEqual(client.previewValues.count, 10)
        XCTAssertTrue(client.colorTemperatureWrites.isEmpty, "An interrupted fade commits nothing")
    }

    func testNoChangeCancelsAStartedFadeBeforeItCanCommit() {
        let client = FakeNightShiftClient()
        client.isNightShiftEnabled = true
        client.colorTemperature = 0.2
        client.clearRecordedWrites()
        let scheduler = ManualRampScheduler()
        let manager = makeManager(client: client, rampScheduler: scheduler)
        manager.applyWorkspacePolicyDecision(.applyStrength(0.8))
        scheduler.advanceOneStep()
        XCTAssertEqual(client.previewValues.count, 1)

        manager.applyWorkspacePolicyDecision(.noChange)
        scheduler.advanceOneStep()

        XCTAssertEqual(client.previewValues.count, 1)
        XCTAssertTrue(client.colorTemperatureWrites.isEmpty)
    }
}

private final class FakeNightShiftClient: NightShiftSystemControlling {
    var supportsNightShift: Bool = true
    var isNightShiftEnabled: Bool = false
    var colorTemperature: Float = 0 {
        didSet { colorTemperatureWrites.append(colorTemperature) }
    }
    private(set) var colorTemperatureWrites: [Float] = []
    private(set) var previewValues: [Float] = []
    var onPreview: (() -> Void)?

    func clearRecordedWrites() {
        colorTemperatureWrites.removeAll()
    }
    var schedule: ScheduleType = .off
    var scheduledState: Bool = false

    private(set) var setNightShiftEnabledCalls: [Bool] = []
    private(set) var setToScheduleCallCount: Int = 0

    func previewColorTemperature(_ value: Float) {
        previewValues.append(value)
        onPreview?()
    }

    func setNightShiftEnabled(_ newValue: Bool) {
        isNightShiftEnabled = newValue
        setNightShiftEnabledCalls.append(newValue)
    }

    func setToSchedule() {
        setToScheduleCallCount += 1
        isNightShiftEnabled = scheduledState
    }

    func setStatusNotificationBlock(_ block: @escaping () -> Void) {
        _ = block
    }
}

private final class ImmediateRampScheduler: StrengthRampScheduling {
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

private final class ManualRampScheduler: StrengthRampScheduling, WorkspaceRefreshTimer {
    private var remaining: ArraySlice<Float> = []
    private var step: ((Float) -> Bool)?

    func run(_ values: [Float], interval: TimeInterval, step: @escaping (Float) -> Bool) -> WorkspaceRefreshTimer {
        remaining = values[...]
        self.step = step
        return self
    }

    func advanceOneStep() {
        guard let step, let value = remaining.popFirst() else { return }
        if !step(value) || remaining.isEmpty {
            invalidate()
        }
    }

    func invalidate() {
        remaining = []
        step = nil
    }
}

/// An unscheduled timer with a fixed deadline. Delivering its callback directly
/// also lets tests simulate a stale callback after invalidation.
final class ManualPauseTimer {
    private let now = Date(timeIntervalSince1970: 1_786_258_800)
    private(set) var timer: Timer!
    private var action: ((Timer) -> Void)!

    func schedule(interval: TimeInterval, action: @escaping @Sendable (Timer) -> Void) -> Timer {
        let timer = Timer(fire: now.addingTimeInterval(interval), interval: 0, repeats: false, block: action)
        self.timer = timer
        self.action = action
        return timer
    }

    func deliverExpiry() {
        action(timer)
    }
}

extension XCTestCase {
    func makeIsolatedDefaults() throws -> UserDefaults {
        let suiteName = "ShiftyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }
}
