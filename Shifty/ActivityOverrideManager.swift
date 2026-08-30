import Cocoa

enum ActivitySuspendReason: String {
    case foregroundMedia
    case pictureInPicture
    case temporaryPause
}

struct ActivityOverrideSnapshot: Equatable {
    var isSuspended: Bool
    var reason: ActivitySuspendReason?
    var until: Date?

    static let none = ActivityOverrideSnapshot(isSuspended: false, reason: nil, until: nil)
}

protocol ActivityOverrideManaging: AnyObject {
    var currentOverride: ActivityOverrideSnapshot { get }
    var onChange: ((ActivityOverrideSnapshot) -> Void)? { get set }
    func start()
    func stop()
    func setTemporaryPause(minutes: Int)
    func clearTemporaryPause()
}

final class ActivityOverrideManager: ActivityOverrideManaging {
    var onChange: ((ActivityOverrideSnapshot) -> Void)?

    private(set) var currentOverride: ActivityOverrideSnapshot = .none {
        didSet { onChange?(currentOverride) }
    }

    private var temporaryPauseTimer: Timer?
    private var observers = [NSObjectProtocol]()

    private let mediaBundleIdentifiers: Set<String> = [
        "org.videolan.vlc",
        "com.colliderli.iina",
        "com.apple.QuickTimePlayerX"
    ]

    func start() {
        guard observers.isEmpty else { return }
        let centre = NSWorkspace.shared.notificationCenter
        observers.append(centre.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.evaluateMediaContext()
        })
        observers.append(centre.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.evaluateMediaContext()
        })
        evaluateMediaContext()
    }

    func stop() {
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        temporaryPauseTimer?.invalidate()
        temporaryPauseTimer = nil
        currentOverride = .none
    }

    func setTemporaryPause(minutes: Int) {
        let clampedMinutes = min(max(minutes, 1), 30)
        temporaryPauseTimer?.invalidate()
        let endDate = Date().addingTimeInterval(TimeInterval(clampedMinutes * 60))
        currentOverride = ActivityOverrideSnapshot(isSuspended: true, reason: .temporaryPause, until: endDate)
        temporaryPauseTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(clampedMinutes * 60),
            repeats: false
        ) { [weak self] _ in
            self?.temporaryPauseTimer = nil
            self?.evaluateMediaContext()
        }
    }

    func clearTemporaryPause() {
        temporaryPauseTimer?.invalidate()
        temporaryPauseTimer = nil
        evaluateMediaContext()
    }

    private func evaluateMediaContext() {
        if temporaryPauseTimer != nil, let until = currentOverride.until {
            currentOverride = ActivityOverrideSnapshot(isSuspended: true, reason: .temporaryPause, until: until)
            return
        }

        guard
            let activeApp = NSWorkspace.shared.frontmostApplication,
            let bundleID = activeApp.bundleIdentifier,
            mediaBundleIdentifiers.contains(bundleID)
        else {
            currentOverride = .none
            return
        }

        currentOverride = ActivityOverrideSnapshot(isSuspended: true, reason: .foregroundMedia, until: nil)
    }
}
