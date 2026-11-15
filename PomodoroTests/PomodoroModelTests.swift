import Foundation
#if TEST_RUNNER
#else
import XCTest
@testable import PomodoroKit
#endif

@MainActor
final class ModelChecks {
    private var suiteName = ""
    private var defaults = UserDefaults()
    private(set) var failures: [String] = []

    func setUp() {
        suiteName = "PomodoroTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        failures = []
    }

    func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDefaultsAndPersistence() {
        let model = makeModel()
        expectEqual(model.phase, .idle)
        expectEqual(model.studyMinutes, 25)
        expectEqual(model.breakMinutes, 5)

        model.studyMinutes = 40
        model.breakMinutes = 8

        let reloaded = makeModel()
        expectEqual(reloaded.studyMinutes, 40)
        expectEqual(reloaded.breakMinutes, 8)
    }

    func testInvalidStoredDurationsFallBackToDefaults() {
        defaults.set(0, forKey: PomodoroModel.studyKey)
        defaults.set(999, forKey: PomodoroModel.breakKey)
        let model = makeModel()
        expectEqual(model.studyMinutes, 25)
        expectEqual(model.breakMinutes, 5)
    }

    func testDurationsClampToRange() {
        let model = makeModel()
        model.studyMinutes = 500
        model.breakMinutes = 0
        expectEqual(model.studyMinutes, 180)
        expectEqual(model.breakMinutes, 1)
    }

    func testRightClickTogglesSettingsAndLeftClickStartsStudy() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let model = makeModel(clock: { start })

        model.rightClick()
        expectEqual(model.phase, .settings)
        model.dismissSettings()
        expectEqual(model.phase, .idle)

        model.rightClick()
        model.rightClick()
        expectEqual(model.phase, .idle)

        model.leftClick()
        expectEqual(model.phase, .studying)
        expectEqual(model.endDate, start.addingTimeInterval(25 * 60))
        expectEqual(model.remainingText, "25:00")
    }

    func testCountdownUsesEndDateAndStopReturnsIdle() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let model = makeModel(clock: { start })
        model.studyMinutes = 25
        model.leftClick()

        model.tick(at: start.addingTimeInterval(90))
        expectEqual(model.phase, .studying)
        expectEqual(model.remainingText, "23:30")

        model.rightClick()
        expectEqual(model.phase, .settings)
        model.dismissSettings()
        expectEqual(model.phase, .studying)
        expectEqual(model.remainingText, "23:30")

        model.stop()
        expectEqual(model.phase, .idle)
        expectNil(model.endDate)
    }

    func testStudyElapsedOpensBreakPrompt() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let model = makeModel(clock: { start })
        model.leftClick()

        model.tick(at: start.addingTimeInterval(25 * 60 - 0.01))
        expectEqual(model.phase, .studying)

        model.tick(at: start.addingTimeInterval(25 * 60))
        expectEqual(model.phase, .breakPrompt)
        expectNil(model.endDate)

        model.tick(at: start.addingTimeInterval(25 * 60 + 30))
        expectEqual(model.phase, .breakPrompt)
    }

    func testDeclineBreakResetsToIdle() {
        let model = makeModel()
        model.leftClick()
        model.tick(at: model.endDate!)
        model.declineBreak()
        expectEqual(model.phase, .idle)
        expectNil(model.endDate)
    }

    func testAcceptBreakThenFinishReturnsIdle() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let model = makeModel(clock: { start })
        model.breakMinutes = 5
        model.leftClick()
        model.tick(at: model.endDate!)
        model.acceptBreak()

        expectEqual(model.phase, .breaking)
        expectEqual(model.endDate, start.addingTimeInterval(5 * 60))
        expectEqual(model.remainingText, "05:00")

        model.tick(at: start.addingTimeInterval(5 * 60))
        expectEqual(model.phase, .idle)
        expectNil(model.endDate)
    }

    func testStopDuringBreakReturnsIdle() {
        let model = makeModel()
        model.leftClick()
        model.tick(at: model.endDate!)
        model.acceptBreak()
        model.stop()
        expectEqual(model.phase, .idle)
        expectNil(model.endDate)
    }

    func testShortTimersUseSeconds() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let model = makeModel(shortTimers: true, clock: { start })
        model.leftClick()
        expectEqual(model.endDate, start.addingTimeInterval(PomodoroModel.shortTimerSeconds))
    }

    func testRipenessMovesFromGreenToRed() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let model = makeModel(clock: { start })
        expectClose(model.ripeness, 1)

        model.leftClick()
        expectClose(model.ripeness, 0)

        model.tick(at: start.addingTimeInterval(25 * 30))
        expectClose(model.ripeness, 0.5)

        model.tick(at: start.addingTimeInterval(25 * 60 - 1))
        expectClose(model.ripeness, 1)
    }

    func testIgnoredActionsDoNotChangePhase() {
        let model = makeModel()
        model.stop()
        model.acceptBreak()
        model.declineBreak()
        model.dismissSettings()
        expectEqual(model.phase, .idle)

        model.leftClick()
        model.declineBreak()
        expectEqual(model.phase, .studying)
    }

    func runAll() -> Int {
        let tests: [(String, (ModelChecks) -> Void)] = [
            ("testDefaultsAndPersistence", { $0.testDefaultsAndPersistence() }),
            ("testInvalidStoredDurationsFallBackToDefaults", { $0.testInvalidStoredDurationsFallBackToDefaults() }),
            ("testDurationsClampToRange", { $0.testDurationsClampToRange() }),
            ("testRightClickTogglesSettingsAndLeftClickStartsStudy", { $0.testRightClickTogglesSettingsAndLeftClickStartsStudy() }),
            ("testCountdownUsesEndDateAndStopReturnsIdle", { $0.testCountdownUsesEndDateAndStopReturnsIdle() }),
            ("testStudyElapsedOpensBreakPrompt", { $0.testStudyElapsedOpensBreakPrompt() }),
            ("testDeclineBreakResetsToIdle", { $0.testDeclineBreakResetsToIdle() }),
            ("testAcceptBreakThenFinishReturnsIdle", { $0.testAcceptBreakThenFinishReturnsIdle() }),
            ("testStopDuringBreakReturnsIdle", { $0.testStopDuringBreakReturnsIdle() }),
            ("testShortTimersUseSeconds", { $0.testShortTimersUseSeconds() }),
            ("testRipenessMovesFromGreenToRed", { $0.testRipenessMovesFromGreenToRed() }),
            ("testIgnoredActionsDoNotChangePhase", { $0.testIgnoredActionsDoNotChangePhase() }),
        ]
        var failed = 0
        for (name, test) in tests {
            setUp()
            test(self)
            tearDown()
            if failures.isEmpty {
                print("PASS \(name)")
            } else {
                failed += 1
                for failure in failures {
                    print("FAIL \(name): \(failure)")
                }
            }
        }
        return failed
    }

    private func makeModel(
        shortTimers: Bool = false,
        clock: @escaping () -> Date = Date.init
    ) -> PomodoroModel {
        PomodoroModel(
            defaults: defaults,
            shortTimers: shortTimers,
            ticksAutomatically: false,
            clock: clock
        )
    }

    private func expectClose(_ actual: Double, _ expected: Double, line: UInt = #line) {
        if abs(actual - expected) > 0.03 {
            failures.append("line \(line): expected \(expected), got \(actual)")
        }
    }

    private func expectEqual<T: Equatable>(
        _ actual: T,
        _ expected: T,
        line: UInt = #line
    ) {
        if actual != expected {
            failures.append("line \(line): expected \(expected), got \(actual)")
        }
    }

    private func expectNil<T>(
        _ actual: T?,
        line: UInt = #line
    ) {
        if actual != nil {
            failures.append("line \(line): expected nil, got \(String(describing: actual))")
        }
    }
}

