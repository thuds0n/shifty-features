import XCTest

final class PreferencesTests: XCTestCase {
    @MainActor
    func testBedtimePersistsAcrossRelaunch() throws {
        continueAfterFailure = false
        let profile = UUID().uuidString
        let app = XCUIApplication()
        app.launchEnvironment["SHIFTY_PREFERENCES_TEST_PROFILE"] = profile
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_AU", "-AppleInterfaceStyle", "Light"]
        defer {
            app.terminate()
            // The app owns the suite and can clear it even when the runner is sandboxed.
            app.launchEnvironment["SHIFTY_RESET_TEST_PROFILE"] = "1"
            app.launch()
            XCTAssertTrue(app.datePickers["circadian.bedtime"].waitForExistence(timeout: 8))
            app.terminate()
        }

        app.launch()
        let bedtime = app.datePickers["circadian.bedtime"]
        XCTAssertTrue(bedtime.waitForExistence(timeout: 8), app.debugDescription)
        let original = try XCTUnwrap(bedtime.value as? String)
        bedtime.click()
        bedtime.typeKey(.upArrow, modifierFlags: [])
        bedtime.typeKey(.tab, modifierFlags: [])
        let edited = try XCTUnwrap(bedtime.value as? String)
        XCTAssertNotEqual(edited, original)

        app.terminate()
        app.launch()
        XCTAssertTrue(bedtime.waitForExistence(timeout: 8))
        XCTAssertEqual(bedtime.value as? String, edited)
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "Circadian preferences after relaunch"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testGermanShortcutCanBeRecordedAndClearedAcrossRelaunches() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["SHIFTY_PREFERENCES_TEST_PROFILE"] = UUID().uuidString
        app.launchEnvironment["SHIFTY_PREFERENCES_TEST_PANE"] = "shortcuts"
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE",
                               "-AppleInterfaceStyle", "Light", "-AppleKeyboardUIMode", "3"]
        let recorder = app.buttons["Night Shift umschalten"]
        defer {
            app.terminate()
            app.launchEnvironment["SHIFTY_RESET_TEST_PROFILE"] = "1"
            app.launch()
            XCTAssertTrue(recorder.waitForExistence(timeout: 8))
            app.terminate()
        }

        func beginRecordingWithKeyboard() {
            for _ in 0..<16 {
                app.typeKey(.space, modifierFlags: [])
                if recorder.value as? String == "Aufnahme läuft" { return }
                app.typeKey(.escape, modifierFlags: [])
                app.typeKey(.tab, modifierFlags: [])
            }
            XCTFail("Tab navigation did not reach the recorder. \(app.debugDescription)")
        }

        app.launch()
        XCTAssertTrue(recorder.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(recorder.value as? String, "Nicht festgelegt")
        beginRecordingWithKeyboard()
        XCTAssertEqual(recorder.value as? String, "Aufnahme läuft")
        app.typeKey("k", modifierFlags: [.control, .shift])
        XCTAssertEqual(recorder.value as? String, "⌃⇧K")
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "German Shortcuts with focused binding"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.terminate()
        app.launch()
        XCTAssertTrue(recorder.waitForExistence(timeout: 8))
        XCTAssertEqual(recorder.value as? String, "⌃⇧K")
        beginRecordingWithKeyboard()
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertEqual(recorder.value as? String, "Nicht festgelegt")

        app.terminate()
        app.launch()
        XCTAssertTrue(recorder.waitForExistence(timeout: 8))
        XCTAssertEqual(recorder.value as? String, "Nicht festgelegt")
    }

}
