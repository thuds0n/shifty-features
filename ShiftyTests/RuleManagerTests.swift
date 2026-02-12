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

    private func makeManager() -> RuleManager {
        RuleManager { [weak self] event in
            self?.events.append(event)
        }
    }
}
