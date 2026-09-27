import XCTest
@testable import Shifty

final class CircadianWorkspaceTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
        return calendar
    }

    func testTargetRemainsDeepNightAfterBedtime() {
        let engine = CircadianTransitionEngine(calendar: calendar)

        let target = engine.target(for: date(year: 2026, month: 8, day: 9, hour: 23, minute: 30))

        XCTAssertEqual(target.phase, .deepNight)
        XCTAssertEqual(target.kelvin, CircadianCurveConfiguration.default.deepNightKelvin)
        XCTAssertEqual(target.phaseProgress, 1)
    }

    func testTargetRemainsDeepNightAfterMidnight() {
        let engine = CircadianTransitionEngine(calendar: calendar)

        let target = engine.target(for: date(year: 2026, month: 8, day: 10, hour: 2))

        XCTAssertEqual(target.phase, .deepNight)
        XCTAssertEqual(target.kelvin, CircadianCurveConfiguration.default.deepNightKelvin)
    }

    func testTargetReturnsToDaylightAtWakeTime() {
        let engine = CircadianTransitionEngine(calendar: calendar)

        let target = engine.target(for: date(year: 2026, month: 8, day: 10, hour: 7))

        XCTAssertEqual(target.phase, .daylight)
        XCTAssertEqual(target.kelvin, CircadianCurveConfiguration.default.daylightKelvin)
    }

    func testTargetIsDaylightBeforeTheEveningRamp() {
        let engine = CircadianTransitionEngine(calendar: calendar)

        let target = engine.target(for: date(year: 2026, month: 8, day: 9, hour: 20))

        XCTAssertEqual(target.phase, .daylight)
        XCTAssertEqual(target.kelvin, CircadianCurveConfiguration.default.daylightKelvin)
    }

    func testTargetReachesDeepNightAtBedtime() {
        let engine = CircadianTransitionEngine(calendar: calendar)

        let target = engine.target(for: date(year: 2026, month: 8, day: 9, hour: 23))

        XCTAssertEqual(target.phase, .deepNight)
        XCTAssertEqual(target.phaseProgress, 1)
        XCTAssertEqual(target.kelvin, CircadianCurveConfiguration.default.deepNightKelvin)
    }

    func testTargetInterpolatesAcrossEveningRamp() {
        let engine = CircadianTransitionEngine(calendar: calendar)

        let target = engine.target(for: date(year: 2026, month: 8, day: 9, hour: 21, minute: 30))

        XCTAssertEqual(target.phase, .evening)
        XCTAssertEqual(target.phaseProgress, 0.4, accuracy: 0.001)
        XCTAssertEqual(target.kelvin, 5700)
    }

    func testTargetInterpolatesAcrossDeepNightRamp() {
        let engine = CircadianTransitionEngine(calendar: calendar)

        let target = engine.target(for: date(year: 2026, month: 8, day: 9, hour: 22, minute: 30))

        XCTAssertEqual(target.phase, .deepNight)
        XCTAssertEqual(target.phaseProgress, 1.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(target.kelvin, 4067)
    }

    func testTargetUsesTheCurrentCalendarTimeZone() {
        var londonCalendar = Calendar(identifier: .gregorian)
        londonCalendar.timeZone = TimeZone(identifier: "Europe/London")!
        let sydneyEngine = CircadianTransitionEngine(calendar: calendar)
        let londonEngine = CircadianTransitionEngine(calendar: londonCalendar)
        let instant = ISO8601DateFormatter().date(from: "2026-08-09T12:30:00Z")!

        XCTAssertEqual(sydneyEngine.target(for: instant).phase, .deepNight)
        XCTAssertEqual(londonEngine.target(for: instant).phase, .daylight)
    }

    func testTargetRemainsDeepNightAcrossDaylightSavingBoundary() {
        let engine = CircadianTransitionEngine(calendar: calendar)

        let target = engine.target(for: date(year: 2026, month: 10, day: 4, hour: 3, minute: 30))

        XCTAssertEqual(target.phase, .deepNight)
        XCTAssertEqual(target.kelvin, CircadianCurveConfiguration.default.deepNightKelvin)
    }

    func testWorkspacePolicyLeavesAPausedOrDisabledNightShiftAlone() {
        let policy = WorkspacePolicy()
        let off = WorkspaceOutputState(isNightShiftEnabled: false, colorTemperature: 0.72)

        XCTAssertEqual(
            policy.decision(isCircadianEnabled: true, targetStrength: 0.9, activityOverride: .none, currentOutput: off),
            .noChange)
        XCTAssertEqual(
            policy.decision(
                isCircadianEnabled: false,
                targetStrength: 0.9,
                activityOverride: .none,
                currentOutput: WorkspaceOutputState(isNightShiftEnabled: true, colorTemperature: 0.72)),
            .noChange)
    }

    func testForegroundMediaHoldsTheCurrentStrength() {
        let policy = WorkspacePolicy()
        let currentOutput = WorkspaceOutputState(isNightShiftEnabled: true, colorTemperature: 0.4)

        XCTAssertEqual(
            policy.decision(
                isCircadianEnabled: true,
                targetStrength: 0.8,
                activityOverride: ActivityOverrideSnapshot(
                    isSuspended: true,
                    reason: .foregroundMedia,
                    until: nil
                ),
                currentOutput: currentOutput
            ),
            .noChange
        )
        XCTAssertEqual(
            policy.decision(
                isCircadianEnabled: true,
                targetStrength: 0.8,
                activityOverride: .none,
                currentOutput: currentOutput
            ),
            .applyStrength(0.8)
        )
    }

    func testNextTransitionFromDaylightIsTheEveningRamp() {
        let engine = CircadianTransitionEngine(calendar: calendar)

        let next = engine.nextTransition(after: date(year: 2026, month: 8, day: 9, hour: 12))

        XCTAssertEqual(next, CircadianTransition(phase: .evening, date: date(year: 2026, month: 8, day: 9, hour: 21)))
    }

    func testNextTransitionFromEveningIsDeepNight() {
        let engine = CircadianTransitionEngine(calendar: calendar)

        let next = engine.nextTransition(after: date(year: 2026, month: 8, day: 9, hour: 21, minute: 30))

        XCTAssertEqual(next, CircadianTransition(phase: .deepNight, date: date(year: 2026, month: 8, day: 9, hour: 22, minute: 15)))
    }

    func testNextTransitionFromDeepNightIsTheFollowingWakeTime() {
        let engine = CircadianTransitionEngine(calendar: calendar)

        let beforeMidnight = engine.nextTransition(after: date(year: 2026, month: 8, day: 9, hour: 23, minute: 30))
        let afterMidnight = engine.nextTransition(after: date(year: 2026, month: 8, day: 10, hour: 2))

        let wake = CircadianTransition(phase: .daylight, date: date(year: 2026, month: 8, day: 10, hour: 7))
        XCTAssertEqual(beforeMidnight, wake)
        XCTAssertEqual(afterMidnight, wake)
    }

    func testNextTransitionSkipsEveningWhenThereIsNoEveningRamp() {
        var configuration = CircadianCurveConfiguration.default
        configuration.eveningLeadTime = configuration.deepNightLeadTime
        let engine = CircadianTransitionEngine(configuration: configuration, calendar: calendar)

        let next = engine.nextTransition(after: date(year: 2026, month: 8, day: 9, hour: 12))

        XCTAssertEqual(next, CircadianTransition(phase: .deepNight, date: date(year: 2026, month: 8, day: 9, hour: 22, minute: 15)))
    }

    func testValidationBoundsKelvinAndKeepsTheEveningWarmingOrder() {
        var configuration = CircadianCurveConfiguration.default
        configuration.daylightKelvin = 9000
        configuration.eveningKelvin = 6600
        configuration.deepNightKelvin = 1200

        let validated = configuration.validated()

        XCTAssertEqual(validated.daylightKelvin, 6500)
        XCTAssertEqual(validated.eveningKelvin, 6500)
        XCTAssertEqual(validated.deepNightKelvin, 2700)
    }

    func testValidationFitsLeadTimesInsideTheWakingDay() {
        var configuration = CircadianCurveConfiguration.default
        configuration.wakeTime = DateComponents(hour: 20, minute: 0)
        configuration.bedtime = DateComponents(hour: 21, minute: 0)
        configuration.eveningLeadTime = 4 * 3600
        configuration.deepNightLeadTime = 5 * 3600

        let validated = configuration.validated()

        XCTAssertEqual(validated.eveningLeadTime, 3600)
        XCTAssertEqual(validated.deepNightLeadTime, 3600)
    }

    func testValidationFallsBackToDefaultsWhenBedtimeEqualsWakeTime() {
        var configuration = CircadianCurveConfiguration.default
        configuration.bedtime = DateComponents(hour: 7, minute: 0)

        XCTAssertEqual(configuration.validated(), .default)
    }

    func testConfigurationStoreRoundTripsAndDefaultsWhenEmptyOrUnreadable() throws {
        let suiteName = "CircadianWorkspaceTests.configurationStore"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsCircadianConfigurationStore(defaults: defaults)

        XCTAssertEqual(store.configuration, .default)

        var configuration = CircadianCurveConfiguration.default
        configuration.bedtime = DateComponents(hour: 22, minute: 45)
        configuration.wakeTime = DateComponents(hour: 6, minute: 30)
        configuration.eveningKelvin = 4000
        configuration.eveningLeadTime = 90 * 60
        store.configuration = configuration
        XCTAssertEqual(store.configuration, configuration)

        defaults.set(Data("not json".utf8), forKey: Keys.circadianConfiguration)
        XCTAssertEqual(store.configuration, .default)
    }

    @MainActor
    func testIdleCLIPayloadIsAValidPropertyListAndOmitsSuspendReason() {
        let payload = CircadianWorkspaceCoordinator.shared.currentCLIStatePayload()

        XCTAssertTrue(PropertyListSerialization.propertyList(payload, isValidFor: .binary))
        XCTAssertNil(payload["suspendReason"])
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
