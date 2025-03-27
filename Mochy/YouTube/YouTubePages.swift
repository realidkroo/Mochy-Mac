import Foundation

nonisolated struct HomePage: Sendable {
    var chips: [HomeChip]
    var sections: [FeedSection]
    var continuation: String?
}

nonisolated struct HomeChip: Hashable, Sendable {
    let title: String
    let params: String?
}

nonisolated struct SearchSummary: Sendable {
    var top: YTItem?
    var sections: [FeedSection]
}

nonisolated struct SearchResult: Sendable {
    var items: [YTItem]
    var continuation: String?
}

nonisolated struct SearchSuggestions: Sendable {
    var queries: [String]
    var items: [YTItem]
}

nonisolated struct AlbumPage: Sendable {
    let album: AlbumItem
    let songs: [SongItem]
    let otherVersions: [YTItem]
    let description: String?
}

nonisolated struct ArtistPage: Sendable {
    let artist: ArtistItem
    let banner: String?
    let subscribers: String?
    let monthlyListeners: String?
    let description: String?
    let shuffleEndpoint: WatchEndpoint?
    let radioEndpoint: WatchEndpoint?
    let sections: [FeedSection]
}

nonisolated struct PlaylistPage: Sendable {
    let playlist: PlaylistItem
    let songs: [SongItem]
    let continuation: String?
}

nonisolated struct NextResult: Sendable {
    let items: [SongItem]
    let currentIndex: Int?
    let continuation: String?
    let lyricsBrowseId: String?
    let relatedBrowseId: String?
}

nonisolated enum SearchFilter: String, CaseIterable, Sendable {
    case all
    case songs = "EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D"
    case videos = "EgWKAQIQAWoKEAkQChAFEAMQBA%3D%3D"
    case albums = "EgWKAQIYAWoKEAkQChAFEAMQBA%3D%3D"
    case artists = "EgWKAQIgAWoKEAkQChAFEAMQBA%3D%3D"
    case playlists = "EgeKAQQoAEABagoQAxAEEAoQCRAF"

    // the params come url-encoded from the web app, the api wants them plain
    var params: String? { self == .all ? nil : rawValue.removingPercentEncoding }
}

extension InnerTube {
    func home(params: String? = nil) async throws -> HomePage {
        await ensureVisitorData()
        var body: [String: Any] = ["browseId": "FEmusic_home"]
        body["params"] = params
        let response = try await post("browse", body: body)
        let sectionList = response["contents"]["singleColumnBrowseResultsRenderer"]["tabs"][0]["tabRenderer"]["content"]["sectionListRenderer"]
        let chips = sectionList["header"]["chipCloudRenderer"]["chips"].array.compactMap { chip -> HomeChip? in
            let renderer = chip["chipCloudChipRenderer"]
            guard let title = renderer["text"].text else { return nil }
            return HomeChip(title: title, params: renderer["navigationEndpoint"]["browseEndpoint"]["params"].string)
        }
        return HomePage(
            chips: chips,
            sections: sectionList["contents"].array.compactMap(Renderers.section),
            continuation: sectionList.continuation
        )
    }

    func homeContinuation(_ token: String) async throws -> HomePage {
        let response = try await post("browse", body: [:], query: [
            URLQueryItem(name: "continuation", value: token),
            URLQueryItem(name: "ctoken", value: token),
        ])
        let list = response["continuationContents"]["sectionListContinuation"]
        return HomePage(chips: [], sections: list["contents"].array.compactMap(Renderers.section), continuation: list.continuation)
    }

    func searchSuggestions(_ input: String) async throws -> SearchSuggestions {
        let response = try await post("music/get_search_suggestions", body: ["input": input])
        let groups = response["contents"].array.map { $0["searchSuggestionsSectionRenderer"]["contents"] }
        let queries = groups.flatMap { $0.children("searchSuggestionRenderer") }.compactMap { $0["suggestion"].text }
        let items = groups.flatMap { $0.children("musicResponsiveListItemRenderer") }.compactMap { Renderers.listItem($0) }
        return SearchSuggestions(queries: queries, items: items)
    }

