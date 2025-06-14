import Foundation

// every lyrics source the android app asks, under the same names so saved orders match
nonisolated enum LyricsProvider: String, CaseIterable, Codable, Sendable, Identifiable {
    case betterLyrics = "BetterLyrics"
    case youLyPlus = "YouLyPlus"
    case paxsenix = "Paxsenix"
    case simpMusic = "SimpMusic"
    case lrcLib = "LrcLib"
    case deezer = "Deezer"
    case youTubeSubtitle = "YouTubeSubtitle"
    case youTubeMusic = "YouTubeMusic"
    case netEase = "NetEase"
    case qqMusic = "QQMusic"
    case kuGou = "Kugou"
    case youTubeCaptions = "YouTubeCaptions"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .betterLyrics: "Apple Music"
        case .youLyPlus: "YouLyPlus"
        case .paxsenix: "PaxSenix"
        case .simpMusic: "SimpMusic"
        case .lrcLib: "LrcLib"
        case .deezer: "Deezer"
        case .youTubeSubtitle: "YouTube Subtitle"
        case .youTubeMusic: "YouTube Music"
        case .netEase: "NetEase"
        case .qqMusic: "QQ Music"
        case .kuGou: "KuGou"
        case .youTubeCaptions: "YouTube Auto Captions"
        }
    }

    var detail: String {
        switch self {
        case .betterLyrics: String(localized: "Word by word, with duets and backing vocals")
        case .youLyPlus: String(localized: "Word by word from LyricsPlus")
        case .paxsenix: String(localized: "Apple Music lyrics through PaxSenix")
        case .simpMusic: String(localized: "Matched to the exact YouTube video")
        case .lrcLib: String(localized: "Free, community synced lyrics")
        case .deezer: String(localized: "Deezer's own synced lyrics")
        case .youTubeSubtitle: String(localized: "The subtitles uploaded with the video")
        case .youTubeMusic: String(localized: "YouTube Music's plain lyrics")
        case .netEase: String(localized: "Best for Chinese songs, often word by word")
        case .qqMusic: String(localized: "Best for Chinese songs")
        case .kuGou: String(localized: "Best for Chinese songs")
        case .youTubeCaptions: String(localized: "Speech recognition, only when nothing else has lyrics")
        }
    }

    // the chinese services answer in chinese for songs that aren't, so they're only believed first-hand for chinese songs
    var isChinese: Bool { self == .netEase || self == .qqMusic || self == .kuGou }

    // youtube's own lyrics come from the video itself, so their script says what language the song is in
    var isLanguageReference: Bool { self == .youTubeMusic || self == .youTubeSubtitle }

    static let defaultOrder: [LyricsProvider] = [
        .betterLyrics, .youLyPlus, .paxsenix, .simpMusic, .lrcLib, .deezer,
        .youTubeSubtitle, .youTubeMusic, .netEase, .qqMusic, .kuGou, .youTubeCaptions,
    ]

    // the raw lyrics text in the app's format, nil when this source has nothing for the song
    func fetch(_ query: LyricsQuery) async throws -> String? {
        switch self {
        case .betterLyrics: try await BetterLyrics.lyrics(query)
        case .youLyPlus: await YouLyPlus.lyrics(query)
        case .paxsenix: await Paxsenix.lyrics(query)
        case .simpMusic: await SimpMusicLyrics.lyrics(query)
        case .lrcLib: await LrcLib.lyrics(query)
        case .deezer: try await DeezerLyrics.lyrics(query)
        case .youTubeSubtitle: try await InnerTube.shared.subtitleLyrics(videoId: query.videoId)
        case .youTubeMusic: try await YouTubeMusicLyrics.lyrics(query)
        case .netEase: try await NetEaseLyrics.lyrics(query)
        case .qqMusic: try await QQMusicLyrics.lyrics(query)
        case .kuGou: try await KuGou.lyrics(query)
        case .youTubeCaptions: try await InnerTube.shared.captionLyrics(videoId: query.videoId)
        }
    }
}
