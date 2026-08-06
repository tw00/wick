import AppKit

/// The two things Wick can install outside its own bundle: a Claude Code skill,
/// so Claude can set a timer when you ask it to, and a set of Raycast script
/// commands. Both are plain files, so installing and removing them is honest —
/// nothing is registered anywhere else, and Remove leaves nothing behind.
enum Integrations {

    // MARK: - Claude Code skill

    static var skillDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/skills/focus-timer", isDirectory: true)
    }

    static var skillInstalled: Bool {
        FileManager.default.fileExists(atPath: skillDirectory.appendingPathComponent("SKILL.md").path)
    }

    static func installSkill() throws {
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try skillText.write(to: skillDirectory.appendingPathComponent("SKILL.md"),
                            atomically: true, encoding: .utf8)
    }

    static func removeSkill() throws {
        guard FileManager.default.fileExists(atPath: skillDirectory.path) else { return }
        try FileManager.default.removeItem(at: skillDirectory)
    }

    // MARK: - Raycast script commands

    /// Raycast keeps its script directories in its own database rather than in
    /// readable preferences, so Wick can't add one for you. It writes the
    /// commands somewhere stable instead and shows you the folder.
    static var scriptsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Wick/Raycast Scripts", isDirectory: true)
    }

    static var scriptsInstalled: Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: scriptsDirectory.path)) ?? []
        return names.contains { $0.hasSuffix(".sh") }
    }

    static var raycastInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.raycast.macos") != nil
    }

    static func installScripts() throws {
        try FileManager.default.createDirectory(at: scriptsDirectory, withIntermediateDirectories: true)
        for script in scripts {
            let url = scriptsDirectory.appendingPathComponent(script.file)
            try script.body.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
    }

    static func removeScripts() throws {
        guard FileManager.default.fileExists(atPath: scriptsDirectory.path) else { return }
        try FileManager.default.removeItem(at: scriptsDirectory)
    }

    static func revealScripts() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: scriptsDirectory.path)
    }

    private struct Script {
        let file: String
        let body: String
    }

    private static let scripts: [Script] = [
        Script(file: "wick-start.sh", body: command(
            title: "Start Timer", icon: "⏱️", description: "Start a Wick timer.",
            argument: #"{ "type": "text", "placeholder": "25m", "optional": true }"#,
            run: #"open "wick://start?d=${1:-25m}""#)),
        Script(file: "wick-toggle.sh", body: command(
            title: "Pause or Resume Timer", icon: "⏯️",
            description: "Pause a running Wick timer, or resume a paused one.",
            argument: nil, run: #"open "wick://toggle""#)),
        Script(file: "wick-add.sh", body: command(
            title: "Add Time", icon: "➕", description: "Stretch the running Wick timer.",
            argument: #"{ "type": "text", "placeholder": "5m", "optional": true }"#,
            run: #"open "wick://add?d=${1:-5m}""#)),
        Script(file: "wick-stop.sh", body: command(
            title: "Stop Timer", icon: "⏹️", description: "Clear the timer and the border.",
            argument: nil, run: #"open "wick://stop""#)),
    ]

    private static func command(title: String, icon: String, description: String,
                                argument: String?, run: String) -> String {
        var lines = [
            "#!/bin/bash",
            "",
            "# @raycast.schemaVersion 1",
            "# @raycast.title \(title)",
            "# @raycast.mode silent",
            "# @raycast.packageName Wick",
            "# @raycast.icon \(icon)",
        ]
        if let argument { lines.append("# @raycast.argument1 \(argument)") }
        lines += [
            "# @raycast.description \(description)",
            "",
            run,
            "",
        ]
        return lines.joined(separator: "\n")
    }

    // MARK: - Skill text

    private static let skillText = """
    ---
    name: focus-timer
    description: Set, extend, pause or stop a focus timer on this Mac using Wick, \
    the screen-border timer. Use whenever a timer, a focus block or a pomodoro is \
    asked for — "give me 25 minutes", "time me", "remind me in an hour to stop" — \
    or when a task being handed back would sensibly be timeboxed.
    ---

    # Focus timer (Wick)

    Wick draws a line around the edge of the screen that shortens as the time runs
    out, and chimes when it's done. Drive it with `open` and a URL — no window
    appears, nothing steals focus.

    ## Commands

    ```bash
    open "wick://start?d=25m"    # start (accepts 25, 45m, 1h30, 90s)
    open "wick://toggle"         # pause a running timer, resume a paused one
    open "wick://add?d=10m"      # stretch the running timer
    open "wick://stop"           # clear the timer and the border
    open "wick://settings"       # open Settings
    ```

    Wick launches itself if it isn't running.

    ## How to use it

    - **Just start it.** A timer is reversible and silent to set up — don't ask for
      confirmation, set it and say so in one line.
    - **Pick a length from the work, not a default.** A quick review is 10 minutes;
      a deep piece of drafting is 45–60. If a length is named, use exactly that.
    - **Never chain timers or set a second one on top.** One timer runs at a time;
      starting another replaces it.
    - **Don't stop a running timer unless asked** — it may have been started by hand.

    ## Reporting back

    One line: what's set and until when. "25 min — border's running, chime at 4:05."
    Don't explain the tool.

    ## Styles

    The border style is a setting rather than a command:
    `defaults write com.tw.wick style -string <name>`, then restart Wick. Calm ones
    are `plain`, `fade`, `pulse`, `split`, `ticks`, `tide`, `level`; playful ones are
    `fuse`, `snake`, `aurora`.

    """
}