    // the unfiltered search, a top result card followed by a shelf per kind
    func searchSummary(_ query: String) async throws -> SearchSummary {
        let response = try await post("search", body: ["query": query])
        let contents = response["contents"]["tabbedSearchResultsRenderer"]["tabs"][0]["tabRenderer"]["content"]["sectionListRenderer"]["contents"]
        var summary = SearchSummary(top: nil, sections: [])
        // youtube now sends the rest as one-item sections, so they're gathered back into a shelf per kind
        var loose: [YTItem] = []
        for content in contents.array {
            let card = content["musicCardShelfRenderer"]
            if card.exists {
                summary.top = topResult(card)
                loose += card["contents"].children("musicResponsiveListItemRenderer").compactMap { Renderers.listItem($0) }
            } else if content["itemSectionRenderer"].exists {
                loose += content["itemSectionRenderer"]["contents"].children("musicResponsiveListItemRenderer").compactMap { Renderers.listItem($0) }
            } else if let section = Renderers.section(content) {
                summary.sections.append(section)
            }
        }
        let topId = summary.top?.id
        summary.sections += groupedByKind(loose.filter { $0.id != topId })
        return summary
    }

    private func groupedByKind(_ items: [YTItem]) -> [FeedSection] {
        let kinds: [(String, (YTItem) -> Bool)] = [
            (String(localized: "Songs"), { $0.song?.isVideo == false }),
            (String(localized: "Videos"), { $0.song?.isVideo == true }),
            (String(localized: "Albums"), { if case .album = $0 { true } else { false } }),
            (String(localized: "Artists"), { if case .artist = $0 { true } else { false } }),
            (String(localized: "Playlists"), { if case .playlist = $0 { true } else { false } }),
        ]
        return kinds.compactMap { title, matches in
            let picked = items.filter(matches)
            return picked.isEmpty ? nil : FeedSection(title: title, label: nil, thumbnail: nil, items: picked)
        }
    }

    func search(_ query: String, filter: SearchFilter) async throws -> SearchResult {
        var body: [String: Any] = ["query": query]
        body["params"] = filter.params
        let response = try await post("search", body: body)
        let shelf = response["contents"]["tabbedSearchResultsRenderer"]["tabs"][0]["tabRenderer"]["content"]["sectionListRenderer"]["contents"]
            .firstChild("musicShelfRenderer")
        return SearchResult(
            items: shelf["contents"].children("musicResponsiveListItemRenderer").compactMap { Renderers.listItem($0) },
            continuation: shelf.continuation
        )
    }

    func searchContinuation(_ token: String) async throws -> SearchResult {
        let response = try await post("search", body: [:], query: [
            URLQueryItem(name: "continuation", value: token),
            URLQueryItem(name: "ctoken", value: token),
        ])
        let shelf = response["continuationContents"]["musicShelfContinuation"]
        let items = shelf["contents"].children("musicResponsiveListItemRenderer").compactMap { Renderers.listItem($0) }
        return SearchResult(items: items, continuation: items.isEmpty ? nil : shelf.continuation)
    }

    func album(_ browseId: String) async throws -> AlbumPage {
        let response = try await post("browse", body: ["browseId": browseId])
        let columns = response["contents"]["twoColumnBrowseResultsRenderer"]
        let header = columns["tabs"][0]["tabRenderer"]["content"]["sectionListRenderer"]["contents"].firstChild("musicResponsiveHeaderRenderer")
        guard let title = header["title"].text else { throw InnerTubeError.missing("album title") }

        let canonical = response["microformat"]["microformatDataRenderer"]["urlCanonical"].string
        let playlistId = canonical?.components(separatedBy: "list=").last
        let album = AlbumItem(
            browseId: browseId,
            playlistId: playlistId,
            title: title,
            artists: header["straplineTextOne"].runs.namesOnly.asArtists,
            year: header["subtitle"].runs.last.flatMap { Int($0.text) },
            thumbnail: header["thumbnail"].thumbnailURL ?? ""
        )
        let secondary = columns["secondaryContents"]["sectionListRenderer"]["contents"]
        let tracks = secondary.firstChild("musicShelfRenderer")["contents"].children("musicResponsiveListItemRenderer")
        let songs = tracks.compactMap { Renderers.listItem($0, album: album)?.song }
        let others = secondary.array.compactMap(Renderers.section).first?.items ?? []
        return AlbumPage(album: album, songs: songs, otherVersions: others, description: header["description"]["musicDescriptionShelfRenderer"]["description"].text)
    }

