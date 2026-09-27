//
//  PrefCircadianView.swift
//  Shifty
//

import SwiftUI

// MARK: - Status text

extension CircadianStatus {
    /// A one-line summary such as "Evening · 4100K · Deep Night at 22:15".
    func displayText(timeFormatter: DateFormatter) -> String {
        var parts = isSuspended
            ? [NSLocalizedString("menu.circadian.paused", comment: "Circadian Mode is paused")]
            : [target.phase.localizedName, "\(target.kelvin)K"]

        if let nextTransition {
            parts.append(String(
                format: NSLocalizedString("menu.circadian.next_format", comment: "Next phase and its start time, e.g. Deep Night at 22:15"),
                nextTransition.phase.localizedName,
                timeFormatter.string(from: nextTransition.date)))
        }
        return parts.joined(separator: " · ")
    }
}

extension CircadianPhase {
    var localizedName: String {
        switch self {
        case .daylight:
            return NSLocalizedString("menu.circadian.phase.daylight", comment: "Circadian phase name")
        case .evening:
            return NSLocalizedString("menu.circadian.phase.evening", comment: "Circadian phase name")
        case .deepNight:
            return NSLocalizedString("menu.circadian.phase.deep_night", comment: "Circadian phase name")
        }
    }
}

extension DateFormatter {
    static let circadianTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - PrefCircadianView

struct PrefCircadianView: View {
    private static let windDownOptions: [TimeInterval] = [3600, 2 * 3600, 3 * 3600]
    private static let nightKelvinRange = CircadianCurveConfiguration.kelvinRange.lowerBound...4500

    @AppStorage(Keys.isCircadianModeEnabled) private var isEnabled = false

    @State private var configuration = CircadianCurveConfiguration.default
    @State private var hasLoaded = false

    private var coordinator: CircadianWorkspaceCoordinator { .shared }

