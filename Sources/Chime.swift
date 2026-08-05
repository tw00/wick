import AppKit

/// End-of-timer sound. Uses the system sounds so there are no assets to ship
/// and the choices are ones you already recognise.
enum Chime {
    static var available: [String] {
        let dir = "/System/Library/Sounds"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return names
            .filter { $0.hasSuffix(".aiff") }
            .map { String($0.dropLast(5)) }
            .sorted()
    }

    /// Plays the configured sound, repeated a few times so it's hard to miss
    /// if you've wandered off.
    static func play(name: String? = nil, repeats: Int? = nil) {
        let soundName = name ?? Prefs.shared.soundName
        guard !soundName.isEmpty else { return }
        let count = max(1, min(6, repeats ?? Prefs.shared.soundRepeats))
        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 1.1) {
                NSSound(named: soundName)?.play()
            }
        }
    }
}
