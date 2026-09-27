import XCTest
@testable import Shifty

final class RuleManagerTests: XCTestCase {
    private static let suiteName = "RuleManagerTests"

    private var events: [NightShiftEvent] = []
    private var defaults: UserDefaults!
    private var savedArgumentDomain: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        events = []
        defaults = UserDefaults(suiteName: Self.suiteName)
        defaults.removePersistentDomain(forName: Self.suiteName)

        // RuleManager consults BrowserManager.shared, which reads this flag from
        // UserDefaults.standard. Override it in the volatile argument domain so
        // the developer's persisted preference is never written.
        let standard = UserDefaults.standard
        savedArgumentDomain = standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var argumentDomain = savedArgumentDomain
        argumentDomain[Keys.isWebsiteControlEnabled] = false
        standard.setVolatileDomain(argumentDomain, forName: UserDefaults.argumentDomain)
    }

    override func tearDown() {
        UserDefaults.standard.setVolatileDomain(savedArgumentDomain, forName: UserDefaults.argumentDomain)
        defaults.removePersistentDomain(forName: Self.suiteName)
        defaults = nil
        super.tearDown()
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

    func testRulesPersistToInjectedDefaultsOnly() {
        let manager = makeManager()

        manager.addDomainDisableRule(forDomain: "example.com")

        XCTAssertNotNil(defaults.data(forKey: Keys.browserRules))
        XCTAssertTrue(makeManager().browserRules.contains(BrowserRule(type: .domain, host: "example.com")))
    }

    private func makeManager() -> RuleManager {
        RuleManager(defaults: defaults) { [weak self] event in
            self?.events.append(event)
        }
    }
}
