import AppKit
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

    @MainActor
    func testWebsiteRuleAppearsLiveAndRemovalPersistsAcrossRelaunch() {
        continueAfterFailure = false
        let domain = "colour-critical-review-and-display-calibration-workspace.test"
        let app = XCUIApplication()
        app.launchEnvironment["SHIFTY_PREFERENCES_TEST_PROFILE"] = UUID().uuidString
        app.launchEnvironment["SHIFTY_PREFERENCES_TEST_PANE"] = "rules"
        app.launchEnvironment["SHIFTY_PREFERENCES_TEST_DOMAIN"] = domain
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_AU", "-AppleInterfaceStyle", "Light"]

        let window = app.windows.firstMatch
        let emptyState = window.staticTexts["No Rules"]
        let domainLabel = window.staticTexts[domain]
        let ruleType = window.staticTexts["Domain disabled"]
        let removeButton = window.buttons["Remove Rule"]
        defer {
            app.terminate()
            app.launchEnvironment["SHIFTY_PREFERENCES_TEST_DOMAIN"] = nil
            app.launchEnvironment["SHIFTY_RESET_TEST_PROFILE"] = "1"
            app.launch()
            XCTAssertTrue(emptyState.waitForExistence(timeout: 8))
            app.terminate()
        }

        app.launch()
        XCTAssertTrue(emptyState.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertFalse(domainLabel.exists)

        app.typeKey("d", modifierFlags: [.command, .shift])
        XCTAssertTrue(domainLabel.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(ruleType.exists)
        XCTAssertTrue(removeButton.isHittable)
        XCTAssertEqual(removeButton.value as? String, domain)
        XCTAssertFalse(emptyState.exists)

        let screenshot = XCTAttachment(screenshot: window.screenshot())
        screenshot.name = "Rules preferences with a long website domain"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        removeButton.click()
        XCTAssertTrue(emptyState.waitForExistence(timeout: 8))
        XCTAssertFalse(domainLabel.exists)
        XCTAssertFalse(removeButton.exists)

        app.terminate()
        app.launchEnvironment["SHIFTY_PREFERENCES_TEST_DOMAIN"] = nil
        app.launch()
        XCTAssertTrue(emptyState.waitForExistence(timeout: 8))
        XCTAssertFalse(domainLabel.exists)
        XCTAssertFalse(removeButton.exists)
    }

    @MainActor
    func testLiveChromeTabsApplyAndClearWebsiteRule() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SHIFTY_LIVE_CHROME_TEST"] == "1",
                          "Set TEST_RUNNER_SHIFTY_LIVE_CHROME_TEST=1 to run the live Chrome check")
        let app = XCUIApplication()
        try XCTSkipUnless(app.state == .notRunning, "Quit any running Shifty instance before this check")
        let chromeURL = try XCTUnwrap(NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome"),
                                     "Install Google Chrome to run the live browser check")
        continueAfterFailure = false
        let chrome = XCUIApplication(url: chromeURL)
        chrome.activate()
        let windowCount = chrome.windows.count
        chrome.typeKey("n", modifierFlags: [.command, .shift])
        let newWindow = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            chrome.windows.count > windowCount
        }, object: chrome)
        XCTAssertEqual(XCTWaiter.wait(for: [newWindow], timeout: 8), .completed,
                       "Chrome did not open a new Incognito window")
        let incognitoWindow = chrome.windows.containing(.button, identifier: "Incognito").firstMatch
        XCTAssertTrue(incognitoWindow.exists, "Chrome's test window must be Incognito")
        addTeardownBlock { @MainActor in
            if incognitoWindow.exists {
                incognitoWindow.typeKey("w", modifierFlags: [.command, .shift])
            }
        }

        func openDomain(_ domain: String) {
            incognitoWindow.typeKey("l", modifierFlags: .command)
            chrome.typeText("https://\(domain)/")
            chrome.typeKey(.return, modifierFlags: [])
        }

        func assertSelectedDomain(_ domain: String, line: UInt = #line) {
            let address = incognitoWindow.textFields
                .matching(NSPredicate(format: "value CONTAINS %@", domain)).firstMatch
            XCTAssertTrue(address.waitForExistence(timeout: 8),
                          "Chrome did not select the \(domain) tab", line: line)
        }

        openDomain("example.com")
        incognitoWindow.typeKey("t", modifierFlags: .command)
        openDomain("example.org")
        incognitoWindow.typeKey("1", modifierFlags: .command)
        assertSelectedDomain("example.com")
        let frontmostApp = try XCTUnwrap(NSWorkspace.shared.menuBarOwningApplication)
        XCTAssertEqual(frontmostApp.bundleIdentifier, "com.google.Chrome")

        app.launchEnvironment["SHIFTY_PREFERENCES_TEST_PROFILE"] = UUID().uuidString
        app.launchEnvironment["SHIFTY_PREFERENCES_TEST_PANE"] = "live-chrome-rules"
        app.launchEnvironment["SHIFTY_LIVE_CHROME_PID"] = String(frontmostApp.processIdentifier)
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_AU"]
        addTeardownBlock { @MainActor in
            app.terminate()
            app.launchEnvironment["SHIFTY_RESET_TEST_PROFILE"] = "1"
            app.launchEnvironment["SHIFTY_PREFERENCES_TEST_PANE"] = "rules"
            app.launch()
            _ = app.staticTexts["No Rules"].waitForExistence(timeout: 8)
            app.terminate()
        }
        app.launch()

        let window = app.windows.firstMatch
        let status = window.staticTexts["liveChrome.status"]
        func assertStatus(_ expected: String, line: UInt = #line) {
            let result = NSPredicate(format: "value == %@ OR value ENDSWITH %@ OR value == %@", expected,
                                     "permission required for this Shifty build", "The Chrome test process is unavailable")
            let ready = XCTNSPredicateExpectation(predicate: result, object: status)
            _ = XCTWaiter.wait(for: [ready], timeout: 10)
            XCTAssertEqual(status.exists ? status.value as? String : nil, expected, line: line)
        }

        assertStatus("example.com · simulated Night Shift on")
        let empty = window.staticTexts["No Rules"]
        XCTAssertTrue(empty.exists)
        window.buttons["liveChrome.toggleDomainRule"].click()
        let domain = window.staticTexts["example.com"]
        XCTAssertTrue(domain.waitForExistence(timeout: 8))
        XCTAssertTrue(window.staticTexts["Domain disabled"].exists)
        assertStatus("example.com · simulated Night Shift off")

        chrome.activate()
        incognitoWindow.typeKey("2", modifierFlags: .command)
        assertSelectedDomain("example.org")
        assertStatus("example.org · simulated Night Shift on")
        incognitoWindow.typeKey("1", modifierFlags: .command)
        assertSelectedDomain("example.com")
        assertStatus("example.com · simulated Night Shift off")
        XCTAssertTrue(domain.exists)

        app.activate()
        window.buttons["Remove Rule"].click()
        XCTAssertTrue(empty.waitForExistence(timeout: 8))
        XCTAssertFalse(domain.exists)
        assertStatus("example.com · simulated Night Shift on")
    }
}
