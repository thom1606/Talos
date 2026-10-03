import AppKit

/// Gives each newly hovered wheel target one short, immediate sound.
@MainActor
final class AppFeedback {
    static let shared = AppFeedback()

    private let sounds = FeedbackSounds()

    private init() { }

    func prepare() {
        guard TalosPreferences.defaults.bool(forKey: TalosPreferenceKey.hoverSound)
                || TalosPreferences.defaults.bool(forKey: TalosPreferenceKey.completionSound) else { return }
        Task { @concurrent [sounds] in
            await sounds.prepare()
        }
    }

    func hoveredTargetChanged() {
        guard TalosPreferences.defaults.bool(forKey: TalosPreferenceKey.hoverSound) else { return }
        Task { @concurrent [sounds] in
            await sounds.playHover()
        }
    }

    func actionCompleted() {
        guard TalosPreferences.defaults.bool(forKey: TalosPreferenceKey.completionSound) else { return }
        Task { @concurrent [sounds] in
            await sounds.playCompletion()
        }
    }
}

/// NSSound's first playback can block while connecting to the audio service.
/// Keep every sound access on one dedicated executor, away from the UI and cooperative pool.
private actor FeedbackSounds {
    nonisolated private let queue = DispatchSerialQueue(label: "com.thom1606.Talos.feedback", qos: .userInitiated)
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private var hoverSounds: [NSSound] = []
    private var completionSound: NSSound?
    private var nextHoverSoundIndex = 0
    private var isPrepared = false

    func prepare() {
        guard !isPrepared else { return }
        isPrepared = true
        if let url = Bundle.main.url(forResource: "HoverTick", withExtension: "wav") {
            hoverSounds = (0..<4).compactMap { _ in NSSound(contentsOf: url, byReference: false) }
            hoverSounds.forEach { $0.volume = 0.6 }
        }
        completionSound = NSSound(named: NSSound.Name("Glass"))
        completionSound?.volume = 0.25
    }

    func playHover() {
        prepare()
        guard !hoverSounds.isEmpty else { return }

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

    func playCompletion() {
        prepare()
        _ = completionSound?.play()
    }
}
