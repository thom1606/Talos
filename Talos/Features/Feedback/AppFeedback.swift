import AppKit

/// Gives each newly hovered wheel target one short, immediate sound.
@MainActor
final class AppFeedback {
    static let shared = AppFeedback()

    private let hoverSounds: [NSSound] = {
        guard let url = Bundle.main.url(forResource: "HoverTick", withExtension: "wav") else { return [] }
        return (0..<4).compactMap { _ in NSSound(contentsOf: url, byReference: false) }
    }()
    private let completionSound = NSSound(named: NSSound.Name("Glass"))
    private var nextHoverSoundIndex = 0

    private init() {
        hoverSounds.forEach { $0.volume = 0.6 }
        completionSound?.volume = 0.25
    }

    func hoveredTargetChanged() {
        guard TalosPreferences.defaults.bool(forKey: TalosPreferenceKey.hoverSound),
              !hoverSounds.isEmpty else { return }

        // Short sounds can overlap without cutting off the previous tile's sound.
        for offset in 0..<hoverSounds.count {
            let index = (nextHoverSoundIndex + offset) % hoverSounds.count
            let sound = hoverSounds[index]
            guard !sound.isPlaying else { continue }
            nextHoverSoundIndex = (index + 1) % hoverSounds.count
            _ = sound.play()
            return
        }
    }

    func actionCompleted() {
        guard TalosPreferences.defaults.bool(forKey: TalosPreferenceKey.completionSound) else { return }
        _ = completionSound?.play()
    }
}
