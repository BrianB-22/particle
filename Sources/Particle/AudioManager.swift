import AVFoundation

final class AudioManager {
    static let shared = AudioManager()

    private var bgPlayer: AVAudioPlayer?
    private var effectPool: [String: [AVAudioPlayer]] = [:]
    private var lastPlayed: [String: Date] = [:]

    private init() { preload() }

    // MARK: - Public API

    func startIntro() {
        guard let url = sound("background_intro", ext: "wav") else { return }
        bgPlayer = try? AVAudioPlayer(contentsOf: url)
        bgPlayer?.numberOfLoops = -1
        bgPlayer?.volume = 0.80
        bgPlayer?.play()
    }

    func startGameplay() {
        guard let url = sound("background_gameplay", ext: "wav") else { return }
        bgPlayer = try? AVAudioPlayer(contentsOf: url)
        bgPlayer?.numberOfLoops = -1
        bgPlayer?.volume = 0.40
        bgPlayer?.play()
    }

    func stopBackground() { bgPlayer?.stop(); bgPlayer = nil }

    func play(_ name: String) {
        // Debounce: same effect can't fire more than once per 80ms
        let now = Date()
        if let last = lastPlayed[name], now.timeIntervalSince(last) < 0.08 { return }
        lastPlayed[name] = now

        guard let player = availablePlayer(for: name) else { return }
        player.currentTime = 0
        player.play()
    }

    // MARK: - Private

    private func preload() {
        let effects: [(String, String)] = [
            ("boid_dead",       "wav"),
            ("boid_safe",       "wav"),
            ("blackhole_appear", "wav"),
            ("pred_lose",       "wav"),
            ("gameover",        "wav"),
        ]
        for (name, ext) in effects {
            guard let url = sound(name, ext: ext) else { continue }
            // Pool of 6 players per effect so rapid concurrent sounds don't cut each other off
            effectPool[name] = (0..<6).compactMap { _ in try? AVAudioPlayer(contentsOf: url) }
            effectPool[name]?.forEach { $0.prepareToPlay(); $0.volume = 0.7 }
        }
        effectPool["background_music"] = nil  // bg handled separately
    }

    private func availablePlayer(for name: String) -> AVAudioPlayer? {
        effectPool[name]?.first { !$0.isPlaying }
    }

    private func sound(_ name: String, ext: String) -> URL? {
        // Bundle.module only exists in SPM builds; Xcode app targets use Bundle.main
        #if SWIFT_PACKAGE
        return Bundle.module.url(forResource: name, withExtension: ext)
        #else
        return Bundle.main.url(forResource: name, withExtension: ext)
        #endif
    }
}
