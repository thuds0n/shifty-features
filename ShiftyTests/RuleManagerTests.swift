import XCTest
@testable import Shifty

final class RuleManagerTests: XCTestCase {
    private var events: [NightShiftEvent] = []
    private var defaults: UserDefaults { UserDefaults.standard }

    override func setUp() {
        super.setUp()
        events = []
        defaults.removeObject(forKey: Keys.currentAppDisableRules)
        defaults.removeObject(forKey: Keys.runningAppDisableRules)
        defaults.removeObject(forKey: Keys.browserRules)
        defaults.set(false, forKey: Keys.isWebsiteControlEnabled)
    }

    func testSetSubdomainRuleDisabledAddsRuleAndEmitsDisableActivated() {
        let manager = makeManager()

        manager.setSubdomainRule(.disabled, forSubdomain: "example.com")

        XCTAssertTrue(manager.browserRules.contains(BrowserRule(type: .subdomainDisabled, host: "example.com")))
        XCTAssertEqual(events, [.nightShiftDisableRuleActivated])
    }

    func testSetSubdomainRuleNoneRemovesDisabledRuleAndEmitsDisableDeactivated() {
        let manager = makeManager()
        manager.setSubdomainRule(.disabled, forSubdomain: "example.com")
        events.removeAll()

        manager.setSubdomainRule(.none, forSubdomain: "example.com")

        XCTAssertFalse(manager.browserRules.contains(BrowserRule(type: .subdomainDisabled, host: "example.com")))
        XCTAssertEqual(events, [.nightShiftDisableRuleDeactivated])
    }

    func testAddAndRemoveDomainDisableRuleUpdatesRulesAndEmitsEvents() {
        let manager = makeManager()

        manager.addDomainDisableRule(forDomain: "example.com")
        manager.removeDomainDisableRule(forDomain: "example.com")

        XCTAssertFalse(manager.browserRules.contains(BrowserRule(type: .domain, host: "example.com")))
        XCTAssertEqual(events, [.nightShiftDisableRuleActivated, .nightShiftDisableRuleDeactivated])
    }

    func testRemoveBrowserRuleEmitsTheMatchingDeactivationEvent() {
        let manager = makeManager()
        manager.addDomainDisableRule(forDomain: "example.com")
        manager.browserRules.insert(BrowserRule(type: .subdomainEnabled, host: "docs.example.com"))
        events.removeAll()

        manager.removeBrowserRule(BrowserRule(type: .subdomainEnabled, host: "docs.example.com"))
        manager.removeBrowserRule(BrowserRule(type: .domain, host: "example.com"))
        manager.removeBrowserRule(BrowserRule(type: .domain, host: "missing.example"))

        XCTAssertTrue(manager.browserRules.isEmpty)
        XCTAssertEqual(events, [.nightShiftEnableRuleDeactivated, .nightShiftDisableRuleDeactivated])
    }

    func testRemovingStoredAppRulesEmitsDeactivationOnlyWhenARuleWasRemoved() throws {
        let rule = AppRule(bundleIdentifier: "com.example.app", fullScreenOnly: false)
        defaults.set(try PropertyListEncoder().encode(Set([rule])), forKey: Keys.currentAppDisableRules)
        defaults.set(try PropertyListEncoder().encode(Set([rule])), forKey: Keys.runningAppDisableRules)
        let manager = makeManager()

        manager.removeCurrentAppDisableRule(rule)
        manager.removeRunningAppDisableRule(rule)
        manager.removeRunningAppDisableRule(rule)

        XCTAssertTrue(manager.currentAppDisableRuleSnapshot.isEmpty)
        XCTAssertTrue(manager.runningAppDisableRuleSnapshot.isEmpty)
        XCTAssertEqual(events, [.nightShiftDisableRuleDeactivated, .nightShiftDisableRuleDeactivated])
    }

    func testChangingRulesPostsRulesDidChange() {
        let manager = makeManager()
        let posted = expectation(forNotification: RuleManager.rulesDidChangeNotification, object: manager)

        manager.addDomainDisableRule(forDomain: "example.com")

        wait(for: [posted], timeout: 1)
    }

    private func makeManager() -> RuleManager {
        RuleManager { [weak self] event in
            self?.events.append(event)
        }
    }
}
