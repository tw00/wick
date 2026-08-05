import AppKit
import Carbon.HIToolbox

/// One recorded key combination.
struct HotkeySpec: Equatable {
    var keyCode: Int
    /// Carbon modifier mask (`cmdKey`, `optionKey`, …), which is what
    /// `RegisterEventHotKey` wants.
    var carbonMods: Int
    /// What to show in Settings: "⌥⌘T".
    var label: String

    var isSet: Bool { keyCode >= 0 && carbonMods != 0 && !label.isEmpty }
    static let unset = HotkeySpec(keyCode: -1, carbonMods: 0, label: "")

    /// Reads a recorded key event, refusing anything without a real modifier —
    /// a global hotkey on a bare letter would eat that letter everywhere.
    static func from(event: NSEvent) -> HotkeySpec? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let needsOne: NSEvent.ModifierFlags = [.command, .control, .option]
        guard !flags.intersection(needsOne).isEmpty else { return nil }

        var carbon = 0
        var label = ""
        if flags.contains(.control) { carbon |= controlKey; label += "⌃" }
        if flags.contains(.option)  { carbon |= optionKey;  label += "⌥" }
        if flags.contains(.shift)   { carbon |= shiftKey;   label += "⇧" }
        if flags.contains(.command) { carbon |= cmdKey;     label += "⌘" }

        label += Self.keyName(for: event)
        return HotkeySpec(keyCode: Int(event.keyCode), carbonMods: carbon, label: label)
    }

    private static func keyName(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space:       return "Space"
        case kVK_Return:      return "↩"
        case kVK_Tab:         return "⇥"
        case kVK_Delete:      return "⌫"
        case kVK_LeftArrow:   return "←"
        case kVK_RightArrow:  return "→"
        case kVK_UpArrow:     return "↑"
        case kVK_DownArrow:   return "↓"
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Comma:  return ","
        case kVK_ANSI_Slash:  return "/"
        default:
            return (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }
}

/// System-wide shortcuts, through Carbon's `RegisterEventHotKey` — still the one
/// way to get a global hotkey without asking for Accessibility access. Off until
/// you turn it on, and both combinations are recorded in Settings.
final class Hotkeys {
    static let shared = Hotkeys()

    enum Action: UInt32 {
        case toggle = 1
        case stop = 2
    }

    var onAction: ((Action) -> Void)?

    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    private init() {}

    /// Applies the current preferences — call again after anything changes.
    func sync() {
        unregister()
        guard Prefs.shared.hotkeysEnabled else { return }
        installHandler()
        add(Prefs.shared.toggleHotkey, action: .toggle)
        add(Prefs.shared.stopHotkey, action: .stop)
    }

    private func unregister() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
    }

    private func add(_ spec: HotkeySpec, action: Action) {
        guard spec.isSet else { return }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x5749_434B), id: action.rawValue)   // 'WICK'
        let status = RegisterEventHotKey(UInt32(spec.keyCode), UInt32(spec.carbonMods), id,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs.append(ref)
        } else {
            NSLog("Wick: hotkey %@ unavailable (status %d) — probably taken", spec.label, status)
        }
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, let action = Action(rawValue: id.id) else {
                return OSStatus(eventNotHandledErr)
            }
            DispatchQueue.main.async { Hotkeys.shared.onAction?(action) }
            return noErr
        }, 1, &spec, nil, &handler)
    }
}
