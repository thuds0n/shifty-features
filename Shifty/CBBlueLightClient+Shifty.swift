//
//  CBBlueLightClient+Shifty.swift
//  CBBlueLightClient+Shifty
//
//  Created by Nate Thompson on 8/28/21.
//

import Foundation
import SwiftLog

protocol NightShiftSystemControlling: AnyObject {
    var supportsNightShift: Bool { get }
    var isNightShiftEnabled: Bool { get }
    var colorTemperature: Float { get set }
    var schedule: ScheduleType { get set }
    var scheduledState: Bool { get }

    func previewColorTemperature(_ value: Float)
    func setNightShiftEnabled(_ newValue: Bool)
    func setToSchedule()
    func setStatusNotificationBlock(_ block: @escaping () -> Void)
}

final class CoreBrightnessNightShiftClient: NightShiftSystemControlling {
    static let shared = CoreBrightnessNightShiftClient()

    private let client = CBBlueLightClient()
    private let brightnessSystemClient = BrightnessSystemClient()

    var supportsNightShift: Bool {
        CBBlueLightClient.supportsBlueLightReduction()
    }

    private var blueLightStatus: Status {
        var status: Status = Status()
        client.getBlueLightStatus(&status)
        return status
    }

    var colorTemperature: Float {
        get {
            var strength: Float = 0
            client.getStrength(&strength)
            return strength
        }
        set {
            client.setStrength(newValue, commit: true)
        }
    }
    
    func previewColorTemperature(_ value: Float) {
        client.setStrength(value, commit: false)
    }

    var isNightShiftEnabled: Bool {
        blueLightStatus.enabled.boolValue
    }
    
    func setNightShiftEnabled(_ newValue: Bool) {
        client.setEnabled(newValue)
        
        // Set to appropriate strength when in schedule transition by resetting schedule
        if newValue && scheduledState {
            let savedSchedule = schedule
            schedule = .off
            schedule = savedSchedule
        }
    }

    var schedule: ScheduleType {
        get {
            switch blueLightStatus.mode {
            case 0:
                return .off
            case 1:
                return .solar
            case 2:
                return .custom(start: blueLightStatus.schedule.fromTime, end: blueLightStatus.schedule.toTime)
            default:
                assertionFailure("Unknown mode")
                return .off
            }
        }
        set {
            switch newValue {
            case .off:
                client.setMode(0)
            case .solar:
                client.setMode(1)
            case .custom(start: let start, end: let end):
                client.setMode(2)
                var schedule = Schedule(fromTime: start, toTime: end)
                client.setSchedule(&schedule)
            }
        }
    }
    
    var scheduledState: Bool {
        switch schedule {
        case .off:
            return false
        case .custom(start: let startTime, end: let endTime):
            let now = Time(Date())
            if endTime > startTime {
                //startTime and endTime are on the same day
                let scheduledState = now >= startTime && now < endTime
                logw("scheduled state: \(scheduledState)")
                return scheduledState
            } else {
                //endTime is on the day following startTime
                let scheduledState = now >= startTime || now < endTime
                logw("scheduled state: \(scheduledState)")
                return scheduledState
            }
        case .solar:
            guard let sunrise = brightnessSystemClient?.sunrise,
                let sunset = brightnessSystemClient?.sunset else {
                logw("Found nil for object BrightnessSystemClient. Returning false for scheduledState.")
                return false
            }
            let now = Date()
            logw("sunset: \(sunset)")
            logw("sunrise: \(sunrise)")
            
            // For some reason, BrightnessSystemClient.isDaylight doesn't track perfectly with sunrise and sunset
            // Should return true when not daylight
            let scheduledState : Bool
            let order = NSCalendar.current.compare(sunrise, to: sunset, toGranularity: .day)
            switch order {
                case .orderedSame, .orderedAscending:
                    scheduledState = now >= sunset || now <= sunrise
                case .orderedDescending:
                    scheduledState = now >= sunset && now <= sunrise
            }
            logw("scheduled state: \(scheduledState)")
            return scheduledState
        }
    }
    
    func setToSchedule() {
        if isNightShiftEnabled != scheduledState {
            setNightShiftEnabled(scheduledState)
        }
    }

    func setStatusNotificationBlock(_ block: @escaping () -> Void) {
        client.setStatusNotificationBlock(block)
    }
}

enum ScheduleType: Equatable {
    case off
    case solar
    case custom(start: Time, end: Time)
    
    static func == (lhs: ScheduleType, rhs: ScheduleType) -> Bool {
        switch (lhs, rhs) {
        case (.off, .off), (.solar, .solar):
            return true
        case (let .custom(leftStart, leftEnd), let custom(rightStart, rightEnd)):
            return leftStart == rightStart && leftEnd == rightEnd
        default:
            return false
        }
    }
}
