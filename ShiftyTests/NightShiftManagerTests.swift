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
