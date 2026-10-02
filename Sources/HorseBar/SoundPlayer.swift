import AVFoundation

/// Plays sounds from a folder. Several sounds can overlap.
final class SoundPlayer {
    static let extensions: Set<String> = ["wav", "mp3", "m4a", "aiff", "aif", "caf"]
    static let systemSounds = URL(fileURLWithPath: "/System/Library/Sounds")

    private var playing: [AVAudioPlayer] = []

    func files(in folder: URL) -> [URL] {
        let list = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return list
            .filter { Self.extensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Sounds in the folder, or the system sounds if it is empty.
    func available(in folder: URL) -> [URL] {
        let own = files(in: folder)
        return own.isEmpty ? files(in: Self.systemSounds) : own
    }

    /// volume 0…1
    func play(_ url: URL, volume: Float) {
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        playing.removeAll { !$0.isPlaying }
        player.volume = volume
        player.play()
        playing.append(player)
    }
}