#if TEST_RUNNER
@main
enum TestMain {
    static func main() {
        let failed = MainActor.assumeIsolated {
            ModelChecks().runAll()
        }
        if failed != 0 {
            exit(EXIT_FAILURE)
        }
    }
}
#else
final class PomodoroModelTests: XCTestCase {
    func testDefaultsAndPersistence() { run { $0.testDefaultsAndPersistence() } }
    func testInvalidStoredDurationsFallBackToDefaults() { run { $0.testInvalidStoredDurationsFallBackToDefaults() } }
    func testDurationsClampToRange() { run { $0.testDurationsClampToRange() } }
    func testRightClickTogglesSettingsAndLeftClickStartsStudy() { run { $0.testRightClickTogglesSettingsAndLeftClickStartsStudy() } }
    func testCountdownUsesEndDateAndStopReturnsIdle() { run { $0.testCountdownUsesEndDateAndStopReturnsIdle() } }
    func testStudyElapsedOpensBreakPrompt() { run { $0.testStudyElapsedOpensBreakPrompt() } }
    func testDeclineBreakResetsToIdle() { run { $0.testDeclineBreakResetsToIdle() } }
    func testAcceptBreakThenFinishReturnsIdle() { run { $0.testAcceptBreakThenFinishReturnsIdle() } }
    func testStopDuringBreakReturnsIdle() { run { $0.testStopDuringBreakReturnsIdle() } }
    func testShortTimersUseSeconds() { run { $0.testShortTimersUseSeconds() } }
    func testRipenessMovesFromGreenToRed() { run { $0.testRipenessMovesFromGreenToRed() } }
    func testIgnoredActionsDoNotChangePhase() { run { $0.testIgnoredActionsDoNotChangePhase() } }

    private func run(_ body: @MainActor (ModelChecks) -> Void) {
        MainActor.assumeIsolated {
            let checks = ModelChecks()
            checks.setUp()
            body(checks)
            checks.tearDown()
            if !checks.failures.isEmpty {
                XCTFail(checks.failures.joined(separator: "\n"))
            }
        }
    }
}
#endif