    var body: some View {
        Form {
            Section {
                Toggle("prefs.circadian.enable", isOn: $isEnabled)
                    .onChange(of: isEnabled) { _, _ in coordinator.applyNow() }

                TimelineView(.everyMinute) { context in
                    VStack(alignment: .leading, spacing: 6) {
                        CircadianScheduleStrip(configuration: configuration, now: context.date)
                        if isEnabled {
                            Text(coordinator.currentStatus().displayText(timeFormatter: .circadianTime))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .padding(.vertical, 4)
                }
            } footer: {
                Text("prefs.circadian.enable_footer")
            }

            Section("prefs.circadian.section.schedule") {
                DatePicker("prefs.circadian.wake_time", selection: timeBinding(\.wakeTime), displayedComponents: .hourAndMinute)
                DatePicker("prefs.circadian.bedtime", selection: timeBinding(\.bedtime), displayedComponents: .hourAndMinute)
                Picker("prefs.circadian.wind_down", selection: binding(\.eveningLeadTime)) {
                    ForEach(windDownChoices, id: \.self) { leadTime in
                        Text(windDownLabel(leadTime)).tag(leadTime)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("prefs.circadian.section.warmth") {
                LabeledContent("prefs.circadian.night_warmth") {
                    HStack(spacing: 8) {
                        Slider(value: nightWarmthBinding, in: 0...1) {
                            EmptyView()
                        } minimumValueLabel: {
                            Image(systemName: "sun.max")
                        } maximumValueLabel: {
                            Image(systemName: "moon")
                        }
                        .labelsHidden()
                        Text(verbatim: "\(configuration.deepNightKelvin)K")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(minWidth: 48, alignment: .trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            configuration = coordinator.configuration
            hasLoaded = true
        }
    }

    // MARK: Bindings

    /// Writes every edit through the coordinator, which validates, persists and applies it,
    /// then reads back the validated result so the controls show what is actually in effect.
    private func binding<Value>(_ keyPath: WritableKeyPath<CircadianCurveConfiguration, Value>) -> Binding<Value> {
        Binding(
            get: { configuration[keyPath: keyPath] },
            set: { newValue in
                var updated = configuration
                updated[keyPath: keyPath] = newValue
                apply(updated)
            })
    }

    private func timeBinding(_ keyPath: WritableKeyPath<CircadianCurveConfiguration, DateComponents>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.date(from: configuration[keyPath: keyPath]) ?? Date() },
            set: { newValue in
                var updated = configuration
                updated[keyPath: keyPath] = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                apply(updated)
            })
    }

    /// 0 is the coolest night target and 1 the warmest, so the slider reads left to right
    /// like the menu's sun-to-moon slider. Values snap to 100 K and `apply` skips unchanged
    /// configurations, so a drag only applies when the rounded Kelvin value changes.
    private var nightWarmthBinding: Binding<Double> {
        let range = Self.nightKelvinRange
        let span = Double(range.upperBound - range.lowerBound)
        return Binding(
            get: {
                let kelvin = min(max(configuration.deepNightKelvin, range.lowerBound), range.upperBound)
                return Double(range.upperBound - kelvin) / span
            },
            set: { warmth in
                var updated = configuration
                updated.deepNightKelvin = range.upperBound - Int((warmth * span / 100).rounded()) * 100
                updated.eveningKelvin = max(updated.eveningKelvin, updated.deepNightKelvin)
                apply(updated)
            })
    }

    private func apply(_ updated: CircadianCurveConfiguration) {
        guard hasLoaded, updated != configuration else { return }
        coordinator.updateConfiguration(updated)
        configuration = coordinator.configuration
    }

    // MARK: Wind-down choices

    /// The standard choices, plus the stored value if validation shortened it to fit a short waking day.
    private var windDownChoices: [TimeInterval] {
        let current = configuration.eveningLeadTime
        return Self.windDownOptions.contains(current)
            ? Self.windDownOptions
            : (Self.windDownOptions + [current]).sorted()
    }

    private func windDownLabel(_ leadTime: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.hour, .minute]
        let duration = formatter.string(from: leadTime) ?? ""
        return String(
            format: NSLocalizedString("prefs.circadian.before_bedtime_format", comment: "Wind-down lead time, e.g. 2 hours before bedtime"),
            duration)
    }
}

// MARK: - CircadianScheduleStrip

/// A 24-hour bar, midnight to midnight, tinted by how warm each phase makes the display,
/// with a marker at the current time.
private struct CircadianScheduleStrip: View {
    let configuration: CircadianCurveConfiguration
    let now: Date

    private static let sampleMinutes = 5

    var body: some View {
        let segments = phaseSegments()
        VStack(alignment: .leading, spacing: 4) {
            Canvas { context, size in
                let minuteWidth = size.width / 1440
                for segment in segments {
                    let rect = CGRect(
                        x: CGFloat(segment.startMinute) * minuteWidth,
                        y: 0,
                        width: CGFloat(segment.endMinute - segment.startMinute) * minuteWidth,
                        height: size.height)
                    context.fill(Path(rect), with: .color(Self.tint(for: segment.phase)))
                }
                let markerX = CGFloat(minuteOfDay(now)) * minuteWidth
                context.fill(
                    Path(CGRect(x: markerX - 1, y: 0, width: 2, height: size.height)),
                    with: .color(.primary))
            }
            .frame(height: 14)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack {
                ForEach(["00:00", "06:00", "12:00", "18:00", "24:00"], id: \.self) { label in
                    Text(label)
                    if label != "24:00" { Spacer() }
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .monospacedDigit()

            HStack(spacing: 12) {
                ForEach([CircadianPhase.daylight, .evening, .deepNight], id: \.self) { phase in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Self.tint(for: phase))
                            .frame(width: 10, height: 10)
                        Text(phase.localizedName)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary(segments)))
    }

    private static func tint(for phase: CircadianPhase) -> Color {
        switch phase {
        case .daylight:
            return .primary.opacity(0.12)
        case .evening:
            return .orange.opacity(0.45)
        case .deepNight:
            return .orange.opacity(0.85)
        }
    }

    private struct Segment {
        var phase: CircadianPhase
        var startMinute: Int
        var endMinute: Int
    }

    /// Samples the real transition engine across today so the strip always matches the schedule.
    private func phaseSegments() -> [Segment] {
        let calendar = Calendar.current
        let engine = CircadianTransitionEngine(configuration: configuration, calendar: calendar)
        let startOfDay = calendar.startOfDay(for: now)
        var segments = [Segment]()

        for minute in stride(from: 0, to: 1440, by: Self.sampleMinutes) {
            let phase = engine.target(for: startOfDay.addingTimeInterval(TimeInterval(minute * 60))).phase
            if let last = segments.last, last.phase == phase {
                segments[segments.count - 1].endMinute = minute + Self.sampleMinutes
            } else {
                segments.append(Segment(phase: phase, startMinute: minute, endMinute: minute + Self.sampleMinutes))
            }
        }
        return segments
    }

    private func minuteOfDay(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return ((components.hour ?? 0) * 60) + (components.minute ?? 0)
    }

    private func accessibilitySummary(_ segments: [Segment]) -> String {
        let formatter = DateFormatter.circadianTime
        let startOfDay = Calendar.current.startOfDay(for: now)
        return segments.map { segment in
            let start = formatter.string(from: startOfDay.addingTimeInterval(TimeInterval(segment.startMinute * 60)))
            return "\(segment.phase.localizedName) \(start)"
        }
        .joined(separator: ", ")
    }
}
