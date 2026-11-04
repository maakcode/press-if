import Foundation

public enum ScheduleKind: String, Codable, Sendable {
    case now, after, at, daily
}

public struct ScheduleIntent: Codable, Equatable, Sendable {
    public let kind: ScheduleKind
    public let date: String?
    public let time: String?
    public let seconds: Int?

    public init(kind: ScheduleKind, date: String? = nil, time: String? = nil, seconds: Int? = nil) {
        self.kind = kind
        self.date = date
        self.time = time
        self.seconds = seconds
    }

    public func resolve(now: Date, timeZone: TimeZone) throws -> Date {
        switch kind {
        case .now: return now.addingTimeInterval(2)
        case .after:
            guard let seconds, (1...604800).contains(seconds) else {
                throw PressError.message("Choose a delay from 1 second to 7 days.")
            }
            return now.addingTimeInterval(TimeInterval(seconds))
        case .at, .daily:
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let clock = try clockComponents()
            if kind == .daily {
                guard let next = calendar.nextDate(after: now, matching: DateComponents(hour: clock.hour, minute: clock.minute, second: 0), matchingPolicy: .strict) else {
                    throw PressError.message("Could not calculate the next run time.")
                }
                return next
            }
            let day = try dateComponents(now: now, calendar: calendar)
            let components = DateComponents(timeZone: timeZone, year: day.year, month: day.month, day: day.day, hour: clock.hour, minute: clock.minute, second: 0)
            guard let resolved = calendar.date(from: components),
                  calendar.component(.year, from: resolved) == day.year,
                  calendar.component(.month, from: resolved) == day.month,
                  calendar.component(.day, from: resolved) == day.day,
                  calendar.component(.hour, from: resolved) == clock.hour,
                  calendar.component(.minute, from: resolved) == clock.minute else {
                throw PressError.message("This date or time does not exist.")
            }
            guard resolved > now else {
                throw PressError.message("This time has passed. Specify tomorrow or another date.")
            }
            return resolved
        }
    }

    private func clockComponents() throws -> (hour: Int, minute: Int) {
        guard let time, time.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil else {
            throw PressError.message("The run time must use HH:mm format.")
        }
        let components = time.split(separator: ":").compactMap { Int($0) }
        guard components.count == 2, (0...23).contains(components[0]), (0...59).contains(components[1]) else {
            throw PressError.message("The run time is invalid.")
        }
        return (components[0], components[1])
    }

    private func dateComponents(now: Date, calendar: Calendar) throws -> DateComponents {
        guard let date else { return calendar.dateComponents([.year, .month, .day], from: now) }
        guard date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            throw PressError.message("The run date is invalid.")
        }
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else {
            throw PressError.message("The run date is invalid.")
        }
        return DateComponents(year: parts[0], month: parts[1], day: parts[2])
    }
}
