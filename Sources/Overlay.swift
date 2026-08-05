import AppKit

/// A borderless, click-through window pinned over one screen. It sits above
/// full-screen apps and the menu bar, and never takes focus.
final class OverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        displaysWhenScreenProfileChanges = true
        contentView = BorderView(frame: NSRect(origin: .zero, size: screen.frame.size))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    var border: BorderView? { contentView as? BorderView }
}

/// Keeps one overlay per participating screen alive, and in sync with the timer
/// and the display configuration.
final class OverlayController {
    private var windows: [OverlayWindow] = []
    private let engine: TimerEngine

    init(engine: TimerEngine) {
        self.engine = engine
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(prefsChanged), name: .wickPrefsChanged, object: nil)
        // Coming back from sleep, the overlay can be left behind other windows.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(screensChanged),
            name: NSWorkspace.didWakeNotification, object: nil)
    }

    /// Show or hide the border to match the timer's phase.
    func sync() {
        let visible = engine.phase != .idle
        guard visible else { teardown(); return }

        let screens = Prefs.shared.allDisplays
            ? NSScreen.screens
            : [NSScreen.main].compactMap { $0 }

        if windows.count != screens.count { teardown() }

        if windows.isEmpty {
            windows = screens.map { screen in
                let w = OverlayWindow(screen: screen)
                w.border?.stateProvider = { [engine] in
                    RingState(consumed: CGFloat(engine.consumed), phase: engine.phase,
                              duration: engine.duration)
                }
                return w
            }
        }

        for (w, screen) in zip(windows, screens) {
            w.setFrame(screen.frame, display: false)
            w.border?.cornerRadius = CGFloat(Screens.cornerRadius(for: screen))
            w.border?.setFrameSize(screen.frame.size)
            w.orderFrontRegardless()
        }
    }

    func redraw() {
        windows.forEach { $0.border?.invalidateAll() }
    }

    private func teardown() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    @objc private func screensChanged() {
        teardown()
        sync()
    }

    @objc private func prefsChanged() {
        sync()
        redraw()
    }
}
