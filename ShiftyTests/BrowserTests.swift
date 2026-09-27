import DomainParser
import XCTest
@testable import Shifty

final class WebsiteContextTests: XCTestCase {
    private static let parser = try? DomainParser()

    private func context(_ string: String?) throws -> WebsiteContext {
        let parser = try XCTUnwrap(Self.parser, "The bundled public suffix list must load")
        return WebsiteContext(url: string.flatMap(URL.init(string:))) { parser.parse(host: $0)?.domain }
    }

    func testDomainUsesThePublicSuffixList() throws {
        XCTAssertEqual(try context("https://docs.example.co.uk/page").domain, "example.co.uk")
        XCTAssertEqual(try context("https://docs.example.co.uk/page").subdomain, "docs.example.co.uk")
        XCTAssertEqual(try context("https://mail.google.com").domain, "google.com")
    }

    func testBareAndWwwHostsAreNotSeparateSubdomains() throws {
        XCTAssertFalse(try context("https://example.com").hasValidSubdomain)
        XCTAssertFalse(try context("https://www.example.com").hasValidSubdomain)
        XCTAssertTrue(try context("https://docs.example.com").hasValidSubdomain)
        XCTAssertTrue(try context("https://www.docs.example.com").hasValidSubdomain)
    }

    func testNoURLHasNoWebsite() throws {
        let website = try context(nil)
        XCTAssertNil(website.domain)
        XCTAssertFalse(website.hasValidDomain)
        XCTAssertFalse(website.hasValidSubdomain)
    }

    func testNonWebURLsHaveNoDomain() throws {
        XCTAssertFalse(try context("file:///Users/example/index.html").hasValidDomain)
        XCTAssertFalse(try context("about:blank").hasValidDomain)
    }

    func testHostWithoutARegistrableDomainIsStillASubdomain() throws {
        let website = try context("http://localhost:8000")
        XCTAssertNil(website.domain)
        XCTAssertEqual(website.subdomain, "localhost")
        XCTAssertTrue(website.hasValidSubdomain)
    }

    func testRuleEventPrecedence() {
        XCTAssertEqual(WebsiteContext.ruleEvent(subdomainRule: .enabled, isDomainDisabled: true), .nightShiftEnableRuleActivated)
        XCTAssertEqual(WebsiteContext.ruleEvent(subdomainRule: .disabled, isDomainDisabled: false), .nightShiftDisableRuleActivated)
        XCTAssertEqual(WebsiteContext.ruleEvent(subdomainRule: .none, isDomainDisabled: true), .nightShiftDisableRuleActivated)
        XCTAssertEqual(WebsiteContext.ruleEvent(subdomainRule: .none, isDomainDisabled: false), .nightShiftDisableRuleDeactivated)
    }

    func testSupportedBrowsersMatchByBundleIdentifier() {
        XCTAssertEqual(SupportedBrowserID("com.apple.Safari"), .safari)
        XCTAssertEqual(SupportedBrowserID("com.brave.Browser"), .brave)
        XCTAssertEqual(SupportedBrowserID("com.vivaldi.Vivaldi"), .vivaldi)
        XCTAssertNil(SupportedBrowserID("org.mozilla.firefox"))
        XCTAssertNil(SupportedBrowserID("com.apple.safari"), "Bundle identifiers are case-sensitive")
    }
}
