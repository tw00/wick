import AppKit

/// The menu bar item: remaining time as the title, everything else in the menu.
final class MenuBarController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let engine: TimerEngine
    private static let presets: [TimeInterval] = [5, 10, 15, 20, 25, 30, 45, 60].map { $0 * 60 }

    var onShowSettings: (() -> Void)?

    init(engine: TimerEngine) {
        self.engine = engine
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Wick")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        refresh()
    }

    // MARK: - Title

    func refresh() {
        guard let button = item.button else { return }
        switch engine.phase {
        case .idle:
            button.title = ""
            button.image = symbol("timer")
        case .running:
            button.title = " " + Format.clock(engine.remaining)
            button.image = symbol("timer")
        case .paused:
            button.title = " " + Format.clock(engine.remaining)
            button.image = symbol("pause.circle")
        case .finished:
            button.title = " done"
            button.image = symbol("bell.fill")
        }
    }

    private func symbol(_ name: String) -> NSImage? {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "Wick")
        img?.isTemplate = true
        return img
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header: String
        switch engine.phase {
        case .idle:     header = "No timer running"
        case .running:  header = "\(Format.clock(engine.remaining)) left of \(Format.human(engine.duration))"
        case .paused:   header = "Paused — \(Format.clock(engine.remaining)) left"
        case .finished: header = "Time's up"
        }
        let head = NSMenuItem(title: header, action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(head)
        menu.addItem(.separator())

        switch engine.phase {
        case .running:
            add(menu, "Pause", #selector(pause))
            add(menu, "Stop", #selector(stop))
            add(menu, "Add 5 min", #selector(extend))
        case .paused:
            add(menu, "Resume", #selector(resume))
            add(menu, "Stop", #selector(stop))
        case .finished:
            add(menu, "Dismiss", #selector(stop))
        case .idle:
            break
        }
        if engine.phase != .idle { menu.addItem(.separator()) }

        let startTitle = NSMenuItem(title: engine.phase == .idle ? "Start" : "Restart with", action: nil,
                                    keyEquivalent: "")
        startTitle.isEnabled = false
        menu.addItem(startTitle)
        for d in Self.presets {
            let mi = add(menu, "  " + Format.human(d), #selector(startPreset(_:)))
            mi.representedObject = d
            mi.state = abs(Prefs.shared.defaultDuration - d) < 1 ? .on : .off
        }
        add(menu, "  Custom…", #selector(custom))
        menu.addItem(.separator())

        let styleMenu = NSMenu()
        for (heading, styles) in [("Calm", RingStyle.calm), ("Playful", RingStyle.playful)] {
            let head = NSMenuItem(title: heading, action: nil, keyEquivalent: "")
            head.isEnabled = false
            styleMenu.addItem(head)
            for s in styles {
                let mi = NSMenuItem(title: "  " + s.label, action: #selector(pickStyle(_:)),
                                    keyEquivalent: "")
                mi.target = self
                mi.representedObject = s.rawValue
                mi.state = Prefs.shared.style == s ? .on : .off
                styleMenu.addItem(mi)
            }
        }
        let styleItem = NSMenuItem(title: "Style", action: nil, keyEquivalent: "")
        styleItem.submenu = styleMenu
        menu.addItem(styleItem)

        let widthMenu = NSMenu()
        for weight in BorderWeight.allCases {
            let mi = NSMenuItem(title: weight.label, action: #selector(pickWidth(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = weight.px
            mi.state = abs(Prefs.shared.thickness - weight.px) < 0.5 ? .on : .off
            widthMenu.addItem(mi)
        }
        let widthItem = NSMenuItem(title: "Width", action: nil, keyEquivalent: "")
        widthItem.submenu = widthMenu
        menu.addItem(widthItem)

        let soundMenu = NSMenu()
        let off = NSMenuItem(title: "Off", action: #selector(pickSound(_:)), keyEquivalent: "")
        off.target = self
        off.representedObject = ""
        off.state = Prefs.shared.soundName.isEmpty ? .on : .off
        soundMenu.addItem(off)
        soundMenu.addItem(.separator())
        for name in Chime.available {
            let mi = NSMenuItem(title: name, action: #selector(pickSound(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = name
            mi.state = Prefs.shared.soundName == name ? .on : .off
            soundMenu.addItem(mi)
        }
        let soundItem = NSMenuItem(title: "Sound", action: nil, keyEquivalent: "")
        soundItem.submenu = soundMenu
        menu.addItem(soundItem)

        let focus = add(menu, FocusMode.isConfigured ? "Focus While Running" : "Set Up Focus…",
                        FocusMode.isConfigured ? #selector(toggleFocus) : #selector(focusHelp))
        focus.state = (FocusMode.isConfigured && Prefs.shared.focusWhileRunning) ? .on : .off

        menu.addItem(.separator())
        add(menu, "Settings…", #selector(settings), key: ",")
        add(menu, "About Wick", #selector(about))
        add(menu, "Quit Wick", #selector(quit), key: "q")
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = self
        menu.addItem(mi)
        return mi
    }

    // MARK: - Actions

    @objc private func startPreset(_ sender: NSMenuItem) {
        guard let d = sender.representedObject as? TimeInterval else { return }
        Prefs.shared.defaultDuration = d
        engine.start(d)
    }

    @objc private func custom() {
        let alert = NSAlert()
        alert.messageText = "Start a timer"
        alert.informativeText = "How long? e.g. 25, 45m, 1h30, 90s"
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.placeholderString = "25"
        alert.accessoryView = field
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn,
              let seconds = Duration.parse(field.stringValue) else { return }
        Prefs.shared.defaultDuration = seconds
        engine.start(seconds)
    }

    @objc private func pause()  { engine.pause() }
    @objc private func resume() { engine.resume() }
    @objc private func stop()   { engine.stop() }
    @objc private func extend() { engine.extend(by: 5 * 60) }

    @objc private func pickStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let s = RingStyle(rawValue: raw) else { return }
        Prefs.shared.style = s
    }

    @objc private func pickWidth(_ sender: NSMenuItem) {
        guard let px = sender.representedObject as? Double else { return }
        Prefs.shared.thickness = px
    }

    @objc private func pickSound(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        Prefs.shared.soundName = name
        Chime.play(name: name, repeats: 1)
    }

    @objc private func toggleFocus() {
        Prefs.shared.focusWhileRunning.toggle()
        if engine.phase == .running {
            Prefs.shared.focusWhileRunning ? FocusMode.activate() : FocusMode.deactivate()
        }
    }

    @objc private func focusHelp() {
        FocusMode.refreshAvailability()
        let alert = NSAlert()
        alert.messageText = "Focus needs two Shortcuts"
        alert.informativeText = FocusMode.setupInstructions
        alert.addButton(withTitle: "Open Shortcuts")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    @objc private func settings() { onShowSettings?() }

    @objc private func about() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(
                string: "A timer that burns down the edge of your screen.",
                attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)])
        ])
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
