import AppKit
import MediaPlayer

// the media keys, control center's now playing and airpods all talk to the player through here
final class NowPlayingCenter {
    private weak var player: PlayerModel?
    private var artworkTask: Task<Void, Never>?
    private var artworkSongId: String?
    private var artwork: MPMediaItemArtwork?

    func attach(to player: PlayerModel) {
        self.player = player
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget(handler: Self.run { [weak player] _ in player?.resume() })
        center.pauseCommand.addTarget(handler: Self.run { [weak player] _ in player?.pause() })
        center.togglePlayPauseCommand.addTarget(handler: Self.run { [weak player] _ in player?.togglePlayPause() })
        center.nextTrackCommand.addTarget(handler: Self.run { [weak player] _ in player?.skipNext() })
        center.previousTrackCommand.addTarget(handler: Self.run { [weak player] _ in player?.skipPrevious() })
        center.changePlaybackPositionCommand.addTarget(handler: Self.run { [weak player] position in
            if let position { player?.seek(to: position) }
        })
    }

    // the commands can arrive on any thread, so the handler itself stays off the main actor and hops over
    nonisolated private static func run(
        _ action: @escaping @Sendable @MainActor (TimeInterval?) -> Void
    ) -> (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        { event in
            let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime
            Task { @MainActor in action(position) }
            return .success
        }
    }

    func update() {
        guard let player, let song = player.current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState = .stopped
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artistNames,
            MPMediaItemPropertyPlaybackDuration: player.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: player.isPlaying && !player.isBuffering ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let album = song.album?.name { info[MPMediaItemPropertyAlbumTitle] = album }
        if artworkSongId == song.id, let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = player.isPlaying ? .playing : .paused
        loadArtwork(for: song)
    }

    private func loadArtwork(for song: SongItem) {
        guard artworkSongId != song.id else { return }
        artworkSongId = song.id
        artwork = nil
        artworkTask?.cancel()
        artworkTask = Task {
            guard let image = await ImageLoader.shared.image(song.thumbnail.resizedThumbnail(600), pixels: 600), artworkSongId == song.id else { return }
            artwork = Self.makeArtwork(NSImage(cgImage: image.cgImage, size: NSSize(width: image.cgImage.width, height: image.cgImage.height)))
            update()
        }
    }

    // the system asks for the picture from its own queue, so the closure must not belong to the main actor
    nonisolated private static func makeArtwork(_ image: NSImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
