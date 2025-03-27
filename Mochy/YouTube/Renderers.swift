import Foundation

// one piece of a youtube text line, with the link it points to when it has one
nonisolated struct Run: Sendable {
    let text: String
    let endpoint: JSON

    var browseId: String? { endpoint["browseEndpoint"]["browseId"].string }
    var videoId: String? { endpoint["watchEndpoint"]["videoId"].string }
    var pageType: String? {
        endpoint["browseEndpoint"]["browseEndpointContextSupportedConfigs"]["browseEndpointContextMusicConfig"]["pageType"].string
    }
    var musicVideoType: String? {
        endpoint["watchEndpoint"]["watchEndpointMusicSupportedConfigs"]["watchEndpointMusicConfig"]["musicVideoType"].string
    }
}

nonisolated extension JSON {
    var runs: [Run] {
        self["runs"].array.compactMap { run in
            run["text"].string.map { Run(text: $0, endpoint: run["navigationEndpoint"]) }
        }
    }

    var text: String? {
        let joined = runs.map(\.text).joined()
        return joined.isEmpty ? self["simpleText"].string : joined
    }

    // musicThumbnailRenderer and friends all end in a list of sizes, the last one is the biggest
    var thumbnailURL: String? {
        let thumbnails = self["musicThumbnailRenderer"]["thumbnail"]["thumbnails"].exists
            ? self["musicThumbnailRenderer"]["thumbnail"]["thumbnails"]
            : self["thumbnail"]["thumbnails"].exists ? self["thumbnail"]["thumbnails"] : self["thumbnails"]
        return thumbnails.last["url"].string
    }

    var continuation: String? {
        let list = self["continuations"].exists ? self["continuations"] : self
        return list.first["nextContinuationData"]["continuation"].string
            ?? list.first["nextRadioContinuationData"]["continuation"].string
            ?? self.last["continuationItemRenderer"]["continuationEndpoint"]["continuationCommand"]["token"].string
    }

    var pageType: String? {
        self["browseEndpoint"]["browseEndpointContextSupportedConfigs"]["browseEndpointContextMusicConfig"]["pageType"].string
    }

    var hasExplicitBadge: Bool {
        array.contains { $0["musicInlineBadgeRenderer"]["icon"]["iconType"].string == "MUSIC_EXPLICIT_BADGE" }
    }

    // the watch endpoint behind a cover's play button, where youtube hides an album's playlist id
    var playButtonEndpoint: JSON {
        let play = self["musicItemThumbnailOverlayRenderer"]["content"]["musicPlayButtonRenderer"]["playNavigationEndpoint"]
        return play["watchPlaylistEndpoint"].exists ? play["watchPlaylistEndpoint"] : play["watchEndpoint"]
    }
}

nonisolated extension Array where Element == Run {
    // "artist • album • 3:20" comes as one line, split it back into its parts
    func splitBySeparator() -> [[Run]] {
        var parts: [[Run]] = [[]]
        for run in self {
            if run.text == " • " {
                parts.append([])
            } else {
                parts[parts.count - 1].append(run)
            }
        }
        return parts.filter { !$0.isEmpty }
    }

    // names come with " & " and ", " runs in between, every other run is the real one
    var namesOnly: [Run] { enumerated().filter { $0.offset % 2 == 0 }.map(\.element) }

    var asArtists: [ArtistRef] { map { ArtistRef(name: $0.text, id: $0.browseId) } }
}

nonisolated extension String {
    // "3:20" or "1:02:03" into seconds
    var parsedDuration: Int? {
        let parts = split(separator: ":").map { Int($0) }
        guard (2...3).contains(parts.count), parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
    }

    // google image links carry their size in the url, ask for the one we're about to draw
    func resizedThumbnail(_ size: Int) -> String {
        if let range = range(of: #"=w\d+-h\d+"#, options: .regularExpression) {
            return replacingCharacters(in: range, with: "=w\(size)-h\(size)")
        }
        if let range = range(of: #"=s\d+"#, options: .regularExpression) {
            return replacingCharacters(in: range, with: "=s\(size)")
        }
        return self
    }
}

