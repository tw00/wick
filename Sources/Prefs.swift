import AppKit
import Carbon.HIToolbox

extension Notification.Name {
    /// Posted whenever a preference that affects the overlay or menu changes.
    static let wickPrefsChanged = Notification.Name("wickPrefsChanged")
}

enum RingStyle: String, CaseIterable, Identifiable {
    // Calm — for actually working.
    case plain, fade, pulse, split, ticks, tide, level
    // Playful — for everything else.
    case fuse, snake, aurora

    var id: String { rawValue }

    static var calm: [RingStyle] { [.plain, .fade, .pulse, .split, .ticks, .tide, .level] }
    static var playful: [RingStyle] { [.fuse, .snake, .aurora] }

    var label: String {
        switch self {
        case .plain:  return "Plain"
        case .fade:   return "Fade"
        case .pulse:  return "Pulse"
        case .split:  return "Split"
        case .ticks:  return "Minutes"
        case .tide:   return "Tide"
        case .level:  return "Level"
        case .fuse:   return "Fuse"
        case .snake:  return "Snake"
        case .aurora: return "Aurora"
        }
    }

    var blurb: String {
        switch self {
        case .plain:  return "A grey line that shortens. No motion, no distraction."
        case .fade:   return "Same line, dissolving at the leading edge. The quietest one."
        case .pulse:  return "Blue line with a breathing head. Calm, but alive."
        case .split:  return "Burns both ways from the top and meets at the bottom."
        case .ticks:  return "One tick per minute, going out one at a time. Countable."
        case .tide:   return "A slow bright wave travelling the line. Calm, never still."
        case .level:  return "Drains like liquid down the sides, with a wobbling surface."
        case .fuse:   return "A twisted hemp fuse burning down, sparks and all."
        case .snake:  return "A snake eats its way round the screen, apple by apple."
        case .aurora: return "Drifting colour that washes out to grey as time runs out."
        }
    }
}

enum NudgeMode: String, CaseIterable, Identifiable {
    /// Hide everything except the listed apps — say where you're allowed to be.
    case allow
    /// Hide only the listed apps.
    case block

    var id: String { rawValue }

    var label: String {
        switch self {
        case .allow: return "Allow only these"
        case .block: return "Hide these"
        }
    }
}

/// Named line weights, for switching without hunting along a slider.
enum BorderWeight: String, CaseIterable, Identifiable {
    case hair, thin, normal, bold

    var id: String { rawValue }

    var px: Double {
        switch self {
        case .hair:   return 1
        case .thin:   return 3
        case .normal: return 6
        case .bold:   return 10
        }
    }

    var label: String {
        switch self {
        case .hair:   return "Hair 1"
        case .thin:   return "Thin 3"
        case .normal: return "Normal 6"
        case .bold:   return "Bold 10"
        }
    }
}

/// Registered defaults, read through accessors that guarantee registration has
/// happened first. A stored property's initialiser runs *before* the body of
/// `init`, so registering there would be too late: every default would read back
/// as zero, empty or false.
private enum Store {
    static let ready: Bool = {
        let d = UserDefaults.standard
        d.register(defaults: [
            "style": RingStyle.plain.rawValue,
            "thickness": 6.0,
            "cornerRadius": -1.0,          // -1 = auto: match the screen's own corners
            "allDisplays": false,
            "defaultDuration": 25.0 * 60,
            "soundName": "Glass",
            "soundRepeats": 3,
            "focusWhileRunning": false,
            "hotkeysEnabled": false,
            "hotkeyToggleKey": kVK_ANSI_T,
            "hotkeyToggleMods": cmdKey | optionKey,
            "hotkeyToggleLabel": "⌥⌘T",
            "hotkeyStopKey": kVK_ANSI_T,
            "hotkeyStopMods": cmdKey | optionKey | shiftKey,
            "hotkeyStopLabel": "⌥⇧⌘T",
            "notifyOnFinish": true,
            "nudgeMode": NudgeMode.allow.rawValue,
            "listedApps": [String](),
        ])
        // Earlier builds only had a blocklist.
        if d.stringArray(forKey: "listedApps")?.isEmpty != false,
           let old = d.stringArray(forKey: "blockedApps"), !old.isEmpty {
            d.set(old, forKey: "listedApps")
            d.set(NudgeMode.block.rawValue, forKey: "nudgeMode")
            d.removeObject(forKey: "blockedApps")
        }
        return true
    }()

    private static var defaults: UserDefaults { _ = ready; return UserDefaults.standard }

    static func double(_ key: String) -> Double { defaults.double(forKey: key) }
    static func int(_ key: String) -> Int { defaults.integer(forKey: key) }
    static func bool(_ key: String) -> Bool { defaults.bool(forKey: key) }
    static func string(_ key: String) -> String { defaults.string(forKey: key) ?? "" }
    static func strings(_ key: String) -> [String] { defaults.stringArray(forKey: key) ?? [] }

    /// Hotkeys live as three keys apiece — code, modifier mask, and the label to
    /// show, so nothing has to reverse a key code back into a glyph.
    static func hotkey(_ prefix: String) -> HotkeySpec {
        HotkeySpec(keyCode: int("\(prefix)Key"),
                   carbonMods: int("\(prefix)Mods"),
                   label: string("\(prefix)Label"))
    }

