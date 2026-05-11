import Foundation
import OutlookWatchdogLib

// Simple test runner — no XCTest dependency required

var passed = 0
var failed = 0

func assert(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    if condition {
        passed += 1
    } else {
        failed += 1
        print("  FAIL: \(message) (\(file):\(line))")
    }
}

func test(_ name: String, _ body: () -> Void) {
    print("• \(name)")
    body()
}

// MARK: - Window Classification

test("classifyWindow: Inbox → main") {
    let w = WindowInfo(name: "Inbox • user@example.com", id: 1, visible: true)
    assert(classifyWindow(w) == .main, "Inbox should be .main")
}

test("classifyWindow: Calendar → main") {
    let w = WindowInfo(name: "Calendar", id: 2, visible: true)
    assert(classifyWindow(w) == .main, "Calendar should be .main")
}

test("classifyWindow: Mail → main") {
    let w = WindowInfo(name: "Mail", id: 3, visible: false)
    assert(classifyWindow(w) == .main, "Mail should be .main")
}

test("classifyWindow: empty name → companion") {
    let w = WindowInfo(name: "", id: 4, visible: false)
    assert(classifyWindow(w) == .companion, "Empty name should be .companion")
}

test("classifyWindow: Reminder → reminder") {
    let w = WindowInfo(name: "1 Reminder", id: 5, visible: false)
    assert(classifyWindow(w) == .reminder, "Reminder should be .reminder")
}

test("classifyWindow: other → unknown") {
    let w = WindowInfo(name: "Some Other Window", id: 6, visible: true)
    assert(classifyWindow(w) == .unknown, "Other should be .unknown")
}

// MARK: - Snapshot: Fresh Launch

test("fresh launch: no zombies") {
    let windows = [
        WindowInfo(name: "Inbox • user@example.com", id: 1, visible: true),
        WindowInfo(name: "", id: 2, visible: false),
    ]
    let s = WindowSnapshot(windows: windows)
    assert(s.totalZombieCount == 0, "Expected 0 zombies, got \(s.totalZombieCount)")
    assert(s.zombieMainCount == 0, "Expected 0 zombie mains")
    assert(!s.hasZombies, "Should not have zombies")
}

// MARK: - Snapshot: After Close/Reopen Cycles

test("realistic one cycle: zombies detected") {
    // 1 visible Inbox, 2 hidden Inbox, 3 hidden companions
    let windows = [
        WindowInfo(name: "Inbox • user@example.com", id: 5, visible: true),
        WindowInfo(name: "Inbox • user@example.com", id: 3, visible: false),
        WindowInfo(name: "Inbox • user@example.com", id: 1, visible: false),
        WindowInfo(name: "", id: 6, visible: false),
        WindowInfo(name: "", id: 4, visible: false),
        WindowInfo(name: "", id: 2, visible: false),
    ]
    let s = WindowSnapshot(windows: windows)
    assert(s.hiddenMainCount == 2, "Expected 2 hidden mains, got \(s.hiddenMainCount)")
    assert(s.zombieMainCount == 1, "Expected 1 zombie main, got \(s.zombieMainCount)")
    assert(s.hasZombies, "Should have zombies")
}

test("many cycles: large zombie count") {
    var windows = [WindowInfo(name: "Inbox • user@example.com", id: 100, visible: true)]
    for i in 0..<10 {
        windows.append(WindowInfo(name: "Inbox • user@example.com", id: i, visible: false))
        windows.append(WindowInfo(name: "", id: 1000 + i, visible: false))
    }
    let s = WindowSnapshot(windows: windows)
    assert(s.windows.count == 21, "Expected 21 windows")
    assert(s.zombieMainCount == 9, "Expected 9 zombie mains, got \(s.zombieMainCount)")
    assert(s.hasZombies, "Should have zombies")
}

// MARK: - Snapshot: Edge Cases

test("no windows: no zombies") {
    let s = WindowSnapshot(windows: [])
    assert(s.totalZombieCount == 0, "Expected 0 zombies")
    assert(!s.hasZombies, "Should not have zombies")
}