nonisolated enum Renderers {
    private static let artistPages: Set<String> = ["MUSIC_PAGE_TYPE_ARTIST", "MUSIC_PAGE_TYPE_LIBRARY_ARTIST", "MUSIC_PAGE_TYPE_USER_CHANNEL"]
    private static let albumPages: Set<String> = ["MUSIC_PAGE_TYPE_ALBUM", "MUSIC_PAGE_TYPE_AUDIOBOOK"]

    // the square cards in carousels: home shelves, artist albums, related
    static func twoRowItem(_ renderer: JSON) -> YTItem? {
        guard let title = renderer["title"].runs.first?.text else { return nil }
        let endpoint = renderer["navigationEndpoint"]
        let thumbnail = renderer["thumbnailRenderer"].thumbnailURL
        let subtitle = renderer["subtitle"].runs

        if let videoId = endpoint["watchEndpoint"]["videoId"].string {
            let parts = subtitle.namesOnly
            var artists = parts.filter { run in
                guard let id = run.browseId else { return false }
                return !id.hasPrefix("MPREb_")
            }.asArtists
            if artists.isEmpty, let first = subtitle.first { artists = [ArtistRef(name: first.text, id: nil)] }
            let album = parts.first { $0.browseId?.hasPrefix("MPREb_") == true }
            return .song(SongItem(
                id: videoId,
                title: title,
                artists: artists,
                album: album.flatMap { run in run.browseId.map { AlbumRef(name: run.text, id: $0) } },
                thumbnail: thumbnail ?? "",
                explicit: renderer["subtitleBadges"].hasExplicitBadge,
                musicVideoType: endpoint["watchEndpoint"]["watchEndpointMusicSupportedConfigs"]["watchEndpointMusicConfig"]["musicVideoType"].string
            ))
        }

        guard let browseId = endpoint["browseEndpoint"]["browseId"].string else { return nil }
        let pageType = endpoint.pageType ?? ""

        if albumPages.contains(pageType) {
            let artists = subtitle.namesOnly.filter { $0.browseId != nil }.asArtists
            return .album(AlbumItem(
                browseId: browseId,
                playlistId: renderer["thumbnailOverlay"].playButtonEndpoint["playlistId"].string,
                title: title,
                artists: artists.isEmpty ? subtitle.namesOnly.dropFirst().map { ArtistRef(name: $0.text, id: $0.browseId) } : artists,
                year: subtitle.last.flatMap { Int($0.text) },
                thumbnail: thumbnail ?? "",
                explicit: renderer["subtitleBadges"].hasExplicitBadge
            ))
        }
        if artistPages.contains(pageType) {
            return .artist(ArtistItem(
                id: browseId,
                title: renderer["title"].runs.last?.text ?? title,
                thumbnail: thumbnail,
                subtitle: renderer["subtitle"].text
            ))
        }
        if pageType == "MUSIC_PAGE_TYPE_PLAYLIST" {
            return .playlist(PlaylistItem(
                id: browseId.hasPrefix("VL") ? String(browseId.dropFirst(2)) : browseId,
                title: title,
                author: subtitle.first?.text,
                songCountText: subtitle.count > 2 ? subtitle.last?.text : nil,
                thumbnail: thumbnail
            ))
        }
        return nil
    }

    // the long rows in shelves: search results, album tracks, playlist songs, an artist's top songs
    static func listItem(_ renderer: JSON, album: AlbumItem? = nil) -> YTItem? {
        let columns = renderer["flexColumns"].array.map { $0["musicResponsiveListItemFlexColumnRenderer"]["text"] }
        guard let titleRun = columns.first?.runs.first else { return nil }
        let endpoint = renderer["navigationEndpoint"]
        let secondLine = columns.count > 1 ? columns[1].runs : []
        let thumbnail = renderer["thumbnail"].thumbnailURL
        let explicit = renderer["badges"].hasExplicitBadge
        let pageType = endpoint.pageType ?? ""

        if let browseId = endpoint["browseEndpoint"]["browseId"].string {
            let parts = secondLine.splitBySeparator()
            if artistPages.contains(pageType) {
                return .artist(ArtistItem(id: browseId, title: titleRun.text, thumbnail: thumbnail, subtitle: columns.dropFirst().compactMap(\.text).first))
            }
            if albumPages.contains(pageType) {
                let linked = secondLine.filter { $0.browseId != nil }
                return .album(AlbumItem(
                    browseId: browseId,
                    playlistId: renderer["overlay"].playButtonEndpoint["playlistId"].string,
                    title: titleRun.text,
                    artists: linked.isEmpty ? (parts.dropFirst().first ?? []).namesOnly.asArtists : linked.asArtists,
                    year: parts.last?.first.flatMap { Int($0.text) },
                    thumbnail: thumbnail ?? "",
                    explicit: explicit
                ))
            }
            if pageType == "MUSIC_PAGE_TYPE_PLAYLIST" {
                return .playlist(PlaylistItem(
                    id: browseId.hasPrefix("VL") ? String(browseId.dropFirst(2)) : browseId,
                    title: titleRun.text,
                    author: parts.count > 1 ? parts[1].first?.text : parts.first?.first?.text,
                    songCountText: parts.last?.last?.text,
                    thumbnail: thumbnail
                ))
            }
            return nil
        }

        guard let videoId = renderer["playlistItemData"]["videoId"].string ?? titleRun.videoId else { return nil }
        let allRuns = columns.flatMap(\.runs)
        var artists = allRuns.filter { artistPages.contains($0.pageType ?? "") }.asArtists
        if artists.isEmpty {
            // unlinked artists only show up as the first part of the second line, minus a "Song" or "Video" label
            let firstPart = secondLine.splitBySeparator().first ?? []
            artists = firstPart.namesOnly.filter { !["Song", "Video", "Episode"].contains($0.text) }.asArtists
        }
        if artists.isEmpty, let album { artists = album.artists }
        let albumRun = allRuns.first { albumPages.contains($0.pageType ?? "") }
        let durationText = renderer["fixedColumns"].first["musicResponsiveListItemFixedColumnRenderer"]["text"].text
            ?? secondLine.splitBySeparator().last?.first?.text
        let videoType = renderer["overlay"].playButtonEndpoint["watchEndpointMusicSupportedConfigs"]["watchEndpointMusicConfig"]["musicVideoType"].string
            ?? titleRun.musicVideoType

        return .song(SongItem(
            id: videoId,
            title: titleRun.text,
            artists: artists,
            album: albumRun.flatMap { run in run.browseId.map { AlbumRef(name: run.text, id: $0) } }
                ?? album.map { AlbumRef(name: $0.title, id: $0.browseId) },
            duration: durationText?.parsedDuration,
            thumbnail: thumbnail ?? album?.thumbnail ?? "",
            explicit: explicit,
            musicVideoType: videoType
        ))
    }

    // the rows in the up next queue
    static func queueItem(_ renderer: JSON) -> SongItem? {
        guard let videoId = renderer["videoId"].string, let title = renderer["title"].runs.first?.text else { return nil }
        let byline = renderer["longBylineText"].runs.splitBySeparator()
        let artists = (byline.first ?? []).namesOnly.filter { $0.text.parsedDuration == nil }.asArtists
        let albumRun = byline.count > 1 ? byline[1].first : nil
        return SongItem(
            id: videoId,
            title: title,
            artists: artists,
            album: albumRun.flatMap { run in run.browseId.map { AlbumRef(name: run.text, id: $0) } },
            duration: renderer["lengthText"].text?.parsedDuration,
            thumbnail: renderer["thumbnail"]["thumbnails"].last["url"].string ?? "",
            explicit: renderer["badges"].hasExplicitBadge,
            musicVideoType: renderer["navigationEndpoint"]["watchEndpoint"]["watchEndpointMusicSupportedConfigs"]["watchEndpointMusicConfig"]["musicVideoType"].string
        )
    }

    // a shelf of any kind turned into a titled list of items, nil when there's nothing we can show
    static func section(_ content: JSON) -> FeedSection? {
        if content["musicCarouselShelfRenderer"].exists {
            let shelf = content["musicCarouselShelfRenderer"]
            let header = shelf["header"]["musicCarouselShelfBasicHeaderRenderer"]
            guard let title = header["title"].text else { return nil }
            let items = shelf["contents"].array.compactMap { item -> YTItem? in
                if item["musicTwoRowItemRenderer"].exists { return twoRowItem(item["musicTwoRowItemRenderer"]) }
                if item["musicResponsiveListItemRenderer"].exists { return listItem(item["musicResponsiveListItemRenderer"]) }
                return nil
            }
            guard !items.isEmpty else { return nil }
            return FeedSection(
                title: title,
                label: header["strapline"].text,
                thumbnail: header["thumbnail"].thumbnailURL,
                moreBrowseId: header["moreContentButton"]["buttonRenderer"]["navigationEndpoint"]["browseEndpoint"]["browseId"].string,
                moreParams: header["moreContentButton"]["buttonRenderer"]["navigationEndpoint"]["browseEndpoint"]["params"].string,
                items: items
            )
        }
        if content["musicShelfRenderer"].exists {
            let shelf = content["musicShelfRenderer"]
            let items = shelf["contents"].children("musicResponsiveListItemRenderer").compactMap { listItem($0) }
            guard !items.isEmpty else { return nil }
            let more = shelf["bottomEndpoint"]["browseEndpoint"]
            return FeedSection(
                title: shelf["title"].text ?? "",
                label: nil,
                thumbnail: nil,
                moreBrowseId: more["browseId"].string,
                moreParams: more["params"].string,
                items: items
            )
        }
        return nil
    }
}

nonisolated struct FeedSection: Hashable, Sendable, Identifiable {
    let title: String
    let label: String?
    let thumbnail: String?
    var moreBrowseId: String? = nil
    var moreParams: String? = nil
    let items: [YTItem]

    var id: String { title + (items.first?.id ?? "") }
    var isAllSongs: Bool { items.allSatisfy { $0.song != nil } }
}