    func artist(_ browseId: String) async throws -> ArtistPage {
        let response = try await post("browse", body: ["browseId": browseId])
        let header = response["header"]["musicImmersiveHeaderRenderer"].exists
            ? response["header"]["musicImmersiveHeaderRenderer"]
            : response["header"]["musicVisualHeaderRenderer"]
        guard let name = header["title"].text else { throw InnerTubeError.missing("artist name") }
        let contents = response["contents"]["singleColumnBrowseResultsRenderer"]["tabs"][0]["tabRenderer"]["content"]["sectionListRenderer"]["contents"]
        let subscribe = header["subscriptionButton"]["subscribeButtonRenderer"]
        return ArtistPage(
            artist: ArtistItem(id: browseId, title: name, thumbnail: header["thumbnail"].thumbnailURL ?? header["foregroundThumbnail"].thumbnailURL),
            banner: header["thumbnail"].thumbnailURL,
            subscribers: subscribe["longSubscriberCountText"].text ?? subscribe["shortSubscriberCountText"].text,
            monthlyListeners: header["monthlyListenerCount"].text,
            description: header["description"].text ?? contents.firstChild("musicDescriptionShelfRenderer")["description"].text,
            shuffleEndpoint: watchEndpoint(header["playButton"]["buttonRenderer"]["navigationEndpoint"]),
            radioEndpoint: watchEndpoint(header["startRadioButton"]["buttonRenderer"]["navigationEndpoint"]),
            sections: contents.array.compactMap(Renderers.section)
        )
    }

    func playlist(_ playlistId: String) async throws -> PlaylistPage {
        let response = try await post("browse", body: ["browseId": "VL\(playlistId)"])
        let columns = response["contents"]["twoColumnBrowseResultsRenderer"]
        let base = columns["tabs"][0]["tabRenderer"]["content"]["sectionListRenderer"]["contents"][0]
        let header = base["musicResponsiveHeaderRenderer"].exists
            ? base["musicResponsiveHeaderRenderer"]
            : base["musicEditablePlaylistDetailHeaderRenderer"]["header"]["musicResponsiveHeaderRenderer"]
        guard let title = header["title"].text else { throw InnerTubeError.missing("playlist title") }
        let shelf = columns["secondaryContents"]["sectionListRenderer"]["contents"][0]["musicPlaylistShelfRenderer"]
        return PlaylistPage(
            playlist: PlaylistItem(
                id: playlistId,
                title: title,
                author: header["straplineTextOne"].text,
                songCountText: header["secondSubtitle"].runs.first?.text,
                thumbnail: header["thumbnail"].thumbnailURL
            ),
            songs: shelf["contents"].children("musicResponsiveListItemRenderer").compactMap { Renderers.listItem($0)?.song },
            continuation: shelf["contents"].continuation ?? shelf.continuation
        )
    }

    func playlistContinuation(_ token: String) async throws -> ([SongItem], String?) {
        let response = try await post("browse", body: [:], query: [
            URLQueryItem(name: "continuation", value: token),
            URLQueryItem(name: "ctoken", value: token),
        ])
        let appended = response["onResponseReceivedActions"][0]["appendContinuationItemsAction"]["continuationItems"]
        if appended.exists {
            return (appended.children("musicResponsiveListItemRenderer").compactMap { Renderers.listItem($0)?.song }, appended.continuation)
        }
        let shelf = response["continuationContents"]["musicPlaylistShelfContinuation"]
        return (shelf["contents"].children("musicResponsiveListItemRenderer").compactMap { Renderers.listItem($0)?.song }, shelf.continuation)
    }

