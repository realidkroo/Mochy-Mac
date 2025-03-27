import Foundation

nonisolated struct ArtistRef: Hashable, Sendable, Codable {
    let name: String
    let id: String?
}

nonisolated struct AlbumRef: Hashable, Sendable, Codable {
    let name: String
    let id: String
}

nonisolated struct SongItem: Hashable, Sendable, Codable, Identifiable {
    let id: String
    let title: String
    let artists: [ArtistRef]
    var album: AlbumRef? = nil
    var duration: Int? = nil
    let thumbnail: String
    var explicit: Bool = false
    var musicVideoType: String? = nil

    var artistNames: String { artists.map(\.name).joined(separator: ", ") }

    // atv is a plain song with album art, everything else is a real video
    var isVideo: Bool { musicVideoType != nil && musicVideoType != "MUSIC_VIDEO_TYPE_ATV" }
}

nonisolated struct AlbumItem: Hashable, Sendable, Identifiable {
    let browseId: String
    var playlistId: String? = nil
    let title: String
    let artists: [ArtistRef]
    var year: Int? = nil
    let thumbnail: String
    var explicit: Bool = false

    var id: String { browseId }
}

nonisolated struct ArtistItem: Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let thumbnail: String?
    var subtitle: String? = nil
}

nonisolated struct PlaylistItem: Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let author: String?
    var songCountText: String? = nil
    let thumbnail: String?
}

nonisolated enum YTItem: Hashable, Sendable, Identifiable {
    case song(SongItem)
    case album(AlbumItem)
    case artist(ArtistItem)
    case playlist(PlaylistItem)

    var id: String {
        switch self {
        case .song(let song): "song-\(song.id)"
        case .album(let album): "album-\(album.browseId)"
        case .artist(let artist): "artist-\(artist.id)"
        case .playlist(let playlist): "playlist-\(playlist.id)"
        }
    }

    var title: String {
        switch self {
        case .song(let song): song.title
        case .album(let album): album.title
        case .artist(let artist): artist.title
        case .playlist(let playlist): playlist.title
        }
    }

    var thumbnail: String? {
        switch self {
        case .song(let song): song.thumbnail
        case .album(let album): album.thumbnail
        case .artist(let artist): artist.thumbnail
        case .playlist(let playlist): playlist.thumbnail
        }
    }

    var song: SongItem? {
        if case .song(let song) = self { return song }
        return nil
    }
}

// where a play starts from: one song, a radio built around it, or a whole playlist
nonisolated struct WatchEndpoint: Hashable, Sendable {
    var videoId: String? = nil
    var playlistId: String? = nil
    var params: String? = nil
    var index: Int? = nil

    static func radio(for videoId: String) -> WatchEndpoint {
        WatchEndpoint(videoId: videoId, playlistId: "RDAMVM\(videoId)", params: "wAEB")
    }
}
