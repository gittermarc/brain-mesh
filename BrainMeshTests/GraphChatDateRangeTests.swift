import Foundation
import Testing

@testable import BrainMesh

struct GraphChatDateRangeTests {

    @Test
    func yearRangesUseHalfOpenCalendarBoundariesAcrossTimeZones() throws {
        for identifier in ["Europe/Berlin", "America/New_York", "Asia/Tokyo"] {
            let timeZone = try #require(TimeZone(identifier: identifier))
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let referenceDate = try #require(
                calendar.date(
                    from: DateComponents(year: 2024, month: 6, day: 15, hour: 12)
                )
            )
            let interpreter = GraphChatDateInterpreter(
                calendar: calendar,
                timeZone: timeZone,
                referenceDate: referenceDate
            )
            let interval = try interpreter.interval(forYear: 2024)
            let expectedStart = try #require(
                calendar.date(
                    from: DateComponents(year: 2024, month: 1, day: 1)
                )
            )
            let expectedEnd = try #require(
                calendar.date(
                    from: DateComponents(year: 2025, month: 1, day: 1)
                )
            )

            #expect(interval.lowerBound == expectedStart)
            #expect(interval.upperBoundExclusive == expectedEnd)
            #expect(interval.lowerBound < interval.upperBoundExclusive)
        }
    }

    @Test
    func monthRangesCrossYearBoundaryAcrossTimeZones() throws {
        for identifier in ["Europe/Berlin", "America/New_York", "Asia/Tokyo"] {
            let timeZone = try #require(TimeZone(identifier: identifier))
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let referenceDate = try #require(
                calendar.date(
                    from: DateComponents(year: 2024, month: 12, day: 15, hour: 12)
                )
            )
            let interpreter = GraphChatDateInterpreter(
                calendar: calendar,
                timeZone: timeZone,
                referenceDate: referenceDate
            )
            let interval = try interpreter.interval(
                forMonth: GraphQueryYearMonth(year: 2024, month: 12)
            )

            #expect(
                interval.lowerBound
                    == calendar.date(
                        from: DateComponents(year: 2024, month: 12, day: 1)
                    )
            )
            #expect(
                interval.upperBoundExclusive
                    == calendar.date(
                        from: DateComponents(year: 2025, month: 1, day: 1)
                    )
            )
        }
    }

    @Test
    func overdueUsesInjectedReferenceDayAndTimeZone() throws {
        let timeZone = try #require(TimeZone(identifier: "America/New_York"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let referenceDate = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2024,
                    month: 7,
                    day: 4,
                    hour: 18,
                    minute: 30
                )
            )
        )
        let validator = GraphChatTestSupport.makeValidator(
            timeZoneIdentifier: "America/New_York",
            referenceDate: referenceDate
        )
        let plan = GraphQueryPlan(
            entityAlias: GraphEntityAlias("E1"),
            filters: [
                GraphQueryFilter(
                    fieldAlias: GraphFieldAlias("F5"),
                    operation: .isOverdue,
                    value: .none
                )
            ]
        )
        let validated = try validator.validate(
            plan,
            against: GraphChatTestSupport.makeSchemaContext()
        )

        guard case .dateInterval(let interval) = validated.filters[0].value else {
            Issue.record("Expected a resolved overdue date interval")
            return
        }
        #expect(interval.lowerBound == .distantPast)
        #expect(interval.upperBoundExclusive == calendar.startOfDay(for: referenceDate))
    }

    @Test
    func validatedYearDescriptionUsesInjectedTimeZoneBoundaries() throws {
        let timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let validator = GraphChatTestSupport.makeValidator(
            timeZoneIdentifier: "Europe/Berlin"
        )
        let plan = GraphQueryPlan(
            entityAlias: GraphEntityAlias("E1"),
            filters: [
                GraphQueryFilter(
                    fieldAlias: GraphFieldAlias("F5"),
                    operation: .inYear,
                    value: .year(2024)
                )
            ]
        )
        let validated = try validator.validate(
            plan,
            against: GraphChatTestSupport.makeSchemaContext()
        )
        let description = try #require(validated.filters.first?.valueDescription)
        let appliedFilters = GraphChatQueryEngine.appliedFilters(
            validated.filters,
            fieldMap: [:]
        )

        #expect(timeZone.identifier == "Europe/Berlin")
        #expect(description == "2024-01-01 bis vor 2025-01-01")
        #expect(appliedFilters.first?.valueDescription == description)
    }

    @Test
    func invalidMonthAndDescendingDateRangeAreRejected() {
        let invalidMonthPlan = GraphQueryPlan(
            entityAlias: GraphEntityAlias("E1"),
            filters: [
                GraphQueryFilter(
                    fieldAlias: GraphFieldAlias("F5"),
                    operation: .inMonth,
                    value: .month(GraphQueryYearMonth(year: 2024, month: 13))
                )
            ]
        )
        let descendingRangePlan = GraphQueryPlan(
            entityAlias: GraphEntityAlias("E1"),
            filters: [
                GraphQueryFilter(
                    fieldAlias: GraphFieldAlias("F5"),
                    operation: .between,
                    value: .dateInterval(
                        GraphQueryDateInterval(
                            lowerBound: Date(timeIntervalSince1970: 10),
                            upperBoundExclusive: Date(timeIntervalSince1970: 5)
                        )
                    )
                )
            ]
        )

        #expect(
            GraphChatTestSupport.validationError(for: invalidMonthPlan)?
                .issues.map(\.code) == [.invalidRange]
        )
        #expect(
            GraphChatTestSupport.validationError(for: descendingRangePlan)?
                .issues.map(\.code) == [.invalidRange]
        )
    }
}
