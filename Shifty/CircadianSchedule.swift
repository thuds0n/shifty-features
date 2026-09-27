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

/// The next phase the schedule will enter, and when.
struct CircadianTransition: Equatable {
    var phase: CircadianPhase
    var date: Date
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

    static let kelvinRange = 2700...6500
    static let maximumLeadTime: TimeInterval = 6 * 3600

    /// Returns a configuration that the transition engine can always schedule:
    /// times are whole minutes of the day, bedtime and wake time differ, Kelvin
    /// targets are bounded and get warmer through the evening, and the ramps fit
    /// inside the waking day.
    func validated() -> CircadianCurveConfiguration {
        let bedtimeMinutes = Self.minuteOfDay(bedtime)
        let wakeMinutes = Self.minuteOfDay(wakeTime)
        guard bedtimeMinutes != wakeMinutes else { return .default }

        let daylight = clampKelvin(daylightKelvin)
        let evening = min(clampKelvin(eveningKelvin), daylight)
        let deepNight = min(clampKelvin(deepNightKelvin), evening)

        let awakeMinutes = (bedtimeMinutes - wakeMinutes + 1440) % 1440
        let maximumEveningLead = min(Self.maximumLeadTime, TimeInterval(awakeMinutes * 60))
        let eveningLead = min(max(eveningLeadTime, 0), maximumEveningLead)
        let deepNightLead = min(max(deepNightLeadTime, 0), eveningLead)

        return CircadianCurveConfiguration(
            bedtime: DateComponents(hour: bedtimeMinutes / 60, minute: bedtimeMinutes % 60),
            wakeTime: DateComponents(hour: wakeMinutes / 60, minute: wakeMinutes % 60),
            daylightKelvin: daylight,
            eveningKelvin: evening,
            deepNightKelvin: deepNight,
            eveningLeadTime: eveningLead,
            deepNightLeadTime: deepNightLead
        )
    }

    static func minuteOfDay(_ components: DateComponents) -> Int {
        let hour = min(max(components.hour ?? 0, 0), 23)
        let minute = min(max(components.minute ?? 0, 0), 59)
        return (hour * 60) + minute
    }

    private func clampKelvin(_ kelvin: Int) -> Int {
        min(max(kelvin, Self.kelvinRange.lowerBound), Self.kelvinRange.upperBound)
    }
}

protocol CircadianTransitioning: AnyObject {
    var configuration: CircadianCurveConfiguration { get set }
    func target(for date: Date) -> CircadianTarget
    func nextTransition(after date: Date) -> CircadianTransition?
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

        let (eveningLeadTime, deepNightLeadTime) = leadTimes
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

    func nextTransition(after date: Date) -> CircadianTransition? {
        let phase = target(for: date).phase

        if phase == .deepNight {
            return occurrence(of: configuration.wakeTime, after: date)
                .map { CircadianTransition(phase: .daylight, date: $0) }
        }

        guard let bedtime = occurrence(of: configuration.bedtime, after: date) else { return nil }
        let (eveningLeadTime, deepNightLeadTime) = leadTimes
        if phase == .daylight && eveningLeadTime > deepNightLeadTime {
            return CircadianTransition(phase: .evening, date: bedtime.addingTimeInterval(-eveningLeadTime))
        }
        return CircadianTransition(phase: .deepNight, date: bedtime.addingTimeInterval(-deepNightLeadTime))
    }

    private var leadTimes: (evening: TimeInterval, deepNight: TimeInterval) {
        let evening = max(configuration.eveningLeadTime, 0)
        return (evening, min(max(configuration.deepNightLeadTime, 0), evening))
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
