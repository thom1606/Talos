import AppKit

@MainActor final class SoundService {
    static let shared = SoundService()
    private let glass = Bundle.main.url(forResource: "Glass_006", withExtension: "ogg")
        .flatMap { NSSound(contentsOf: $0, byReference: false) }

    func playHover() {
        guard AppPreferences.defaults.bool(forKey: "hoverSound") else { return }
        play(volume: 0.5)
    }

    func playWheelCompletion() {
        guard AppPreferences.defaults.bool(forKey: "hoverSound") else { return }
        play(volume: 0.65)
    }

    func playCompletion() {
        guard AppPreferences.defaults.bool(forKey: "completionSound") else { return }
        play(volume: 0.65)
    }

    private func play(volume: Float) {
        glass?.stop()
        glass?.volume = volume
        glass?.play()
    }
}