test("only reminders: no zombies") {
    let windows = [WindowInfo(name: "1 Reminder", id: 1, visible: false)]
    let s = WindowSnapshot(windows: windows)
    assert(s.totalZombieCount == 0, "Expected 0 zombies")
}

test("all hidden, no visible: expected state after ⌘W") {
    let windows = [
        WindowInfo(name: "Inbox • user@example.com", id: 1, visible: false),
        WindowInfo(name: "", id: 2, visible: false),
    ]
    let s = WindowSnapshot(windows: windows)
    assert(s.visibleMainCount == 0, "Expected 0 visible mains")
    assert(s.hiddenMainCount == 1, "Expected 1 hidden main")
    assert(s.zombieMainCount == 0, "1 hidden main is expected, not a zombie")
}

// MARK: - Detector: State Change Detection

test("detector: first run always reports") {
    let detector = ZombieDetector()
    let windows = [
        WindowInfo(name: "Inbox • user@example.com", id: 1, visible: true),
        WindowInfo(name: "", id: 2, visible: false),
    ]
    let report = detector.analyze(windows: windows, processInfo: nil)
    assert(report != nil, "First run should produce a report")
    assert(report?.totalWindows == 2, "Expected 2 total windows")
    assert(report?.totalZombieCount == 0, "Expected 0 zombies on first run")
}

test("detector: unchanged state suppressed") {
    let detector = ZombieDetector()
    let windows = [
        WindowInfo(name: "Inbox • user@example.com", id: 1, visible: true),
        WindowInfo(name: "", id: 2, visible: false),
    ]
    _ = detector.analyze(windows: windows, processInfo: nil)
    let report2 = detector.analyze(windows: windows, processInfo: nil)
    assert(report2 == nil, "Unchanged state should be suppressed")
}

test("detector: zombie creation triggers report with delta") {
    let detector = ZombieDetector()

    let baseline = [
        WindowInfo(name: "Inbox • user@example.com", id: 1, visible: true),
        WindowInfo(name: "", id: 2, visible: false),
    ]
    _ = detector.analyze(windows: baseline, processInfo: nil)

    let afterCycle = [
        WindowInfo(name: "Inbox • user@example.com", id: 3, visible: true),
        WindowInfo(name: "Inbox • user@example.com", id: 1, visible: false),
        WindowInfo(name: "Inbox • user@example.com", id: 5, visible: false),
        WindowInfo(name: "", id: 4, visible: false),
        WindowInfo(name: "", id: 2, visible: false),
        WindowInfo(name: "", id: 6, visible: false),
    ]
    let report = detector.analyze(windows: afterCycle, processInfo: nil)

    assert(report != nil, "Zombie creation should trigger a report")
    assert(report!.totalZombieCount > 0, "Should have zombies")
    assert(report!.delta != nil, "Should have a delta")
    assert(report!.delta!.windowCountChange > 0, "Window count should increase")
    assert(report!.delta!.zombieCountChange > 0, "Zombie count should increase")
}

// MARK: - Parse Window List

test("parseWindowList: normal input") {
    let raw = "Inbox • user@example.com\t100\ttrue\nCalendar\t101\tfalse\n"
    let windows = parseWindowList(raw)
    assert(windows.count == 2, "Expected 2 windows, got \(windows.count)")
    assert(windows[0].name == "Inbox • user@example.com", "Wrong name")
    assert(windows[0].id == 100, "Wrong id")
    assert(windows[0].visible == true, "Should be visible")
    assert(windows[1].name == "Calendar", "Wrong name")
    assert(windows[1].visible == false, "Should be hidden")
}

test("parseWindowList: empty input") {
    assert(parseWindowList("").count == 0, "Empty input should return empty")
}

test("parseWindowList: companion with empty name") {
    let raw = "\t102\tfalse\n"
    let windows = parseWindowList(raw)
    assert(windows.count == 1, "Expected 1 window")
    assert(windows[0].name == "", "Name should be empty")
}

// MARK: - Summary

print("\n\(passed + failed) tests: \(passed) passed, \(failed) failed")
exit(failed > 0 ? 1 : 0)
