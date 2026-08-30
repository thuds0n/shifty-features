import Foundation

enum CircadianPhase: String {
    case daylight
    case evening
    case deepNight
}

struct CircadianTarget: Equatable {
    var phase: CircadianPhase
    var kelvin: Int
    /// Normalised transition progress inside the current phase.
    var phaseProgress: Double
}

struct CircadianCurveConfiguration: Equatable {
    var bedtime: DateComponents
    var wakeTime: DateComponents
    var daylightKelvin: Int
    var eveningKelvin: Int
    var deepNightKelvin: Int
    var eveningLeadTime: TimeInterval
    var deepNightLeadTime: TimeInterval

    static let `default` = CircadianCurveConfiguration(
        bedtime: DateComponents(hour: 23, minute: 0),
        wakeTime: DateComponents(hour: 7, minute: 0),
        daylightKelvin: 6500,
        eveningKelvin: 4500,
        deepNightKelvin: 3200,
        eveningLeadTime: 2 * 3600,
        deepNightLeadTime: 45 * 60
    )
}

protocol CircadianTransitioning: AnyObject {
    var configuration: CircadianCurveConfiguration { get set }
    func target(for date: Date) -> CircadianTarget
}

final class CircadianTransitionEngine: CircadianTransitioning {
    var configuration: CircadianCurveConfiguration
    private let calendar: Calendar

    init(
        configuration: CircadianCurveConfiguration = .default,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.configuration = configuration
        self.calendar = calendar
    }

    func target(for date: Date) -> CircadianTarget {
        guard
            let mostRecentBedtime = occurrence(of: configuration.bedtime, onOrBefore: date),
            let mostRecentWake = occurrence(of: configuration.wakeTime, onOrBefore: date)
        else {
            return CircadianTarget(phase: .daylight, kelvin: configuration.daylightKelvin, phaseProgress: 0)
        }

        if mostRecentBedtime > mostRecentWake {
            return CircadianTarget(phase: .deepNight, kelvin: configuration.deepNightKelvin, phaseProgress: 1)
        }

        guard let bedtime = occurrence(of: configuration.bedtime, after: date) else {
            return CircadianTarget(phase: .daylight, kelvin: configuration.daylightKelvin, phaseProgress: 0)
        }

        let eveningLeadTime = max(configuration.eveningLeadTime, 0)
        let deepNightLeadTime = min(max(configuration.deepNightLeadTime, 0), eveningLeadTime)
        let secondsUntilBedtime = bedtime.timeIntervalSince(date)

        if secondsUntilBedtime > eveningLeadTime {
            return CircadianTarget(phase: .daylight, kelvin: configuration.daylightKelvin, phaseProgress: 0)
        }

        if secondsUntilBedtime > deepNightLeadTime {
            let span = eveningLeadTime - deepNightLeadTime
            let elapsed = eveningLeadTime - secondsUntilBedtime
            let progress = clamp(span == 0 ? 1 : elapsed / span)
            return CircadianTarget(
                phase: .evening,
                kelvin: interpolate(from: configuration.daylightKelvin, to: configuration.eveningKelvin, progress: progress),
                phaseProgress: progress
            )
        }

        let span = max(deepNightLeadTime, 1)
        let progress = clamp((deepNightLeadTime - secondsUntilBedtime) / span)
        return CircadianTarget(
            phase: .deepNight,
            kelvin: interpolate(from: configuration.eveningKelvin, to: configuration.deepNightKelvin, progress: progress),
            phaseProgress: progress
        )
    }

    private func occurrence(of components: DateComponents, onOrBefore date: Date) -> Date? {
        calendar.nextDate(
            after: date.addingTimeInterval(1),
            matching: timeComponents(from: components),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .backward
        )
    }

    private func occurrence(of components: DateComponents, after date: Date) -> Date? {
        calendar.nextDate(
            after: date,
            matching: timeComponents(from: components),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }

    private func timeComponents(from components: DateComponents) -> DateComponents {
        DateComponents(hour: components.hour ?? 0, minute: components.minute ?? 0, second: 0)
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func interpolate(from: Int, to: Int, progress: Double) -> Int {
        Int((Double(from) + (Double(to - from) * progress)).rounded())
    }
}
