import AppKit

/// macOS doesn't let an app toggle a Focus mode directly, so Wick drives two
/// Shortcuts you own. Make them once in the Shortcuts app and Wick will run
/// them at the start and end of every timer.
enum FocusMode {
    static let onShortcut = "Wick Focus On"
    static let offShortcut = "Wick Focus Off"

    /// Cached result of the last `shortcuts list` check.
    private(set) static var isConfigured = false

    static func refreshAvailability(_ done: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .utility).async {
            let list = run("/usr/bin/shortcuts", ["list"]) ?? ""
            let ok = list.contains(onShortcut) && list.contains(offShortcut)
            DispatchQueue.main.async {
                isConfigured = ok
                done?()
            }
        }
    }

    static func activate() { runShortcut(onShortcut) }
    static func deactivate() { runShortcut(offShortcut) }

    private static func runShortcut(_ name: String) {
        guard isConfigured else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            _ = run("/usr/bin/shortcuts", ["run", name])
        }
    }

    static var setupInstructions: String {
        """
        Wick can turn a Focus mode on while the timer runs, using two Shortcuts \
        you create once:

        1. Open Shortcuts → new shortcut → add the "Set Focus" action.
        2. Set it to turn a Focus (e.g. Do Not Disturb) On. Name it exactly:
           \(onShortcut)
        3. Duplicate it, switch the action to Off, and name it exactly:
           \(offShortcut)

        Then tick "Focus while the timer runs" here. Wick runs the first when a \
        timer starts and the second when it ends, is stopped, or paused.
        """
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch {
            NSLog("Wick: %@ failed: %@", path, error.localizedDescription)
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}

/// Soft app blocking. There is no way to hard-block an app without a system
/// extension, so Wick does the next best thing: it hides what you shouldn't be
/// in and hides it again if you reach for it mid-timer. A nudge, not a wall.
///
/// Either say which apps are allowed and everything else goes away, or list the
/// few that do. Nothing happens at all if the list is empty.
final class AppNudge {
    static let shared = AppNudge()

    /// Never hidden: Wick, and the Finder, which you need to dig yourself out.
    private static let exempt: Set<String> = ["com.apple.finder"]

    private var active = false
    private var observer: Any?
    /// In allow mode, whatever you were working in when the timer started counts
    /// as allowed for that timer — starting a timer shouldn't sweep away the
    /// thing you're about to work on.
    private var sessionAllowed: Set<String> = []

    func start() {
        guard !active, !Prefs.shared.listedApps.isEmpty else { return }
        active = true
        sessionAllowed.removeAll()
        if Prefs.shared.nudgeMode == .allow,
           let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            sessionAllowed.insert(front)
        }
        for app in NSWorkspace.shared.runningApplications where shouldHide(app) { app.hide() }

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] note in
                guard let self, self.active,
                      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      self.shouldHide(app)
                else { return }
                // Let the activation settle before pushing it back down.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { app.hide() }
            }
    }

    func stop() {
        active = false
        sessionAllowed.removeAll()
        if let o = observer { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        observer = nil
    }

    private func shouldHide(_ app: NSRunningApplication) -> Bool {
        guard app.activationPolicy == .regular,
              let id = app.bundleIdentifier,
              id != Bundle.main.bundleIdentifier,
              !Self.exempt.contains(id),
              !sessionAllowed.contains(id)
        else { return false }

        let list = Prefs.shared.listedApps
        guard !list.isEmpty else { return false }
        return Prefs.shared.nudgeMode == .allow ? !list.contains(id) : list.contains(id)
    }

    /// Apps worth offering in the settings list: everything with a Dock icon,
    /// minus Wick itself.
    static func candidateApps() -> [(name: String, id: String)] {
        let mine = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != mine }
            .compactMap { app in
                guard let id = app.bundleIdentifier, let name = app.localizedName else { return nil }
                return (name, id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func displayName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url.deletingPathExtension().lastPathComponent
        }
        return bundleID
    }
}
