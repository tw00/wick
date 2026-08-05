import SwiftUI
import AppKit

/// Wick lives in the menu bar only — no dock icon, no windows unless you ask for
/// settings. The delegate wires the timer to the border, the chime, Focus and the
/// app nudge, and owns nothing else.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine = TimerEngine.shared
    private var menuBar: MenuBarController!
    private var overlay: OverlayController!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = OverlayController(engine: engine)
        menuBar = MenuBarController(engine: engine)
        menuBar.onShowSettings = { [weak self] in self?.showSettings() }

        engine.onPhaseChange = { [weak self] phase in
            guard let self else { return }
            self.menuBar.refresh()
            self.overlay.sync()
            switch phase {
            case .running:
                if Prefs.shared.focusWhileRunning { FocusMode.activate() }
                AppNudge.shared.start()
                Notify.requestIfNeeded()
            case .idle, .paused, .finished:
                if Prefs.shared.focusWhileRunning { FocusMode.deactivate() }
                AppNudge.shared.stop()
            }
        }
        engine.onFinish = { [weak self] in
            Chime.play()
            Notify.timerFinished(after: self?.engine.duration ?? 0)
        }

        Hotkeys.shared.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .toggle: self.run(command: "toggle", spec: nil)
            case .stop:   self.engine.stop()
            }
        }
        Hotkeys.shared.sync()
        NotificationCenter.default.addObserver(forName: .wickPrefsChanged, object: nil,
                                               queue: .main) { _ in Hotkeys.shared.sync() }

        FocusMode.refreshAvailability()
        engine.restoreIfInterrupted()
        handleLaunchArguments()
    }

    // MARK: - Scripting
    //
    // Two ways in from the outside, so Wick fits in a Raycast script or a
    // Shortcut: `open "wick://start?d=25m"` on a running copy, or
    // `open -a Wick --args --start 25m` to launch straight into a timer.
    // Commands: start (d=…), pause, resume, toggle, stop, add (d=…).

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "wick" {
            let command = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            let spec = items?.first { $0.name == "d" }?.value
            // ?at=0.5 starts the timer half spent — handy for looking at a style.
            let at = items?.first { $0.name == "at" }?.value.flatMap(Double.init)
            run(command: command, spec: spec, at: at)
        }
    }

    private func handleLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--start") else { return }
        let spec = args.count > i + 1 ? args[i + 1] : nil
        run(command: "start", spec: spec)
    }

    private func run(command: String, spec: String?, at progress: Double? = nil) {
        let seconds = spec.flatMap(Duration.parse)
        switch command {
        case "start":
            if let progress {
                engine.start(seconds ?? Prefs.shared.defaultDuration, at: progress)
            } else {
                engine.start(seconds ?? Prefs.shared.defaultDuration)
            }
        case "pause":  engine.pause()
        case "resume": engine.resume()
        case "stop":   engine.stop()
        case "add":    engine.extend(by: seconds ?? 5 * 60)
        case "settings": showSettings()
        case "toggle":
            switch engine.phase {
            case .running: engine.pause()
            case .paused:  engine.resume()
            default:       engine.start(seconds ?? Prefs.shared.defaultDuration)
            }
        default:
            NSLog("Wick: unknown command '%@'", command)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if Prefs.shared.focusWhileRunning { FocusMode.deactivate() }
        AppNudge.shared.stop()
    }

    private func showSettings() {
        if let w = settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }
        let vc = NSHostingController(rootView: SettingsView())
        vc.preferredContentSize = NSSize(width: 480, height: 640)
        let w = NSWindow(contentViewController: vc)
        w.title = "Wick Settings"
        w.styleMask.remove(.resizable)
        w.setContentSize(NSSize(width: 480, height: 640))
        w.isReleasedWhenClosed = false
        w.center()
        settingsWindow = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

@main
struct WickApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
