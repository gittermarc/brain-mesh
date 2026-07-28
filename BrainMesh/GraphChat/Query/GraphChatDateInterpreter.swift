//
//  GraphChatDateInterpreter.swift
//  BrainMesh
//
//  Calendar- and time-zone-aware date boundaries for validated query plans.
//

import Foundation

nonisolated enum GraphChatDateInterpretationError: LocalizedError, Equatable, Sendable {
    case invalidYear(Int)
    case invalidMonth(year: Int, month: Int)
    case invalidDateInterval

    var errorDescription: String? {
        switch self {
        case .invalidYear(let year):
            return "Das Jahr \(year) kann mit dem verwendeten Kalender nicht interpretiert werden."
        case .invalidMonth(let year, let month):
            return "Der Monat \(month)/\(year) kann mit dem verwendeten Kalender nicht interpretiert werden."
        case .invalidDateInterval:
            return "Der Datumsbereich muss eine aufsteigende halb-offene Grenze besitzen."
        }
    }
}

nonisolated struct GraphChatDateInterpreter: Sendable {
    private let calendar: Calendar
    private let timeZone: TimeZone
    let referenceDate: Date

    init(
        calendar: Calendar,
        timeZone: TimeZone,
        referenceDate: Date
    ) {
        var configuredCalendar = calendar
        configuredCalendar.timeZone = timeZone
        self.calendar = configuredCalendar
        self.timeZone = timeZone
        self.referenceDate = referenceDate
    }

    func interval(forYear year: Int) throws -> GraphQueryDateInterval {
        let components = DateComponents(
            calendar: calendar,
            timeZone: timeZone,
            year: year,
            month: 1,
            day: 1
        )
        guard
            let lowerBound = calendar.date(from: components),
            let upperBound = calendar.date(byAdding: .year, value: 1, to: lowerBound),
            lowerBound < upperBound
        else {
            throw GraphChatDateInterpretationError.invalidYear(year)
        }
        return GraphQueryDateInterval(
            lowerBound: lowerBound,
            upperBoundExclusive: upperBound
        )
    }

    func interval(forMonth value: GraphQueryYearMonth) throws -> GraphQueryDateInterval {
        guard (1...12).contains(value.month) else {
            throw GraphChatDateInterpretationError.invalidMonth(
                year: value.year,
                month: value.month
            )
        }

        let components = DateComponents(
            calendar: calendar,
            timeZone: timeZone,
            year: value.year,
            month: value.month,
            day: 1
        )
        guard
            let lowerBound = calendar.date(from: components),
            let upperBound = calendar.date(byAdding: .month, value: 1, to: lowerBound),
            lowerBound < upperBound
        else {
            throw GraphChatDateInterpretationError.invalidMonth(
                year: value.year,
                month: value.month
            )
        }
        return GraphQueryDateInterval(
            lowerBound: lowerBound,
            upperBoundExclusive: upperBound
        )
    }

    func overdueInterval() -> GraphQueryDateInterval {
        GraphQueryDateInterval(
            lowerBound: .distantPast,
            upperBoundExclusive: calendar.startOfDay(for: referenceDate)
        )
    }

    func interval(forCalendarDay date: Date) throws
        -> GraphQueryDateInterval
    {
        let lowerBound = calendar.startOfDay(for: date)
        guard
            let upperBound = calendar.date(
                byAdding: .day,
                value: 1,
                to: lowerBound
            ),
            lowerBound < upperBound
        else {
            throw GraphChatDateInterpretationError
                .invalidDateInterval
        }
        return GraphQueryDateInterval(
            lowerBound: lowerBound,
            upperBoundExclusive: upperBound
        )
    }

    func validate(
        interval: GraphQueryDateInterval
    ) throws -> GraphQueryDateInterval {
        guard interval.lowerBound < interval.upperBoundExclusive else {
            throw GraphChatDateInterpretationError.invalidDateInterval
        }
        return interval
    }

    func dateDescription(_ date: Date) -> String {
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: date
        )
        guard
            let year = components.year,
            let month = components.month,
            let day = components.day
        else {
            return date.formatted(.iso8601)
        }
        return String(
            format: "%04d-%02d-%02d",
            locale: Locale(identifier: "en_US_POSIX"),
            year,
            month,
            day
        )
    }

    func intervalDescription(
        _ interval: GraphQueryDateInterval
    ) -> String {
        "\(dateDescription(interval.lowerBound)) bis vor "
            + dateDescription(interval.upperBoundExclusive)
    }
}