    static func setHotkey(_ spec: HotkeySpec, _ prefix: String) {
        let d = defaults
        d.set(spec.keyCode, forKey: "\(prefix)Key")
        d.set(spec.carbonMods, forKey: "\(prefix)Mods")
        d.set(spec.label, forKey: "\(prefix)Label")
    }
}

/// User settings, backed by UserDefaults. Also an ObservableObject so the
/// settings window can bind straight to it.
final class Prefs: ObservableObject {
    static let shared = Prefs()

    private let d = UserDefaults.standard

    private init() {}

    @Published var style: RingStyle = RingStyle(rawValue: Store.string("style")) ?? .plain {
        didSet { d.set(style.rawValue, forKey: "style"); changed() }
    }
    @Published var thickness: Double = Store.double("thickness") {
        didSet { d.set(thickness, forKey: "thickness"); changed() }
    }
    @Published var cornerRadius: Double = Store.double("cornerRadius") {
        didSet { d.set(cornerRadius, forKey: "cornerRadius"); changed() }
    }
    @Published var allDisplays: Bool = Store.bool("allDisplays") {
        didSet { d.set(allDisplays, forKey: "allDisplays"); changed() }
    }
    /// Corner radius of the ring, or -1 to follow each screen's own corners.
    var cornersAuto: Bool { cornerRadius < 0 }
    /// Duration the menu bar offers as "Start" and what a fresh timer uses.
    @Published var defaultDuration: Double = Store.double("defaultDuration") {
        didSet { d.set(defaultDuration, forKey: "defaultDuration"); changed() }
    }
    /// Name of a sound in /System/Library/Sounds, or "" for silence.
    @Published var soundName: String = Store.string("soundName") {
        didSet { d.set(soundName, forKey: "soundName"); changed() }
    }
    @Published var soundRepeats: Int = Store.int("soundRepeats") {
        didSet { d.set(soundRepeats, forKey: "soundRepeats"); changed() }
    }
    @Published var focusWhileRunning: Bool = Store.bool("focusWhileRunning") {
        didSet { d.set(focusWhileRunning, forKey: "focusWhileRunning"); changed() }
    }
    @Published var hotkeysEnabled: Bool = Store.bool("hotkeysEnabled") {
        didSet { d.set(hotkeysEnabled, forKey: "hotkeysEnabled"); changed() }
    }
    @Published var notifyOnFinish: Bool = Store.bool("notifyOnFinish") {
        didSet { d.set(notifyOnFinish, forKey: "notifyOnFinish"); changed() }
    }
    /// Start, or pause and resume.
    @Published var toggleHotkey: HotkeySpec = Store.hotkey("hotkeyToggle") {
        didSet { Store.setHotkey(toggleHotkey, "hotkeyToggle"); changed() }
    }
    @Published var stopHotkey: HotkeySpec = Store.hotkey("hotkeyStop") {
        didSet { Store.setHotkey(stopHotkey, "hotkeyStop"); changed() }
    }
    /// Whether `listedApps` is the set that's allowed, or the set that isn't.
    @Published var nudgeMode: NudgeMode = NudgeMode(rawValue: Store.string("nudgeMode")) ?? .allow {
        didSet { d.set(nudgeMode.rawValue, forKey: "nudgeMode"); changed() }
    }
    /// Bundle identifiers the nudge works from, read according to `nudgeMode`.
    @Published var listedApps: [String] = Store.strings("listedApps") {
        didSet { d.set(listedApps, forKey: "listedApps"); changed() }
    }

    private func changed() {
        NotificationCenter.default.post(name: .wickPrefsChanged, object: nil)
    }
}

enum Screens {
    /// Radii for the two ends of a screen. A MacBook's glass is rounded along
    /// the top only — the bottom two corners are square.
    struct Corners: Equatable {
        var top: Double
        var bottom: Double

        static let square = Corners(top: 0, bottom: 0)
        static func uniform(_ r: Double) -> Corners { Corners(top: r, bottom: r) }
    }

    /// What a MacBook's own glass is rounded to, in points. A constant because
    /// the system won't say: on macOS 26 `NSScreen` has no corner-radius method
    /// at all (the old private `_displayCornerRadius` is gone), no SkyLight or
    /// CoreGraphics symbol answers it, and the IORegistry doesn't carry it
    /// either. Settings can override it.
    static let builtInTopRadius: Double = 20

    /// Kept for the machines where the old private accessor still answers.
    static func detectedCornerRadius(_ screen: NSScreen) -> Double? {
        let sel = NSSelectorFromString("_displayCornerRadius")
        guard screen.responds(to: sel),
              let value = (screen as AnyObject).value(forKey: "_displayCornerRadius") as? Double,
              value > 0
        else { return nil }
        return max(0, min(64, value))
    }

    static func isBuiltIn(_ screen: NSScreen) -> Bool {
        guard let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return false }
        return CGDisplayIsBuiltin(CGDirectDisplayID(n.uint32Value)) != 0
    }

    /// What the border should actually use on this screen. Auto means: round the
    /// corners on a MacBook's own display, because the glass is rounded there,
    /// and keep them square on an external monitor, because it isn't.
    static func corners(for screen: NSScreen) -> Corners {
        let pref = Prefs.shared.cornerRadius
        if pref >= 0 { return .uniform(pref) }
        guard isBuiltIn(screen) else { return .square }
        return Corners(top: detectedCornerRadius(screen) ?? builtInTopRadius, bottom: 0)
    }

    static func autoCornersForMain() -> Corners {
        guard let s = NSScreen.main else { return .square }
        return corners(for: s)
    }
}