    // the up next list youtube builds for a song or playlist, this is what radio and autoplay run on
    func next(_ endpoint: WatchEndpoint, continuation: String? = nil) async throws -> NextResult {
        var body: [String: Any] = ["enablePersistentPlaylistPanel": true, "isAudioOnly": true]
        body["videoId"] = endpoint.videoId
        body["playlistId"] = endpoint.playlistId
        body["params"] = endpoint.params
        body["index"] = endpoint.index
        body["continuation"] = continuation
        let response = try await post("next", body: body)

        let tabs = response["contents"]["singleColumnMusicWatchNextResultsRenderer"]["tabbedRenderer"]["watchNextTabbedResultsRenderer"]["tabs"]
        let panel = response["continuationContents"]["playlistPanelContinuation"].exists
            ? response["continuationContents"]["playlistPanelContinuation"]
            : tabs[0]["tabRenderer"]["content"]["musicQueueRenderer"]["content"]["playlistPanelRenderer"]

        var items: [SongItem] = []
        var currentIndex: Int?
        for content in panel["contents"].array {
            let renderer = content["playlistPanelVideoRenderer"].exists
                ? content["playlistPanelVideoRenderer"]
                : content["playlistPanelVideoWrapperRenderer"]["primaryRenderer"]["playlistPanelVideoRenderer"]
            guard let song = Renderers.queueItem(renderer) else { continue }
            if renderer["selected"].bool == true { currentIndex = items.count }
            items.append(song)
        }

        // a single song's radio ends in an automix preview, that's where the real endless list lives
        let automix = panel["contents"].last["automixPreviewVideoRenderer"]["content"]["automixPlaylistVideoRenderer"]["navigationEndpoint"]["watchPlaylistEndpoint"]
        if continuation == nil, let playlistId = automix["playlistId"].string {
            let mix = try await next(WatchEndpoint(playlistId: playlistId, params: automix["params"].string))
            let known = Set(items.map(\.id))
            return NextResult(
                items: items + mix.items.filter { !known.contains($0.id) },
                currentIndex: currentIndex,
                continuation: mix.continuation,
                lyricsBrowseId: tabs[1]["tabRenderer"]["endpoint"]["browseEndpoint"]["browseId"].string,
                relatedBrowseId: tabs[2]["tabRenderer"]["endpoint"]["browseEndpoint"]["browseId"].string
            )
        }
        return NextResult(
            items: items,
            currentIndex: currentIndex,
            continuation: panel.continuation,
            lyricsBrowseId: tabs[1]["tabRenderer"]["endpoint"]["browseEndpoint"]["browseId"].string,
            relatedBrowseId: tabs[2]["tabRenderer"]["endpoint"]["browseEndpoint"]["browseId"].string
        )
    }

    // youtube's own plain lyrics, the fallback when no synced ones turn up
    func lyrics(browseId: String) async throws -> String? {
        let response = try await post("browse", body: ["browseId": browseId])
        return response["contents"]["sectionListRenderer"]["contents"][0]["musicDescriptionShelfRenderer"]["description"].text
    }

    private func topResult(_ card: JSON) -> YTItem? {
        let endpoint = card["title"].runs.first?.endpoint ?? JSON(nil)
        let title = card["title"].text ?? ""
        let subtitle = card["subtitle"].runs
        let thumbnail = card["thumbnail"].thumbnailURL
        if let videoId = endpoint["watchEndpoint"]["videoId"].string {
            let artists = subtitle.filter { $0.browseId?.hasPrefix("UC") == true }.asArtists
            return .song(SongItem(
                id: videoId,
                title: title,
                artists: artists.isEmpty ? subtitle.splitBySeparator().dropFirst().first?.namesOnly.asArtists ?? [] : artists,
                album: subtitle.first { $0.browseId?.hasPrefix("MPREb_") == true }.flatMap { run in run.browseId.map { AlbumRef(name: run.text, id: $0) } },
                duration: subtitle.last?.text.parsedDuration,
                thumbnail: thumbnail ?? "",
                musicVideoType: endpoint["watchEndpoint"]["watchEndpointMusicSupportedConfigs"]["watchEndpointMusicConfig"]["musicVideoType"].string
            ))
        }
        guard let browseId = endpoint["browseEndpoint"]["browseId"].string else { return nil }
        switch endpoint.pageType {
        case "MUSIC_PAGE_TYPE_ARTIST":
            return .artist(ArtistItem(id: browseId, title: title, thumbnail: thumbnail, subtitle: card["subtitle"].text))
        case "MUSIC_PAGE_TYPE_ALBUM", "MUSIC_PAGE_TYPE_AUDIOBOOK":
            return .album(AlbumItem(browseId: browseId, title: title, artists: subtitle.filter { $0.browseId != nil }.asArtists, thumbnail: thumbnail ?? ""))
        case "MUSIC_PAGE_TYPE_PLAYLIST":
            return .playlist(PlaylistItem(id: String(browseId.trimmingPrefix("VL")), title: title, author: subtitle.last?.text, thumbnail: thumbnail))
        default:
            return nil
        }
    }

    private func watchEndpoint(_ navigation: JSON) -> WatchEndpoint? {
        let endpoint = navigation["watchEndpoint"].exists ? navigation["watchEndpoint"] : navigation["watchPlaylistEndpoint"]
        guard endpoint.exists else { return nil }
        return WatchEndpoint(videoId: endpoint["videoId"].string, playlistId: endpoint["playlistId"].string, params: endpoint["params"].string)
    }
}
