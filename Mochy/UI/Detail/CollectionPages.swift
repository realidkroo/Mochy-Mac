import SwiftUI

struct AlbumView: View {
    let browseId: String

    @Environment(PlayerModel.self) private var player
    @Environment(Router.self) private var router
    @State private var page: AlbumPage?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let page {
                content(page)
            } else {
                LoadState(errorMessage: errorMessage) { Task { await load() } }
            }
        }
        .task { await load() }
    }

    private func content(_ page: AlbumPage) -> some View {
        let album = page.album
        let totalSeconds = page.songs.compactMap(\.duration).reduce(0, +)
        let detail = [album.year.map(String.init), String(localized: "\(page.songs.count) songs"), totalSeconds > 0 ? TimeInterval(totalSeconds).clock : nil]
            .compactMap { $0 }
            .joined(separator: " · ")
        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 22) {
                CollectionHeader(
                    thumbnail: album.thumbnail,
                    kind: "Album",
                    title: album.title,
                    subtitle: album.artists.map(\.name).joined(separator: ", "),
                    detail: detail,
                    onSubtitleTap: album.artists.first?.id.map { id in { router.push(.artist(id)) } },
                    onPlay: { player.play(page.songs, title: album.title) },
                    onShuffle: { player.play(page.songs.shuffled(), title: album.title) }
                )
                SongList(songs: page.songs, title: album.title, numbered: true, showsAlbum: false)
                if let description = page.description {
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(5)
                        .padding(.horizontal, Theme.gutter)
                }
                if !page.otherVersions.isEmpty {
                    Shelf(title: String(localized: "More from this artist"), items: page.otherVersions)
                }
            }
            .padding(.bottom, Theme.bottomBarRoom)
        }
        .background(alignment: .top) { CoverBackdrop(thumbnail: album.thumbnail) }
        .scrollIndicators(.never)
    }

    private func load() async {
        errorMessage = nil
        do {
            page = try await InnerTube.shared.album(browseId)
        } catch {
            errorMessage = error.friendlyMessage
        }
    }
}

struct PlaylistView: View {
    let playlistId: String

    @Environment(PlayerModel.self) private var player
    @State private var page: PlaylistPage?
    @State private var songs: [SongItem] = []
    @State private var continuation: String?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let page {
                content(page.playlist)
            } else {
                LoadState(errorMessage: errorMessage) { Task { await load() } }
            }
        }
        .task { await load() }
    }

    private func content(_ playlist: PlaylistItem) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 22) {
                CollectionHeader(
                    thumbnail: playlist.thumbnail,
                    kind: "Playlist",
                    title: playlist.title,
                    subtitle: playlist.author,
                    detail: playlist.songCountText,
                    onPlay: { play(shuffled: false) },
                    onShuffle: { play(shuffled: true) }
                )
                SongList(songs: songs, title: playlist.title)
                if continuation != nil {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity).task { await loadMore() }
                }
            }
            .padding(.bottom, Theme.bottomBarRoom)
        }
        .background(alignment: .top) { CoverBackdrop(thumbnail: playlist.thumbnail) }
        .scrollIndicators(.never)
    }

    // a playlist radio would only be youtube's guess, so play what the playlist actually holds
    private func play(shuffled: Bool) {
        guard !songs.isEmpty else { return }
        player.play(shuffled ? songs.shuffled() : songs, title: page?.playlist.title)
    }

    private func load() async {
        errorMessage = nil
        do {
            let loaded = try await InnerTube.shared.playlist(playlistId)
            page = loaded
            songs = loaded.songs
            continuation = loaded.continuation
        } catch {
            errorMessage = error.friendlyMessage
        }
    }

    private func loadMore() async {
        guard let token = continuation else { return }
        guard let (more, next) = try? await InnerTube.shared.playlistContinuation(token) else {
            continuation = nil
            return
        }
        let known = Set(songs.map(\.id))
        songs.append(contentsOf: more.filter { !known.contains($0.id) })
        continuation = more.isEmpty ? nil : next
    }
}

struct ArtistView: View {
    let browseId: String

