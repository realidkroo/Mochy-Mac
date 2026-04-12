import SwiftUI

@Observable
final class SearchModel {
    var query = ""
    private(set) var submitted: String?
    private(set) var suggestions: SearchSuggestions?
    private(set) var summary: SearchSummary?
    private(set) var results: SearchResult?
    private(set) var filter: SearchFilter = .all
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var recent: [String] = UserDefaults.standard.stringArray(forKey: "recentSearches") ?? []

    var showsSuggestions: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty && query != submitted }

    func suggest() async {
        let input = query.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty, input != submitted else { suggestions = nil; return }
        // waits for a pause in typing so every key doesn't fire a request
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }
        suggestions = try? await InnerTube.shared.searchSuggestions(input)
    }

    func submit(_ text: String? = nil) async {
        let term = (text ?? query).trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        query = term
        submitted = term
        suggestions = nil
        remember(term)
        await run()
    }

    func choose(_ newFilter: SearchFilter) async {
        guard newFilter != filter else { return }
        filter = newFilter
        await run()
    }

    func clear() {
        query = ""
        submitted = nil
        summary = nil
        results = nil
        suggestions = nil
        filter = .all
    }

    func loadMore() async {
        guard let token = results?.continuation else { return }
        guard let more = try? await InnerTube.shared.searchContinuation(token) else { return }
        results?.items.append(contentsOf: more.items)
        results?.continuation = more.continuation
    }

    func forget(_ term: String) {
        recent.removeAll { $0 == term }
        UserDefaults.standard.set(recent, forKey: "recentSearches")
    }

    private func run() async {
        guard let term = submitted else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if filter == .all {
                summary = try await InnerTube.shared.searchSummary(term)
            } else {
                results = nil
                results = try await InnerTube.shared.search(term, filter: filter)
            }
        } catch {
            errorMessage = String(localized: "Search didn't go through. Check your connection and try again.")
        }
    }

    private func remember(_ term: String) {
        recent.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }
        recent.insert(term, at: 0)
        recent = Array(recent.prefix(20))
        UserDefaults.standard.set(recent, forKey: "recentSearches")
    }
}

struct SearchView: View {
    @State private var model = SearchModel()
    @FocusState private var fieldFocused: Bool
    @Environment(Router.self) private var router
    @Environment(\.showsSidebar) private var showsSidebar

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 22) {
                PageTitle(title: "Search")
                    .padding(.horizontal, Theme.gutter)
                searchField
                    .padding(.horizontal, Theme.gutter)
                Group {
                    if model.showsSuggestions {
                        SuggestionList(model: model)
                    } else if model.submitted != nil {
                        SearchResults(model: model)
                    } else {
                        RecentSearches(model: model)
                    }
                }
                .animation(.easeOut(duration: 0.18), value: model.showsSuggestions)
            }
            .padding(.top, showsSidebar ? 34 : 56)
            .padding(.bottom, Theme.bottomBarRoom)
        }
        .scrollIndicators(.never)
        .task(id: model.query) { await model.suggest() }
        .onChange(of: router.searchFocusRequest) { fieldFocused = true }
        .onAppear { if model.submitted == nil { fieldFocused = true } }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            IconShape(icon: .search)
                .fill(Theme.secondaryText)
                .frame(width: 15, height: 15)
            TextField("Songs, artists, albums, playlists", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium))
                .focused($fieldFocused)
                .onSubmit { Task { await model.submit() } }
            if !model.query.isEmpty {
                Button { model.clear(); fieldFocused = true } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
            }
            if model.isLoading { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .frame(maxWidth: 640)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(fieldFocused ? Color.white.opacity(0.35) : Theme.hairline, lineWidth: 1))
        .animation(.easeOut(duration: 0.15), value: fieldFocused)
    }
}

private struct RecentSearches: View {
    let model: SearchModel

    var body: some View {
        if model.recent.isEmpty {
            ContentUnavailableView("Find your next favourite", systemImage: "music.magnifyingglass", description: Text("Search for songs, artists, albums and playlists on YouTube Music."))
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: String(localized: "Recent searches"))
                FlowChips(terms: model.recent, model: model)
            }
            .padding(.horizontal, Theme.gutter)
        }
    }
}

private struct FlowChips: View {
    let terms: [String]
    let model: SearchModel

    var body: some View {
        WordFlow(alignment: .leading, spacing: 8, lineSpacing: 8) {
            ForEach(terms, id: \.self) { term in
                CapsuleButton(verbatim: term) { Task { await model.submit(term) } }
                    .contextMenu { Button("Remove from Recents") { model.forget(term) } }
            }
        }
    }
}

private struct SuggestionList: View {
    let model: SearchModel

    @Environment(PlayerModel.self) private var player
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(model.suggestions?.queries ?? [], id: \.self) { term in
                SuggestionRow(icon: "magnifyingglass", text: term) { Task { await model.submit(term) } }
            }
            if let items = model.suggestions?.items, !items.isEmpty {
                Divider().padding(.vertical, 6).padding(.horizontal, 10)
                ForEach(items) { item in
                    SuggestionItemRow(item: item) {
                        if let song = item.song { player.play(song) } else { router.open(item) }
                    }
                }
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
        .padding(.horizontal, Theme.gutter - 10)
    }
}

