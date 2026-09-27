import Carbon
import XCTest
@testable import Shifty

final class PreferenceAccessibilityTests: XCTestCase {
    private let preferenceKeys = [
        "prefs.rules",
        "prefs.general.section.application",
        "prefs.general.launch_at_login",
        "prefs.general.quick_toggle",
        "prefs.general.switch_icon",
        "prefs.general.section.display",
        "prefs.general.sync_dark_mode",
        "prefs.general.show_kelvin",
        "prefs.general.section.website_shifting",
        "prefs.general.enable_website_shifting",
        "prefs.general.website_shifting_footer",
        "prefs.general.section.true_tone",
        "prefs.general.disable_true_tone",
        "prefs.general.true_tone_footer",
        "prefs.general.section.night_shift_schedule",
        "prefs.general.schedule",
        "prefs.general.schedule.off",
        "prefs.general.schedule.solar",
        "prefs.general.schedule.custom",
        "prefs.general.schedule.from",
        "prefs.general.schedule.to",
        "prefs.rules.active_app",
        "prefs.rules.when_running",
        "prefs.rules.websites",
        "prefs.rules.domain_disabled",
        "prefs.rules.subdomain_disabled",
        "prefs.rules.subdomain_enabled",
        "prefs.rules.remove",
        "prefs.rules.active_app_footer",
        "prefs.rules.when_running_footer",
        "prefs.rules.websites_footer",
        "prefs.rules.empty_title",
        "prefs.rules.empty_message",
        "prefs.shortcuts.section.night_shift",
        "prefs.shortcuts.toggle_night_shift",
        "prefs.shortcuts.warmer",
        "prefs.shortcuts.cooler",
        "prefs.shortcuts.section.disable_rules",
        "prefs.shortcuts.disable_app",
        "prefs.shortcuts.disable_domain",
        "prefs.shortcuts.disable_subdomain",
        "prefs.shortcuts.disable_hour",
        "prefs.shortcuts.disable_custom",
        "prefs.shortcuts.section.true_tone",
        "prefs.shortcuts.toggle_true_tone",
        "prefs.shortcuts.section.dark_mode",
        "prefs.shortcuts.toggle_dark_mode",
        "prefs.shortcuts.recorder.record",
        "prefs.shortcuts.recorder.type_shortcut",
        "prefs.shortcuts.recorder.recording",
        "prefs.shortcuts.recorder.not_set",
        "prefs.shortcuts.recorder.clear",
        "prefs.shortcuts.recorder.help_format",
        "prefs.about.version_format",
        "prefs.about.check_updates",
        "prefs.about.visit_website",
        "prefs.about.send_feedback",
        "prefs.about.donate",
        "prefs.about.help_translate",
        "prefs.about.credits",
        "prefs.about.copyright",
        "prefs.circadian",
        "prefs.circadian.enable",
        "prefs.circadian.enable_footer",
        "prefs.circadian.section.schedule",
        "prefs.circadian.wake_time",
        "prefs.circadian.bedtime",
        "prefs.circadian.wind_down",
        "prefs.circadian.before_bedtime_format",
        "prefs.circadian.section.warmth",
        "prefs.circadian.night_warmth"
    ]

    private let circadianMenuKeys = [
        "menu.circadian.phase.daylight",
        "menu.circadian.phase.evening",
        "menu.circadian.phase.deep_night",
        "menu.circadian.paused",
        "menu.circadian.next_format"
    ]

    func testEverySupportedLocalisationContainsTheSwiftUIPreferenceKeys() throws {
        let appBundle = Bundle(for: AppDelegate.self)

        for localisation in ["en", "de", "fr", "ru", "zh-Hans"] {
            let resourcePath = try XCTUnwrap(
                appBundle.path(forResource: localisation, ofType: "lproj"),
                "Missing \(localisation) localisation bundle"
            )
            let localisedBundle = try XCTUnwrap(Bundle(path: resourcePath))

            for key in preferenceKeys + circadianMenuKeys {
                let value = localisedBundle.localizedString(forKey: key, value: nil, table: nil)
                XCTAssertNotEqual(value, key, "Missing \(key) in \(localisation)")
            }
        }
    }

    func testShortcutRecorderSupportsKeyboardRecordingAndClearing() throws {
        let defaultsKey = "PreferenceAccessibilityTests.shortcut"
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

        let recorder = MASShortcutView()
        recorder.accessibilityLabelText = "Toggle Night Shift"
        recorder.setAssociatedUserDefaultsKey(defaultsKey, with: MASDictionaryTransformer())

        XCTAssertTrue(recorder.acceptsFirstResponder)
        XCTAssertEqual(recorder.accessibilityRole(), .button)
        XCTAssertEqual(recorder.accessibilityLabel(), "Toggle Night Shift")

        recorder.keyDown(with: try keyEvent(keyCode: kVK_Space))
        XCTAssertEqual(
            recorder.accessibilityValue() as? String,
            NSLocalizedString("prefs.shortcuts.recorder.recording", comment: "")
        )

        recorder.keyDown(with: try keyEvent(keyCode: kVK_ANSI_A, modifiers: .command))
        XCTAssertEqual(recorder.shortcutValue?.displayString, "⌘A")
        XCTAssertNotNil(UserDefaults.standard.dictionary(forKey: defaultsKey))

        recorder.keyDown(with: try keyEvent(keyCode: kVK_ForwardDelete))
        XCTAssertNil(recorder.shortcutValue)
        XCTAssertNil(UserDefaults.standard.object(forKey: defaultsKey))
    }

    private func keyEvent(
        keyCode: Int,
        modifiers: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: UInt16(keyCode)
        ))
    }
}
