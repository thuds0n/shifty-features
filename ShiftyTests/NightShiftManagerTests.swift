import XCTest
@testable import Shifty

final class NightShiftManagerTests: XCTestCase {
    private var defaults: UserDefaults { UserDefaults.standard }

    override func setUp() {
        super.setUp()
        defaults.set(false, forKey: Keys.trueToneControl)
        defaults.set(false, forKey: Keys.isDarkModeSyncEnabled)
    }

    func testUserEnabledNightShiftSetsClientStateAndUserSet() {
        let client = FakeNightShiftClient()
        let manager = NightShiftManager(client: client)

        manager.respond(to: .userEnabledNightShift)

        XCTAssertEqual(manager.userSet, .on)
        XCTAssertEqual(manager.nightShiftDisableTimerState, .off)
        XCTAssertEqual(client.setNightShiftEnabledCalls.last, true)
    }

    func testUserDisabledNightShiftSetsClientStateAndUserSet() {
        let client = FakeNightShiftClient()
        let manager = NightShiftManager(client: client)

        manager.respond(to: .userDisabledNightShift)

        XCTAssertEqual(manager.userSet, .off)
        XCTAssertEqual(client.setNightShiftEnabledCalls.last, false)
    }

    func testDisableRuleDeactivatedRestoresScheduleWhenUserNotSet() {
        let client = FakeNightShiftClient()
        let manager = NightShiftManager(client: client)
        manager.userSet = .notSet
        manager.nightShiftDisableTimerState = .off

        manager.respond(to: .nightShiftDisableRuleDeactivated)

        XCTAssertEqual(client.setToScheduleCallCount, 1)
    }

    func testInvalidatingDisableTimerCancelsItsLaterRestoreEvent() {
        let client = FakeNightShiftClient()
        let manager = NightShiftManager(client: client)
        let timerStarted = expectation(description: "Disable timer started")

        manager.setDisableTimer(forTimeInterval: 0.1)
        DispatchQueue.main.async {
            timerStarted.fulfill()
        }
        wait(for: [timerStarted], timeout: 1)

        manager.invalidateDisableTimer()

        XCTAssertNil(manager.nightShiftDisableTimer)
        XCTAssertEqual(manager.nightShiftDisableTimerState, .off)
        XCTAssertEqual(client.setToScheduleCallCount, 1)

        let timerWouldHaveFired = expectation(description: "Cancelled timer did not fire")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            timerWouldHaveFired.fulfill()
        }
        wait(for: [timerWouldHaveFired], timeout: 1)

        XCTAssertEqual(client.setToScheduleCallCount, 1)
    }
}

private final class FakeNightShiftClient: NightShiftSystemControlling {
    var supportsNightShift: Bool = true
    var isNightShiftEnabled: Bool = false
    var colorTemperature: Float = 0
    var schedule: ScheduleType = .off
    var scheduledState: Bool = false

    private(set) var setNightShiftEnabledCalls: [Bool] = []
    private(set) var setToScheduleCallCount: Int = 0

    func previewColorTemperature(_ value: Float) {
        colorTemperature = value
    }

    func setNightShiftEnabled(_ newValue: Bool) {
        isNightShiftEnabled = newValue
        setNightShiftEnabledCalls.append(newValue)
    }

    func setToSchedule() {
        setToScheduleCallCount += 1
    }

    func setStatusNotificationBlock(_ block: @escaping () -> Void) {
        _ = block
    }
}
