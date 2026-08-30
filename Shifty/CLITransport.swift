import Foundation

enum CLICommand: String {
    case queryState
    case setTemporaryPause
    case clearTemporaryPause
    case toggleEnabled
}

protocol CLIBridgeControlling: AnyObject {
    static var notificationName: Notification.Name { get }
    func post(command: CLICommand, payload: [String: Any])
}

final class DistributedNotificationCLIBridge: CLIBridgeControlling {
    static let notificationName = Notification.Name("io.natethompson.Shifty.cli")
    static let responseNotificationName = Notification.Name("io.natethompson.Shifty.cli.response")

    func post(command: CLICommand, payload: [String: Any] = [:]) {
        var userInfo = payload
        userInfo["command"] = command.rawValue
        DistributedNotificationCenter.default().postNotificationName(
            Self.notificationName,
            object: Bundle.main.bundleIdentifier,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }
}
