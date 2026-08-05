import Foundation

/// The whole timer. Remaining time is always derived from the wall clock, so
/// drift, sleep and wake are handled for free: sleep through the end of a timer
/// and it fires the moment you come back.
final class TimerEngine: ObservableObject {
    enum Phase { case idle, running, paused, finished }

    static let shared = TimerEngine()

    @Published private(set) var phase: Phase = .idle
    /// Total length of the current timer.
    private(set) var duration: TimeInterval = Prefs.shared.defaultDuration

    /// Called on every phase transition (menu bar / overlay resync).
    var onPhaseChange: ((Phase) -> Void)?
    /// Called once when the timer reaches zero.
    var onFinish: (() -> Void)?

    private var endDate: Date?
    private var pausedRemaining: TimeInterval = 0
    private var finishedAt: Date?
    private var ticker: Timer?

    private static let savedEnd = "runningEndDate"
    private static let savedDuration = "runningDuration"

    /// Pick a running timer back up after a relaunch — quitting Wick, or having
    /// it start at login mid-timer, shouldn't lose the time you had left.
    func restoreIfInterrupted() {
        let d = UserDefaults.standard
        guard let end = d.object(forKey: Self.savedEnd) as? Date else { return }
        let total = d.double(forKey: Self.savedDuration)
        d.removeObject(forKey: Self.savedEnd)
        guard end.timeIntervalSinceNow > 1, total > 0 else { return }
        duration = total
        endDate = end
        set(.running)
        startTicking()
    }

    private func persist() {
        let d = UserDefaults.standard
        if phase == .running, let endDate {
            d.set(endDate, forKey: Self.savedEnd)
            d.set(duration, forKey: Self.savedDuration)
        } else {
            d.removeObject(forKey: Self.savedEnd)
        }
    }

    /// Seconds left, floored at zero.
    var remaining: TimeInterval {
        switch phase {
        case .idle:     return duration
        case .running:  return max(0, endDate?.timeIntervalSinceNow ?? 0)
        case .paused:   return pausedRemaining
        case .finished: return 0
        }
    }

    /// Fraction of the timer already spent, 0…1. Sampled every frame by the
    /// border, so it stays cheap and allocation-free.
    var consumed: Double {
        guard duration > 0 else { return 1 }
        switch phase {
        case .idle:     return 0
        case .finished: return 1
        default:        return min(1, max(0, 1 - remaining / duration))
        }
    }

    // MARK: - Controls

    func start(_ seconds: TimeInterval) {
        duration = max(1, seconds)
        endDate = Date().addingTimeInterval(duration)
        finishedAt = nil
        set(.running)
        startTicking()
    }

    /// Start a timer already part-way through — for looking at a style without
    /// waiting twenty minutes for it to get interesting.
    func start(_ seconds: TimeInterval, at progress: Double) {
        duration = max(1, seconds)
        endDate = Date().addingTimeInterval(duration * (1 - min(0.999, max(0, progress))))
        finishedAt = nil
        set(.running)
        startTicking()
    }

    func pause() {
        guard phase == .running else { return }
        pausedRemaining = remaining
        endDate = nil
        stopTicking()
        set(.paused)
    }

    func resume() {
        guard phase == .paused else { return }
        endDate = Date().addingTimeInterval(pausedRemaining)
        set(.running)
        startTicking()
    }

    func stop() {
        endDate = nil
        finishedAt = nil
        duration = Prefs.shared.defaultDuration
        stopTicking()
        set(.idle)
    }

    /// Add time to a running or paused timer, stretching the total so the ring
    /// grows back instead of jumping.
    func extend(by seconds: TimeInterval) {
        switch phase {
        case .running:
            duration += seconds
            endDate = (endDate ?? Date()).addingTimeInterval(seconds)
        case .paused:
            duration += seconds
            pausedRemaining += seconds
        case .finished:
            start(seconds)
        case .idle:
            start(Prefs.shared.defaultDuration + seconds)
        }
        onPhaseChange?(phase)
    }

    // MARK: - Ticking

    private func startTicking() {
        stopTicking()
        // Only drives the menu bar title and end-of-timer detection; the border
        // animates off a display link.
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        switch phase {
        case .running:
            if remaining <= 0 {
                endDate = nil
                finishedAt = Date()
                set(.finished)
                onFinish?()
            } else {
                onPhaseChange?(phase)  // menu bar title refresh
            }
        case .finished:
            // The finished ring pulses until acknowledged, but not forever.
            if finishedLongEnoughToClear { stop() }
        case .idle, .paused:
            stopTicking()
        }
    }

    /// The finished ring pulses until acknowledged, but shouldn't glow forever.
    var finishedLongEnoughToClear: Bool {
        guard let f = finishedAt else { return false }
        return Date().timeIntervalSince(f) > 120
    }

    private func set(_ p: Phase) {
        phase = p
        persist()
        onPhaseChange?(p)
    }
}
