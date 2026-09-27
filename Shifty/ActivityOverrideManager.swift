import Cocoa

enum ActivitySuspendReason: String {
    case foregroundMedia
    case pictureInPicture
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
}

final class ActivityOverrideManager: ActivityOverrideManaging {
    var onChange: ((ActivityOverrideSnapshot) -> Void)?

    private(set) var currentOverride: ActivityOverrideSnapshot = .none {
        didSet { onChange?(currentOverride) }
    }

    private var observers = [NSObjectProtocol]()
    private let notificationCenter: NotificationCenter
    private let frontmostBundleIdentifier: () -> String?

    init(
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        frontmostBundleIdentifier: @escaping () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    ) {
        self.notificationCenter = notificationCenter
        self.frontmostBundleIdentifier = frontmostBundleIdentifier
    }

    private let mediaBundleIdentifiers: Set<String> = [
        "org.videolan.vlc",
        "com.colliderli.iina",
        "com.apple.QuickTimePlayerX"
    ]

    func start() {
        guard observers.isEmpty else { return }
        let centre = notificationCenter
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
            notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        currentOverride = .none
    }

    private func evaluateMediaContext() {
        guard let bundleID = frontmostBundleIdentifier(), mediaBundleIdentifiers.contains(bundleID) else {
            currentOverride = .none
            return
        }

        currentOverride = ActivityOverrideSnapshot(isSuspended: true, reason: .foregroundMedia, until: nil)
    }
}
