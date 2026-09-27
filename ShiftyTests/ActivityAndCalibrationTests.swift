import AppKit
import XCTest
@testable import Shifty

final class ActivityOverrideManagerTests: XCTestCase {
    private var centre: NotificationCenter!
    private var frontmost: String?
    private var manager: ActivityOverrideManager!
    private var changes: [ActivityOverrideSnapshot] = []

    override func setUp() {
        super.setUp()
        centre = NotificationCenter()
        frontmost = nil
        changes = []
        manager = ActivityOverrideManager(notificationCenter: centre) { [unowned self] in self.frontmost }
        manager.onChange = { [unowned self] in self.changes.append($0) }
    }

    override func tearDown() {
        manager.stop()
        manager = nil
        centre = nil
        super.tearDown()
    }

    private let mediaSuspension = ActivityOverrideSnapshot(isSuspended: true, reason: .foregroundMedia, until: nil)

    func testStartEvaluatesTheCurrentFrontmostApp() {
        frontmost = "org.videolan.vlc"

        manager.start()

        XCTAssertEqual(manager.currentOverride, mediaSuspension)
    }

    func testActivatingAMediaAppSuspendsAndLeavingItClears() {
        manager.start()
        XCTAssertEqual(manager.currentOverride, .none)

        frontmost = "com.colliderli.iina"
        centre.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        XCTAssertEqual(manager.currentOverride, mediaSuspension)

        frontmost = "com.apple.Safari"
        centre.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        XCTAssertEqual(manager.currentOverride, .none)
        XCTAssertEqual(changes, [.none, mediaSuspension, .none])
    }

    func testSpaceChangesAreReevaluated() {
        manager.start()

        frontmost = "com.apple.QuickTimePlayerX"
        centre.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        XCTAssertEqual(manager.currentOverride, mediaSuspension)
    }

    func testNoFrontmostAppIsNotASuspension() {
        frontmost = nil

        manager.start()

        XCTAssertEqual(manager.currentOverride, .none)
    }

    func testStartIsIdempotent() {
        manager.start()
        manager.start()
        changes.removeAll()

        frontmost = "org.videolan.vlc"
        centre.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)

        XCTAssertEqual(changes.count, 1, "A second start must not register duplicate observers")
    }

    func testStopClearsTheOverrideAndIgnoresLaterNotifications() {
        frontmost = "org.videolan.vlc"
        manager.start()

        manager.stop()
        XCTAssertEqual(manager.currentOverride, .none)

        centre.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        XCTAssertEqual(manager.currentOverride, .none)
    }
}

final class DisplayCalibrationStoreTests: XCTestCase {
    private static let suiteName = "DisplayCalibrationStoreTests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: Self.suiteName)
        defaults.removePersistentDomain(forName: Self.suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: Self.suiteName)
        defaults = nil
        super.tearDown()
    }

    func testDefaultsAreEmpty() {
        let store = UserDefaultsDisplayCalibrationStore(defaults: defaults)

        XCTAssertTrue(store.selectiveShiftDisplayIDs.isEmpty)
        XCTAssertEqual(store.warmthOffset(for: "display-1"), 0)
    }

    func testWarmthOffsetsArePerDisplayAndPersist() {
        let store = UserDefaultsDisplayCalibrationStore(defaults: defaults)

        store.setWarmthOffset(-200, for: "display-1")
        store.setWarmthOffset(150, for: "display-2")
        store.setWarmthOffset(-100, for: "display-1")

        let reloaded = UserDefaultsDisplayCalibrationStore(defaults: defaults)
        XCTAssertEqual(reloaded.warmthOffset(for: "display-1"), -100)
        XCTAssertEqual(reloaded.warmthOffset(for: "display-2"), 150)
        XCTAssertEqual(reloaded.warmthOffset(for: "display-3"), 0)
    }

    func testSelectiveShiftDisplaysPersistAsASet() {
        let store = UserDefaultsDisplayCalibrationStore(defaults: defaults)

        store.selectiveShiftDisplayIDs = ["display-1", "display-2"]

        XCTAssertEqual(UserDefaultsDisplayCalibrationStore(defaults: defaults).selectiveShiftDisplayIDs, ["display-1", "display-2"])
        store.selectiveShiftDisplayIDs = []
        XCTAssertTrue(store.selectiveShiftDisplayIDs.isEmpty)
    }

    func testUnreadableStoredValuesFallBackToDefaults() {
        defaults.set("not a dictionary", forKey: "displayWarmthOffsets")
        defaults.set(42, forKey: "selectiveShiftDisplayIDs")
        let store = UserDefaultsDisplayCalibrationStore(defaults: defaults)

        XCTAssertEqual(store.warmthOffset(for: "display-1"), 0)
        XCTAssertTrue(store.selectiveShiftDisplayIDs.isEmpty)

        store.setWarmthOffset(50, for: "display-1")
        XCTAssertEqual(store.warmthOffset(for: "display-1"), 50, "Writing replaces the unreadable value")
    }
}
