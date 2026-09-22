import Foundation

enum RoutineScheduleTests {
    static var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-09-21 is a Monday.
    static func date(_ day: Int, _ hour: Int, _ minute: Int, month: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    static func routine(_ hour: Int, _ minute: Int, days: Set<Int> = Routine.everyDay, enabled: Bool = true) -> Routine {
        Routine(name: "Test", isEnabled: enabled, hour: hour, minute: minute, weekdays: days, actions: [])
    }

    static let all: [TestCase] = [
        TestCase(name: "occurrence respects weekdays") {
            let weekdays = routine(9, 0, days: Routine.weekdaysOnly)
            try expectEqual(RoutineSchedule.occurrence(of: weekdays, on: date(21, 0, 0), calendar: calendar), date(21, 9, 0))
            try expectNil(RoutineSchedule.occurrence(of: weekdays, on: date(26, 0, 0), calendar: calendar))
        },
        TestCase(name: "nextRun later today") {
            try expectEqual(RoutineSchedule.nextRun(of: routine(9, 0), after: date(21, 8, 0), calendar: calendar), date(21, 9, 0))
        },
        TestCase(name: "nextRun skips to the next allowed day") {
            // Friday 10:00, weekdays only: next is Monday.
            let next = RoutineSchedule.nextRun(of: routine(9, 0, days: Routine.weekdaysOnly), after: date(25, 10, 0), calendar: calendar)
            try expectEqual(next, date(28, 9, 0))
        },
        TestCase(name: "nextRun is strictly after the given date") {
            try expectEqual(RoutineSchedule.nextRun(of: routine(9, 0), after: date(21, 9, 0), calendar: calendar), date(22, 9, 0))
        },
        TestCase(name: "nextRun is nil when disabled or without days") {
            try expectNil(RoutineSchedule.nextRun(of: routine(9, 0, enabled: false), after: date(21, 8, 0), calendar: calendar))
            try expectNil(RoutineSchedule.nextRun(of: routine(9, 0, days: []), after: date(21, 8, 0), calendar: calendar))
        },
        TestCase(name: "occurrences covers a range across days") {
            let times = RoutineSchedule.occurrences(of: routine(9, 0), after: date(21, 8, 0), through: date(23, 9, 0), calendar: calendar)
            try expectEqual(times, [date(21, 9, 0), date(22, 9, 0), date(23, 9, 0)])
        },
        TestCase(name: "occurrences excludes the start and handles empty ranges") {
            try expectEqual(RoutineSchedule.occurrences(of: routine(9, 0), after: date(21, 9, 0), through: date(21, 10, 0), calendar: calendar), [])
            try expectEqual(RoutineSchedule.occurrences(of: routine(9, 0), after: date(21, 10, 0), through: date(21, 8, 0), calendar: calendar), [])
        },
        TestCase(name: "due fires a routine whose time was just crossed") {
            let due = RoutineSchedule.due([routine(9, 0)], lastCheck: date(21, 8, 59), now: date(21, 9, 0), calendar: calendar)
            try expectEqual(due.count, 1)
        },
        TestCase(name: "due does not fire twice for the same time") {
            try expect(RoutineSchedule.due([routine(9, 0)], lastCheck: date(21, 9, 0), now: date(21, 9, 1), calendar: calendar).isEmpty)
        },
        TestCase(name: "due catches up after sleep within the window") {
            let due = RoutineSchedule.due([routine(9, 0)], lastCheck: date(21, 8, 0), now: date(21, 9, 14), calendar: calendar)
            try expectEqual(due.count, 1)
        },
        TestCase(name: "due skips routines older than the catch-up window") {
            try expect(RoutineSchedule.due([routine(9, 0)], lastCheck: date(21, 8, 0), now: date(21, 9, 16), calendar: calendar).isEmpty)
        },
        TestCase(name: "due ignores disabled routines") {
            try expect(RoutineSchedule.due([routine(9, 0, enabled: false)], lastCheck: date(21, 8, 59), now: date(21, 9, 0), calendar: calendar).isEmpty)
        },
        TestCase(name: "daysText names common sets") {
            try expectEqual(RoutineSchedule.daysText(Routine.everyDay, calendar: calendar), "Every day")
            try expectEqual(RoutineSchedule.daysText(Routine.weekdaysOnly, calendar: calendar), "Weekdays")
            try expectEqual(RoutineSchedule.daysText(Routine.weekend, calendar: calendar), "Weekends")
            try expectEqual(RoutineSchedule.daysText([], calendar: calendar), "Never")
        },
        TestCase(name: "templates only reference sounds and scenes that exist") {
            let ids = Set(library.map(\.id)).union(RoutineSounds.scenes.map { "scene:\($0.id)" })
            for template in RoutineTemplates.all {
                for action in template.make().actions where action.kind == .playSound && !action.choice.hasPrefix("preset:") {
                    try expect(ids.contains(action.choice), "\(template.id) uses unknown sound \(action.choice)")
                }
            }
        }
    ]
}
