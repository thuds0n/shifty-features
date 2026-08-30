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

    func testWorkspacePolicyNeutralisesAndRestoresExactOutput() {
        let policy = WorkspacePolicy()
        let originalOutput = WorkspaceOutputState(isNightShiftEnabled: true, colorTemperature: 0.72)
        let temporaryPause = ActivityOverrideSnapshot(
            isSuspended: true,
            reason: .temporaryPause,
            until: date(year: 2026, month: 8, day: 9, hour: 22)
        )

        XCTAssertEqual(
            policy.decision(
                isCircadianEnabled: true,
                targetStrength: 0.9,
                activityOverride: temporaryPause,
                currentOutput: originalOutput
            ),
            .neutralise
        )
        XCTAssertEqual(
            policy.decision(
                isCircadianEnabled: true,
                targetStrength: 0.9,
                activityOverride: temporaryPause,
                currentOutput: WorkspaceOutputState(isNightShiftEnabled: false, colorTemperature: 0.72)
            ),
            .noChange
        )
        XCTAssertEqual(
            policy.decision(
                isCircadianEnabled: true,
                targetStrength: 0.9,
                activityOverride: .none,
                currentOutput: WorkspaceOutputState(isNightShiftEnabled: false, colorTemperature: 0.72)
            ),
            .restore(originalOutput)
        )
    }

    func testDisablingCircadianModeRestoresAnActivePause() {
        let policy = WorkspacePolicy()
        let originalOutput = WorkspaceOutputState(isNightShiftEnabled: true, colorTemperature: 0.55)

        _ = policy.decision(
            isCircadianEnabled: true,
            targetStrength: 0.8,
            activityOverride: ActivityOverrideSnapshot(
                isSuspended: true,
                reason: .temporaryPause,
                until: nil
            ),
            currentOutput: originalOutput
        )

        XCTAssertEqual(
            policy.decision(
                isCircadianEnabled: false,
                targetStrength: 0.8,
                activityOverride: .none,
                currentOutput: WorkspaceOutputState(isNightShiftEnabled: false, colorTemperature: 0.55)
            ),
            .restore(originalOutput)
        )
    }

    func testForegroundMediaHoldsOutputWithoutClaimingATemporaryPause() {
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
