import Foundation
import SwiftData

// a song the app has met: liked, played or saved into a playlist, kept so the library works offline
@Model
final class LibrarySong {
    @Attribute(.unique) var id: String
    var title: String
    var artistsData: Data
    var albumName: String?
    var albumId: String?
    var thumbnail: String
    var duration: Int?
    var musicVideoType: String?
    var likedAt: Date?
    var lastPlayedAt: Date?
    var playCount: Int = 0

    init(_ song: SongItem) {
        id = song.id
        title = song.title
        artistsData = (try? JSONEncoder().encode(song.artists)) ?? Data()
        albumName = song.album?.name
        albumId = song.album?.id
        thumbnail = song.thumbnail
        duration = song.duration
        musicVideoType = song.musicVideoType
    }

    var artists: [ArtistRef] { (try? JSONDecoder().decode([ArtistRef].self, from: artistsData)) ?? [] }

    var item: SongItem {
        SongItem(
            id: id,
            title: title,
            artists: artists,
            album: albumId.map { AlbumRef(name: albumName ?? "", id: $0) },
            duration: duration,
            thumbnail: thumbnail,
            musicVideoType: musicVideoType
        )
    }

    // youtube's answer may be fresher than what we stored, but likes and play counts stay ours
    func refresh(from song: SongItem) {
        title = song.title
        if !song.artists.isEmpty { artistsData = (try? JSONEncoder().encode(song.artists)) ?? artistsData }
        if let album = song.album { albumName = album.name; albumId = album.id }
        if !song.thumbnail.isEmpty { thumbnail = song.thumbnail }
        duration = song.duration ?? duration
    }
}

@Model
final class LocalPlaylist {
    @Attribute(.unique) var id: String
    var name: String
    var createdAt: Date
    var songIds: [String]
    var isPinned: Bool = true

    init(name: String) {
        id = UUID().uuidString
        self.name = name
        createdAt = .now
        songIds = []
    }
}

// one listen, the history, the recap and the home feed's "recently played" read these
@Model
final class PlayEvent {
    var songId: String
    var playedAt: Date

    init(songId: String, playedAt: Date = .now) {
        self.songId = songId
        self.playedAt = playedAt
    }
}
