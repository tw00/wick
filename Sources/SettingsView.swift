import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    /// The window is built at exactly this size; nothing here asks to resize it.
    static let size = NSSize(width: 470, height: 540)

    var body: some View {
        TabView {
            BorderSettings()
                .tabItem { Label("Border", systemImage: "rectangle.dashed") }
            TimerSettings()
                .tabItem { Label("Timer", systemImage: "timer") }
            FocusSettings()
                .tabItem { Label("Focus", systemImage: "moon") }
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Border

private struct BorderSettings: View {
    @ObservedObject private var prefs = Prefs.shared

    /// What the border will actually round its corners to, so the sample below
    /// matches the screen rather than guessing.
    private var corners: Screens.Corners {
        prefs.cornersAuto ? Screens.autoCornersForMain() : .uniform(prefs.cornerRadius)
    }

    var body: some View {
        Form {
            Section {
                Picker("Style", selection: $prefs.style) {
                    Section("Calm") { ForEach(RingStyle.calm) { Text($0.label).tag($0) } }
                    Section("Playful") { ForEach(RingStyle.playful) { Text($0.label).tag($0) } }
                }
                Text(prefs.style.blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let scale: CGFloat = 0.5
                let shape = UnevenRoundedRectangle(
                    topLeadingRadius: CGFloat(corners.top) * scale,
                    bottomLeadingRadius: CGFloat(corners.bottom) * scale,
                    bottomTrailingRadius: CGFloat(corners.bottom) * scale,
                    topTrailingRadius: CGFloat(corners.top) * scale)
                RingPreview(scale: scale, corners: corners)
                    .frame(height: 108)
                    .background(shape.fill(Color.black.opacity(0.3)))
                    .clipShape(shape)
            }

            Section("Thickness") {
                Picker("", selection: $prefs.thickness) {
                    ForEach(BorderWeight.allCases) { Text($0.label).tag($0.px) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                HStack {
                    Slider(value: $prefs.thickness, in: 1...24, step: 1)
                    Text("\(Int(prefs.thickness)) px").monospacedDigit()
                        .frame(width: 46, alignment: .trailing)
                }
            }

            Section("Shape") {
                Toggle("Match each screen's corners", isOn: Binding(
                    get: { prefs.cornersAuto },
                    set: { prefs.cornerRadius = $0 ? -1 : Screens.autoCornersForMain().top }))
                if prefs.cornersAuto {
                    Text("A MacBook rounds the top two corners to \(Int(Screens.builtInTopRadius)) px and leaves the bottom square. External monitors stay square.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack {
                        Slider(value: $prefs.cornerRadius, in: 0...48, step: 1) { Text("Corners") }
                        Text("\(Int(prefs.cornerRadius)) px").monospacedDigit()
                            .frame(width: 46, alignment: .trailing)
                    }
                }
                Toggle("Show on all displays", isOn: $prefs.allDisplays)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Timer

private struct TimerSettings: View {
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        Form {
            Section {
                Picker("Default length", selection: $prefs.defaultDuration) {
                    ForEach([5.0, 10, 15, 20, 25, 30, 45, 60], id: \.self) { m in
                        Text(Format.human(m * 60)).tag(m * 60)
                    }
                }
                Text("What the menu bar starts with, and what a bare wick://start uses.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("When time's up") {
                HStack {
                    Picker("Sound", selection: $prefs.soundName) {
                        Text("Off").tag("")
                        Divider()
                        ForEach(Chime.available, id: \.self) { Text($0).tag($0) }
                    }
                    Button("Test") { Chime.play(repeats: 1) }
                        .disabled(prefs.soundName.isEmpty)
                }
                Stepper("Repeat \(prefs.soundRepeats)×", value: $prefs.soundRepeats, in: 1...6)
                    .disabled(prefs.soundName.isEmpty)
                Text("The border pulses red until you dismiss it, or for two minutes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Focus

private struct FocusSettings: View {
    @ObservedObject private var prefs = Prefs.shared
    @State private var focusReady = FocusMode.isConfigured

    var body: some View {
        Form {
            Section("macOS Focus") {
                Toggle("Turn on Focus while the timer runs", isOn: $prefs.focusWhileRunning)
                    .disabled(!focusReady)
                if focusReady {
                    Label("Shortcuts found", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Needs two Shortcuts named “\(FocusMode.onShortcut)” and “\(FocusMode.offShortcut)”.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("How…") { showFocusHelp() }
                        Button("Check Again") {
                            FocusMode.refreshAvailability { focusReady = FocusMode.isConfigured }
                        }
                    }
                }
            }

            Section("Distraction nudge") {
                Picker("While the timer runs", selection: $prefs.nudgeMode) {
                    ForEach(NudgeMode.allCases) { Text($0.label).tag($0) }
                }
                Text(prefs.nudgeMode == .allow
                     ? "Everything else is hidden, and hidden again if you switch to it. Whatever you were working in when the timer started stays. An empty list does nothing."
                     : "These are hidden, and hidden again if you open one. A nudge, not a lock.")
                    .font(.caption).foregroundStyle(.secondary)

                ForEach(prefs.listedApps, id: \.self) { id in
                    HStack {
                        Text(AppNudge.displayName(for: id))
                        Spacer()
                        Button {
                            prefs.listedApps.removeAll { $0 == id }
                        } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                HStack {
                    Menu("Add Running App") {
                        ForEach(AppNudge.candidateApps().filter { !prefs.listedApps.contains($0.id) },
                                id: \.id) { app in
                            Button(app.name) { prefs.listedApps.append(app.id) }
                        }
                    }
                    .frame(width: 170)
                    Button("Choose…") { chooseApp() }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { FocusMode.refreshAvailability { focusReady = FocusMode.isConfigured } }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier,
                  !prefs.listedApps.contains(id) else { continue }
            prefs.listedApps.append(id)
        }
    }

    private func showFocusHelp() {
        let alert = NSAlert()
        alert.messageText = "Focus needs two Shortcuts"
        alert.informativeText = FocusMode.setupInstructions
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject private var prefs = Prefs.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    @State private var skillInstalled = Integrations.skillInstalled
    @State private var scriptsInstalled = Integrations.scriptsInstalled
    @State private var integrationError: String?

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private static let urls: [(what: String, url: String)] = [
        ("Start a timer",   "wick://start?d=25m"),
        ("Pause or resume", "wick://toggle"),
        ("Add time",        "wick://add?d=10m"),
        ("Stop",            "wick://stop"),
    ]

    var body: some View {
        Form {
            Section {
                Toggle("Launch Wick at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.orange)
                }
                Toggle("Notify when the timer ends", isOn: $prefs.notifyOnFinish)
            }

            Section("Global shortcuts") {
                Toggle("Enable shortcuts", isOn: $prefs.hotkeysEnabled)
                ShortcutField(title: "Start, pause, resume", spec: $prefs.toggleHotkey)
                    .disabled(!prefs.hotkeysEnabled)
                ShortcutField(title: "Stop", spec: $prefs.stopHotkey)
                    .disabled(!prefs.hotkeysEnabled)
                Text("Work anywhere, no Accessibility permission needed. If a combination does nothing, another app already owns it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Integrations") {
                IntegrationRow(
                    name: "Claude Code skill",
                    detail: "Lets Claude start a timer when you ask it to. Written to ~/.claude/skills/focus-timer.",
                    installed: skillInstalled,
                    install: { try Integrations.installSkill() },
                    remove: { try Integrations.removeSkill() },
                    refresh: { skillInstalled = Integrations.skillInstalled })

                IntegrationRow(
                    name: "Raycast commands",
                    detail: scriptsInstalled
                        ? "Add the folder once in Raycast → Extensions → Script Commands."
                        : "Start, pause, add time and stop, as Raycast script commands.",
                    installed: scriptsInstalled,
                    install: { try Integrations.installScripts(); Integrations.revealScripts() },
                    remove: { try Integrations.removeScripts() },
                    refresh: { scriptsInstalled = Integrations.scriptsInstalled })

                if scriptsInstalled {
                    Button("Show Script Folder") { Integrations.revealScripts() }
                        .font(.caption)
                }
                if let integrationError {
                    Text(integrationError).font(.caption).foregroundStyle(.orange)
                }
            }

            Section("Scripting") {
                ForEach(Self.urls, id: \.url) { row in
                    LabeledContent(row.what) {
                        Text(row.url)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                Text("Open any of these from a script, a Shortcut or Raycast. Durations accept 25, 45m, 1h30 or 90s.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Version", value: version)
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister()
            launchError = nil
        } catch {
            launchError = "Couldn't change login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// One installable extra: what it is, whether it's there, and the one button
/// that changes that.
private struct IntegrationRow: View {
    let name: String
    let detail: String
    let installed: Bool
    let install: () throws -> Void
    let remove: () throws -> Void
    let refresh: () -> Void

    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(name, systemImage: installed ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(installed ? Color.green : Color.secondary)
                Spacer()
                Button(installed ? "Remove" : "Install") {
                    do {
                        try installed ? remove() : install()
                        error = nil
                    } catch {
                        self.error = error.localizedDescription
                    }
                    refresh()
                }
            }
            Text(error ?? detail)
                .font(.caption)
                .foregroundStyle(error == nil ? Color.secondary : Color.orange)
        }
    }
}

/// Click, then press the combination you want. A local event monitor is enough —
/// the settings window is key while you're recording.
private struct ShortcutField: View {
    let title: String
    @Binding var spec: HotkeySpec

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button(recording ? "Press keys…" : (spec.isSet ? spec.label : "Set…")) {
                recording ? stop() : start()
            }
            .frame(minWidth: 96)
            Button {
                spec = .unset
            } label: { Image(systemName: "xmark.circle") }
                .buttonStyle(.borderless)
                .disabled(!spec.isSet)
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }          // Escape cancels
            if let captured = HotkeySpec.from(event: event) {
                spec = captured
                stop()
            }
            return nil                                             // swallow either way
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

// MARK: - Live sample

/// A small looping sample of the chosen style, so you can see what you're
/// picking without starting a timer.
private struct RingPreview: NSViewRepresentable {
    var scale: CGFloat
    /// Unscaled corner radii; the view applies `scale` itself, so these match
    /// the numbers in the settings below.
    var corners: Screens.Corners

    func makeNSView(context: Context) -> BorderView {
        let v = BorderView(frame: .zero)
        let start = Date()
        v.stateProvider = {
            // Eight second loop over a pretend three minute timer, so Minutes
            // has ticks to show.
            let t = Date().timeIntervalSince(start).truncatingRemainder(dividingBy: 8) / 8
            return RingState(consumed: CGFloat(t), phase: .running, duration: 180)
        }
        return v
    }

    func updateNSView(_ view: BorderView, context: Context) {
        view.previewScale = scale
        view.corners = corners
        view.invalidateAll()
    }
}