private struct SuggestionRow: View {
    let icon: String
    let text: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondaryText).frame(width: 20)
                Text(text).font(.system(size: 14, weight: .medium))
                Spacer()
                Image(systemName: "arrow.up.left").font(.system(size: 11)).foregroundStyle(Theme.tertiaryText)
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 9).fill(isHovered ? Theme.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct SuggestionItemRow: View {
    let item: YTItem
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RemoteImage(url: item.thumbnail, size: 36)
                    .frame(width: 34, height: 34)
                    .clipShape(kindShape)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.system(size: 13, weight: .semibold))
                    Text(kind).font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                }
                .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 9).fill(isHovered ? Theme.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu { ItemMenu(item: item) }
    }

    private var kindShape: AnyShape {
        if case .artist = item { return AnyShape(Circle()) }
        return AnyShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var kind: String {
        switch item {
        case .song(let song): (song.isVideo ? String(localized: "Video") : String(localized: "Song")) + " · " + song.artistNames
        case .album(let album): String(localized: "Album") + " · " + album.artists.map(\.name).joined(separator: ", ")
        case .artist: String(localized: "Artist")
        case .playlist(let playlist): String(localized: "Playlist") + (playlist.author.map { " · " + $0 } ?? "")
        }
    }
}

private struct SearchResults: View {
    let model: SearchModel

    @Environment(PlayerModel.self) private var player

    private let filters: [(SearchFilter, LocalizedStringKey)] = [
        (.all, "All"), (.songs, "Songs"), (.videos, "Videos"), (.albums, "Albums"), (.artists, "Artists"), (.playlists, "Playlists"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 8) {
                ForEach(filters, id: \.0) { filter, title in
                    CapsuleButton(title: title, isSelected: model.filter == filter) { Task { await model.choose(filter) } }
                }
            }
            .padding(.horizontal, Theme.gutter)

            if let message = model.errorMessage {
                LoadState(errorMessage: message) { Task { await model.submit() } }.frame(height: 200)
            } else if model.filter == .all {
                summary
            } else {
                filtered
            }
        }
    }

    @ViewBuilder
    private var summary: some View {
        if let summary = model.summary {
            let songsSection = summary.sections.first { $0.isAllSongs }
            HStack(alignment: .top, spacing: 24) {
                if let top = summary.top {
                    TopResultCard(item: top)
                        .frame(width: 300)
                }
                if let songsSection {
                    let songs = songsSection.items.compactMap(\.song)
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(title: songsSection.title)
                            .padding(.leading, 10)
                        ForEach(Array(songs.prefix(4).enumerated()), id: \.element.id) { offset, song in
                            SongRow(song: song, showsAlbum: false) { player.play(songs, startAt: offset) }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)

            ForEach(summary.sections.filter { $0.id != songsSection?.id }) { section in
                if section.isAllSongs {
                    let songs = section.items.compactMap(\.song)
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(title: section.title).padding(.leading, 10)
                        ForEach(Array(songs.prefix(6).enumerated()), id: \.element.id) { offset, song in
                            SongRow(song: song) { player.play(songs, startAt: offset) }
                        }
                    }
                    .padding(.horizontal, Theme.gutter - 10)
                } else {
                    Shelf(title: section.title, items: section.items)
                }
            }
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.top, 40)
        }
    }

    @ViewBuilder
    private var filtered: some View {
        if let results = model.results {
            let songs = results.items.compactMap(\.song)
            if songs.count == results.items.count {
                LazyVStack(spacing: 2) {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { offset, song in
                        SongRow(song: song) { player.play(songs, startAt: offset) }
                    }
                    if results.continuation != nil {
                        ProgressView().controlSize(.small).padding().task { await model.loadMore() }
                    }
                }
                .padding(.horizontal, Theme.gutter - 10)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 18, alignment: .top)], alignment: .leading, spacing: 24) {
                    ForEach(results.items) { item in CoverCard(item: item, size: 150) }
                    if results.continuation != nil {
                        ProgressView().controlSize(.small).task { await model.loadMore() }
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.top, 40)
        }
    }
}

// the big card for the best match, with a play button that's always there
private struct TopResultCard: View {
    let item: YTItem

    @Environment(PlayerModel.self) private var player
    @Environment(Router.self) private var router
    @State private var isHovered = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Top result").font(.system(size: 15, weight: .bold))
                RemoteImage(url: item.thumbnail, size: 110)
                    .frame(width: 104, height: 104)
                    .clipShape(isArtist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 12, style: .continuous)))
                    .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.system(size: 24, weight: .bold)).lineLimit(2)
                    Text(kind).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(isHovered ? Color(white: 0.15) : Color(white: 0.1)))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(.white))
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                    .padding(18)
                    .opacity(isHovered ? 1 : 0)
                    .offset(y: isHovered ? 0 : 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.99))
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isHovered)
        .contextMenu { ItemMenu(item: item) }
    }

    private var isArtist: Bool { if case .artist = item { true } else { false } }

    private var kind: String {
        switch item {
        case .song(let song): (song.isVideo ? String(localized: "Video") : String(localized: "Song")) + " · " + song.artistNames
        case .album(let album): String(localized: "Album") + " · " + album.artists.map(\.name).joined(separator: ", ")
        case .artist: String(localized: "Artist")
        case .playlist(let playlist): String(localized: "Playlist") + (playlist.author.map { " · " + $0 } ?? "")
        }
    }

    private func open() {
        if let song = item.song { player.play(song) } else { router.open(item) }
    }
}
