import Foundation

enum ModeTests {
    static func app(_ id: String) -> ModeApp { ModeApp(bundleID: id, name: id) }

    static func mode(apps: [String], distractions: [String] = [], action: BrisaMode.DistractionAction = .hide,
                     end: BrisaMode.EndAction = .minimize) -> BrisaMode {
        BrisaMode(name: "Test", apps: apps.map(app), distractions: distractions.map(app), distractionAction: action, endAction: end)
    }

    static let all: [TestCase] = [
        TestCase(name: "distractions: only running ones are handled") {
            let study = mode(apps: ["notion"], distractions: ["whatsapp", "discord"])
            try expectEqual(ModePlanner.distractionsToHandle(in: study, running: ["whatsapp", "notion"]), ["whatsapp"])
        },
        TestCase(name: "distractions: never an app the mode uses, Brisa or Finder") {
            let study = mode(apps: ["notion"], distractions: ["notion", "local.brisa.ambient", "com.apple.finder", "discord"])
            let running: Set<String> = ["notion", "local.brisa.ambient", "com.apple.finder", "discord"]
            try expectEqual(ModePlanner.distractionsToHandle(in: study, running: running), ["discord"])
        },
        TestCase(name: "distractions: left alone when the mode says so") {
            let study = mode(apps: ["notion"], distractions: ["discord"], action: .leave)
            try expectEqual(ModePlanner.distractionsToHandle(in: study, running: ["discord"]), [])
        },
        TestCase(name: "ending puts away the mode's apps") {
            try expectEqual(ModePlanner.appsToPutAway(ending: mode(apps: ["notion", "anki"]), switchingTo: nil), ["notion", "anki"])
        },
        TestCase(name: "ending leaves apps open when asked") {
            try expectEqual(ModePlanner.appsToPutAway(ending: mode(apps: ["notion"], end: .leaveOpen), switchingTo: nil), [])
        },
        TestCase(name: "switching keeps apps both modes use") {
            let study = mode(apps: ["notion", "anki", "pdf"], end: .quit)
            let work = mode(apps: ["notion", "slack"])
            try expectEqual(ModePlanner.appsToPutAway(ending: study, switchingTo: work), ["anki", "pdf"])
        },
        TestCase(name: "ending never touches Brisa or Finder") {
            let odd = mode(apps: ["com.apple.finder", "local.brisa.ambient", "notes"], end: .quit)
            try expectEqual(ModePlanner.appsToPutAway(ending: odd, switchingTo: nil), ["notes"])
        },
        TestCase(name: "screen frames convert to top-left coordinates") {
            // A 1440×900 main display and a 1920×1080 one above it.
            let main = ModePlanner.accessibilityFrame(of: CGRect(x: 0, y: 0, width: 1440, height: 900), mainScreenHeight: 900)
            let above = ModePlanner.accessibilityFrame(of: CGRect(x: 0, y: 900, width: 1920, height: 1080), mainScreenHeight: 900)
            try expectEqual(main, CGRect(x: 0, y: 0, width: 1440, height: 900))
            try expectEqual(above, CGRect(x: 0, y: -1080, width: 1920, height: 1080))
        },
        TestCase(name: "a window is restored only if it lands on a connected display") {
            let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
            try expect(ModePlanner.isVisible(WindowPlacement(CGRect(x: 100, y: 100, width: 800, height: 600)), on: screens))
            try expect(ModePlanner.isVisible(WindowPlacement(CGRect(x: 1300, y: 100, width: 800, height: 600)), on: screens), "mostly off to the right but 140 pt visible")
            try expect(!ModePlanner.isVisible(WindowPlacement(CGRect(x: 1400, y: 100, width: 800, height: 600)), on: screens), "only a sliver visible")
            try expect(!ModePlanner.isVisible(WindowPlacement(CGRect(x: 2000, y: 100, width: 800, height: 600)), on: screens), "on a missing monitor")
        },
        TestCase(name: "modes survive saving and loading") {
            var study = mode(apps: ["notion"], distractions: ["discord"], action: .quit, end: .quit)
            study.apps[0].windows = [WindowPlacement(CGRect(x: 10, y: 20, width: 300, height: 400))]
            study.sound = "scene:deepFocus"
            study.startFocusSession = true
            let data = try JSONEncoder().encode([study])
            try expectEqual(try JSONDecoder().decode([BrisaMode].self, from: data), [study])
        },
        TestCase(name: "routines can start and end modes") {
            let actions = [RoutineAction(kind: .startMode, choice: UUID().uuidString), RoutineAction(kind: .endMode)]
            let data = try JSONEncoder().encode(actions)
            try expectEqual(try JSONDecoder().decode([RoutineAction].self, from: data), actions)
        }
    ]
}
