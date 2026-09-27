import XCTest
@testable import Shifty

/// Drives the real CoreBrightness Night Shift client and reads its state back, to
/// confirm the private API still behaves on the installed macOS. It changes the
/// display while it runs and restores the previous state afterwards.
///
/// Skipped unless enabled explicitly, because it needs a real display and would
/// disturb whoever is using the Mac:
///
///     TEST_RUNNER_SHIFTY_HARDWARE_TESTS=1 xcodebuild test -project Shifty.xcodeproj \
///         -scheme Shifty -destination 'platform=macOS' \
///         -only-testing:ShiftyTests/HardwareNightShiftTests | xcbeautify
final class HardwareNightShiftTests: XCTestCase {
    private let client = CoreBrightnessNightShiftClient.shared
    private var savedEnabled = false
    private var savedStrength: Float = 0
    private var savedSchedule: ScheduleType = .off

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SHIFTY_HARDWARE_TESTS"] == "1",
            "Set TEST_RUNNER_SHIFTY_HARDWARE_TESTS=1 to run the real CoreBrightness checks")
        try XCTSkipUnless(client.supportsNightShift, "This Mac doesn't support Night Shift")

        savedEnabled = client.isNightShiftEnabled
        savedStrength = client.colorTemperature
        savedSchedule = client.schedule
    }

    override func tearDown() {
        if ProcessInfo.processInfo.environment["SHIFTY_HARDWARE_TESTS"] == "1", client.supportsNightShift {
            client.schedule = savedSchedule
            client.colorTemperature = savedStrength
            client.setNightShiftEnabled(savedEnabled)
            settle()
        }
        super.tearDown()
    }

    func testEnablingAndDisablingIsReflectedInStatus() {
        client.setNightShiftEnabled(true)
        settle()
        XCTAssertTrue(client.isNightShiftEnabled)

        client.setNightShiftEnabled(false)
        settle()
        XCTAssertFalse(client.isNightShiftEnabled)
    }

    func testCommittedStrengthReadsBack() {
        client.setNightShiftEnabled(true)
        settle()

        for strength: Float in [0.25, 0.75] {
            client.colorTemperature = strength
            settle()
            XCTAssertEqual(client.colorTemperature, strength, accuracy: 0.02)
        }
    }

    /// Shortcuts and the "warmer" shortcut enable Night Shift and set a strength in one step.
    func testStrengthSetImmediatelyAfterEnablingIsKept() {
        client.setNightShiftEnabled(false)
        settle()

        client.setNightShiftEnabled(true)
        client.colorTemperature = 0.75
        settle(seconds: 3)

        XCTAssertEqual(client.colorTemperature, 0.75, accuracy: 0.02)
    }

    func testPreviewDoesNotReplaceTheCommittedStrength() {
        client.setNightShiftEnabled(true)
        client.colorTemperature = 0.3
        settle()

        client.previewColorTemperature(0.9)
        settle()
        client.colorTemperature = 0.3
        settle()

        XCTAssertEqual(client.colorTemperature, 0.3, accuracy: 0.02)
    }

    func testCustomScheduleRoundTrips() {
        let custom = ScheduleType.custom(start: Time(hour: 21, minute: 30), end: Time(hour: 6, minute: 45))

        client.schedule = custom
        settle()

        XCTAssertEqual(client.schedule, custom)
    }

    func testHandingBackToTheScheduleMatchesTheScheduledState() {
        client.setNightShiftEnabled(!client.scheduledState)
        settle()

        client.setToSchedule()
        settle()

        XCTAssertEqual(client.isNightShiftEnabled, client.scheduledState)
    }

    /// CoreBrightness applies changes asynchronously; give it a moment before reading back.
    private func settle(seconds: TimeInterval = 0.3) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }
}