    @Environment(PlayerModel.self) private var player
    @State private var page: ArtistPage?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let page {
                content(page)
            } else {
                LoadState(errorMessage: errorMessage) { Task { await load() } }
            }
        }
        .task { await load() }
    }

    private func content(_ page: ArtistPage) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 30) {
                header(page)
                ForEach(page.sections) { section in
                    if section.isAllSongs {
                        let songs = section.items.compactMap(\.song)
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: section.title).padding(.horizontal, Theme.gutter)
                            SongList(songs: Array(songs.prefix(6)), title: section.title)
                        }
                    } else {
                        Shelf(title: section.title, items: section.items)
                    }
                }
                if let description = page.description {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About").font(.system(size: 15, weight: .bold))
                        Text(description)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(8)
                            .frame(maxWidth: 680, alignment: .leading)
                    }
                    .padding(.horizontal, Theme.gutter)
                }
            }
            .padding(.bottom, Theme.bottomBarRoom)
        }
        .scrollIndicators(.never)
        .ignoresSafeArea()
    }

    private func header(_ page: ArtistPage) -> some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: page.banner, size: 1100)
                .frame(height: 380)
                .frame(maxWidth: .infinity)
                .clipped()
            LinearGradient(stops: [.init(color: .black.opacity(0.2), location: 0), .init(color: .clear, location: 0.3), .init(color: .black.opacity(0.75), location: 0.8), .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                Text("Artist")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.6)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.7))
                Text(page.artist.title)
                    .font(.system(size: 58, weight: .heavy))
                    .tracking(-1.5)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                if let stats = [page.subscribers, page.monthlyListeners].compactMap({ $0 }).joined(separator: " · ").nilIfEmpty {
                    Text(stats).font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
                }
                HStack(spacing: 10) {
                    CapsuleButton(title: "Play", systemImage: "play.fill", prominent: true) {
                        if let endpoint = page.shuffleEndpoint ?? page.radioEndpoint { player.play(endpoint: endpoint, title: page.artist.title) }
                    }
                    if let radio = page.radioEndpoint {
                        CapsuleButton(title: "Radio", systemImage: "dot.radiowaves.left.and.right") { player.play(endpoint: radio, title: page.artist.title) }
                    }
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 10)
        }
    }

    private func load() async {
        errorMessage = nil
        do {
            page = try await InnerTube.shared.artist(browseId)
        } catch {
            errorMessage = error.friendlyMessage
        }
    }
}

// a shelf's "more" page, everything in it as a grid
struct SectionView: View {
    let section: FeedSection

    @State private var items: [YTItem] = []
    @State private var loaded = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 22) {
                Text(section.title)
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-0.5)
                    .padding(.horizontal, Theme.gutter)
                    .padding(.top, 64)
                let shown = items.isEmpty ? section.items : items
                if shown.allSatisfy({ $0.song != nil }) {
                    SongList(songs: shown.compactMap(\.song), title: section.title)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 18, alignment: .top)], alignment: .leading, spacing: 24) {
                        ForEach(shown) { CoverCard(item: $0, size: 150) }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
            }
            .padding(.bottom, Theme.bottomBarRoom)
        }
        .scrollIndicators(.never)
        .task {
            guard !loaded, let browseId = section.moreBrowseId else { return }
            loaded = true
            if let more = try? await InnerTube.shared.browseSection(browseId: browseId, params: section.moreParams), !more.isEmpty {
                items = more
            }
        }
    }
}

extension InnerTube {
    // a "see all" page: every shelf on it flattened into one list
    func browseSection(browseId: String, params: String?) async throws -> [YTItem] {
        var body: [String: Any] = ["browseId": browseId]
        body["params"] = params
        let response = try await post("browse", body: body)
        let contents = response["contents"]["singleColumnBrowseResultsRenderer"]["tabs"][0]["tabRenderer"]["content"]["sectionListRenderer"]["contents"]
        var items: [YTItem] = []
        for content in contents.array {
            if let section = Renderers.section(content) { items += section.items }
            let grid = content["gridRenderer"]["items"]
            for item in grid.array {
                if item["musicTwoRowItemRenderer"].exists, let parsed = Renderers.twoRowItem(item["musicTwoRowItemRenderer"]) { items.append(parsed) }
            }
        }
        return items
    }
}
