import Foundation
import Observation

enum PomodoroPhase: Equatable {
    case idle
    case settings
    case studying
    case breakPrompt
    case breaking
}

@MainActor
@Observable
final class PomodoroModel {
    static let studyKey = "studyMinutes"
    static let breakKey = "breakMinutes"
    static let studyRange = 1...180
    static let breakRange = 1...60
    static let defaultStudyMinutes = 25
    static let defaultBreakMinutes = 5
    static let shortTimerSeconds: TimeInterval = 5

    private(set) var phase: PomodoroPhase = .idle
    private(set) var endDate: Date?
    private(set) var now: Date
    private(set) var countdownRevealed = false
    private(set) var sessionLength: TimeInterval = 0
    var studyMinutes: Int {
        didSet { persist(studyMinutes, range: Self.studyRange, key: Self.studyKey, write: { studyMinutes = $0 }) }
    }
    var breakMinutes: Int {
        didSet { persist(breakMinutes, range: Self.breakRange, key: Self.breakKey, write: { breakMinutes = $0 }) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let shortTimers: Bool
    @ObservationIgnored private let ticksAutomatically: Bool
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var phaseBeforeSettings: PomodoroPhase?
    @ObservationIgnored private var hoveringTimer = false
    @ObservationIgnored private var suppressHoverReveal = false
    @ObservationIgnored private var collapseWork: DispatchWorkItem?

    init(
        defaults: UserDefaults = .standard,
        shortTimers: Bool = false,
        ticksAutomatically: Bool = true,
        clock: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.shortTimers = shortTimers
        self.ticksAutomatically = ticksAutomatically
        self.clock = clock
        self.now = clock()
        self.studyMinutes = Self.stored(
            defaults,
            key: Self.studyKey,
            range: Self.studyRange,
            fallback: Self.defaultStudyMinutes
        )
        self.breakMinutes = Self.stored(
            defaults,
            key: Self.breakKey,
            range: Self.breakRange,
            fallback: Self.defaultBreakMinutes
        )
    }

    var remainingText: String {
        let seconds = remainingSeconds
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    var remainingSeconds: Int {
        guard let endDate else { return 0 }
        let remaining = endDate.timeIntervalSince(now)
        guard remaining > 0 else { return 0 }
        return Int(remaining.rounded(.down))
    }

    /// 0 is an unripe green tomato, 1 is the ripe red one. Only a study session moves this.
    var ripeness: Double {
        guard phase == .studying, sessionLength > 0, let endDate else { return 1 }
        let elapsed = sessionLength - endDate.timeIntervalSince(now)
        return min(1, max(0, elapsed / sessionLength))
    }

    func leftClick() {
        guard phase == .idle else { return }
        begin(.studying, seconds: duration(minutes: studyMinutes))
    }

    func rightClick() {
        if phase == .settings {
            closeSettings()
        } else {
            phaseBeforeSettings = phase
            phase = .settings
        }
    }

    func dismissSettings() {
        guard phase == .settings else { return }
        closeSettings()
    }

    private func closeSettings() {
        phase = phaseBeforeSettings ?? .idle
        phaseBeforeSettings = nil
    }

    func setTimerHovered(_ hovering: Bool) {
        hoveringTimer = hovering
        guard phase == .studying, !suppressHoverReveal else { return }
        countdownRevealed = hovering
    }

    func stop() {
        guard phase == .studying || phase == .breaking else { return }
        cancelTimer()
        hideCountdown()
        phase = .idle
    }

    func acceptBreak() {
        guard phase == .breakPrompt else { return }
        begin(.breaking, seconds: duration(minutes: breakMinutes))
    }

    func declineBreak() {
        guard phase == .breakPrompt else { return }
        phase = .idle
    }

    func tick(at date: Date) {
        now = date
        guard let endDate, date >= endDate else { return }
        finishCountdown()
    }

    private func begin(_ next: PomodoroPhase, seconds: TimeInterval) {
        let start = clock()
        now = start
        sessionLength = seconds
        endDate = start.addingTimeInterval(seconds)
        phase = next
        if next == .studying, ticksAutomatically {
            presentCountdownBriefly()
        } else {
            hideCountdown()
        }
        startTickerIfNeeded()
    }

    private func presentCountdownBriefly() {
        collapseWork?.cancel()
        countdownRevealed = true
        suppressHoverReveal = true
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.suppressHoverReveal = false
            if self.phase == .studying {
                self.countdownRevealed = false
            }
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.78, execute: work)
    }

    private func hideCountdown() {
        collapseWork?.cancel()
        collapseWork = nil
        suppressHoverReveal = false
        hoveringTimer = false
        countdownRevealed = false
    }

    private func finishCountdown() {
        let finished = phase
        cancelTimer()
        hideCountdown()
        switch finished {
        case .studying:
            phase = .breakPrompt
        case .breaking:
            phase = .idle
        default:
            break
        }
    }

    private func cancelTimer() {
        ticker?.invalidate()
        ticker = nil
        endDate = nil
    }

    private func startTickerIfNeeded() {
        guard ticksAutomatically else { return }
        ticker?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick(at: Date())
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func duration(minutes: Int) -> TimeInterval {
        shortTimers ? Self.shortTimerSeconds : TimeInterval(minutes * 60)
    }

    private func persist(_ value: Int, range: ClosedRange<Int>, key: String, write: (Int) -> Void) {
        let clamped = Self.clamp(value, to: range)
        if clamped != value {
            write(clamped)
        }
        defaults.set(clamped, forKey: key)
    }

    private static func stored(_ defaults: UserDefaults, key: String, range: ClosedRange<Int>, fallback: Int) -> Int {
        guard let value = defaults.object(forKey: key) as? Int, range.contains(value) else {
            return fallback
        }
        return value
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(range.upperBound, max(range.lowerBound, value))
    }
}
