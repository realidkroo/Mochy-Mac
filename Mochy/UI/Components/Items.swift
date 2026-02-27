import SwiftUI

// a square card for anything in a shelf: a song plays, the rest open their page
struct CoverCard: View {
    let item: YTItem
    var size: CGFloat = 148
    var queue: [SongItem]? = nil

    @Environment(PlayerModel.self) private var player
    @Environment(Router.self) private var router
    @State private var isHovered = false

    private var isArtist: Bool { if case .artist = item { true } else { false } }
    private var isCurrent: Bool { item.song?.id == player.current?.id && item.song != nil }

    var body: some View {
        Button(action: open) {
            VStack(alignment: isArtist ? .center : .leading, spacing: 7) {
                ZStack(alignment: .bottomTrailing) {
                    RemoteImage(url: item.thumbnail, size: size)
                        .frame(width: size, height: size)
                        .clipShape(isArtist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 12, style: .continuous)))
                        .overlay {
                            if isCurrent {
                                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.35))
                                PlayingBars(isPlaying: player.isPlaying)
                            }
                        }
                    if !isArtist {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(.white))
                            .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
                            .padding(8)
                            .opacity(isHovered ? 1 : 0)
                            .offset(y: isHovered ? 0 : 6)
                            .onTapGesture(perform: play)
                    }
                }
                .scaleEffect(isHovered ? 1.025 : 1)
                .shadow(color: .black.opacity(isHovered ? 0.45 : 0), radius: 14, y: 8)

                VStack(alignment: isArtist ? .center : .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .lineLimit(1)
                .frame(width: size, alignment: isArtist ? .center : .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isHovered)
        .contextMenu { ItemMenu(item: item) }
    }

    private var subtitle: String? {
        switch item {
        case .song(let song): song.artistNames
        case .album(let album): [album.artists.map(\.name).joined(separator: ", ").nilIfEmpty, album.year.map(String.init)].compactMap { $0 }.joined(separator: " · ")
        case .artist(let artist): artist.subtitle
        case .playlist(let playlist): playlist.author
        }
    }

    private func open() {
        if let song = item.song {
            if let queue, let start = queue.firstIndex(of: song) {
                player.play(queue, startAt: start)
            } else {
                player.play(song)
            }
        } else {
            router.open(item)
        }
    }

    private func play() {
        switch item {
        case .song: open()
        case .album(let album):
            if let playlistId = album.playlistId {
                player.play(endpoint: WatchEndpoint(playlistId: playlistId), title: album.title)
            } else {
                router.open(item)
            }
        case .playlist(let playlist):
            player.play(endpoint: WatchEndpoint(playlistId: playlist.id), title: playlist.title)
        case .artist: router.open(item)
        }
    }
}

// a long row for songs in lists: number or cover, title, artist, album, length, and the heart
struct SongRow: View {
    let song: SongItem
    var number: Int? = nil
    var showsAlbum = true
    let onPlay: () -> Void

    @Environment(PlayerModel.self) private var player
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @State private var isHovered = false

    var body: some View {
        let isCurrent = player.current?.id == song.id
        HStack(spacing: 12) {
            ZStack {
                if let number, !isHovered, !isCurrent {
                    Text("\(number)")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                } else if number != nil {
                    if isCurrent { PlayingBars(isPlaying: player.isPlaying) } else {
                        Image(systemName: "play.fill").font(.system(size: 11))
                    }
                } else {
                    RemoteImage(url: song.thumbnail, size: 40)
                        .frame(width: 38, height: 38)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            if isCurrent || isHovered {
                                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.black.opacity(0.45))
                                if isCurrent { PlayingBars(isPlaying: player.isPlaying) } else { Image(systemName: "play.fill").font(.system(size: 11)) }
                            }
                        }
                }
            }
            .frame(width: number == nil ? 38 : 22, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(song.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isCurrent ? Color.white : Color.white.opacity(0.95))
                    if song.explicit {
                        Text("E").font(.system(size: 8, weight: .heavy)).foregroundStyle(.black)
                            .frame(width: 12, height: 12).background(RoundedRectangle(cornerRadius: 2).fill(Theme.secondaryText))
                    }
                }
                Text(song.artistNames)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryText)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsAlbum, let album = song.album {
                Button(album.name) { router.push(.album(album.id)) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .frame(maxWidth: 220, alignment: .leading)
            }

            Button { library.toggleLike(song) } label: {
                Image(systemName: library.isLiked(song.id) ? "heart.fill" : "heart")
                    .font(.system(size: 12))
                    .foregroundStyle(library.isLiked(song.id) ? Color.pink : Theme.secondaryText)
            }
            .buttonStyle(.plain)
            .opacity(isHovered || library.isLiked(song.id) ? 1 : 0)

            Text(song.duration.map { TimeInterval($0).clock } ?? "")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 42, alignment: .trailing)

            Menu {
                ItemMenu(item: .song(song))
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 12, weight: .bold)).frame(width: 22, height: 22)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .foregroundStyle(Theme.secondaryText)
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 52)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(isHovered ? Theme.hover : .clear))
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onPlay)
        .onHover { isHovered = $0 }
        .contextMenu { ItemMenu(item: .song(song)) }
        .overlay(alignment: .leading) {
            // a single click on the number or cover plays too, double click anywhere does
            Color.clear
                .frame(width: number == nil ? 58 : 42)
                .contentShape(Rectangle())
                .onTapGesture(perform: onPlay)
        }
    }
}

// the right-click menu for any item, the same everywhere
struct ItemMenu: View {
    let item: YTItem

    @Environment(PlayerModel.self) private var player
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router

    var body: some View {
        switch item {
        case .song(let song):
            Button("Play", systemImage: "play") { player.play(song) }
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") { player.playNext(song) }
            Button("Add to Queue", systemImage: "text.append") { player.addToQueue(song) }
            Button("Start Radio", systemImage: "dot.radiowaves.left.and.right") { player.startRadio(for: song) }
            Divider()
            Button(library.isLiked(song.id) ? "Remove from Liked Songs" : "Add to Liked Songs", systemImage: library.isLiked(song.id) ? "heart.slash" : "heart") { library.toggleLike(song) }
            Button("Add to Playlist…", systemImage: "text.badge.plus") { router.addToPlaylist = song }
            Divider()
            if let artist = song.artists.first(where: { $0.id != nil }), let id = artist.id {
                Button("Go to \(artist.name)", systemImage: "person") { router.push(.artist(id)) }
            }
            if let album = song.album {
                Button("Go to Album", systemImage: "square.stack") { router.push(.album(album.id)) }
            }
            Button("Copy Link", systemImage: "link") { copy("https://music.youtube.com/watch?v=\(song.id)") }
        case .album(let album):
            Button("Open", systemImage: "square.stack") { router.open(item) }
            if let playlistId = album.playlistId {
                Button("Play", systemImage: "play") { player.play(endpoint: WatchEndpoint(playlistId: playlistId), title: album.title) }
            }
            Button("Copy Link", systemImage: "link") { copy("https://music.youtube.com/browse/\(album.browseId)") }
        case .artist(let artist):
            Button("Open", systemImage: "person") { router.open(item) }
            Button("Copy Link", systemImage: "link") { copy("https://music.youtube.com/channel/\(artist.id)") }
        case .playlist(let playlist):
            Button("Open", systemImage: "music.note.list") { router.open(item) }
            Button("Play", systemImage: "play") { player.play(endpoint: WatchEndpoint(playlistId: playlist.id), title: playlist.title) }
            Button("Copy Link", systemImage: "link") { copy("https://music.youtube.com/playlist?list=\(playlist.id)") }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// a titled row of cards that scrolls sideways, with arrows for people without a trackpad
struct Shelf: View {
    let title: String
    var label: String? = nil
    let items: [YTItem]
    var cardSize: CGFloat = 148
    var onMore: (() -> Void)? = nil

    @State private var scrolledId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    if let label {
                        Text(label.uppercased())
                            .font(.system(size: 10.5, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(Theme.tertiaryText)
                    }
                    SectionHeader(title: title, action: onMore)
                }
                Spacer()
                pager
            }
            .padding(.horizontal, Theme.gutter)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(items) { item in
                        CoverCard(item: item, size: cardSize, queue: songQueue)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.never)
            .scrollPosition(id: $scrolledId, anchor: .leading)
            .scrollClipDisabled()
        }
    }

    // songs in a shelf play as one queue, so the next card is up next
    private var songQueue: [SongItem]? {
        let songs = items.compactMap(\.song)
        return songs.count == items.count ? songs : nil
    }

    private var pager: some View {
        HStack(spacing: 4) {
            BarButton(systemImage: "chevron.left", size: 24, iconSize: 10) { page(-1) }
            BarButton(systemImage: "chevron.right", size: 24, iconSize: 10) { page(1) }
        }
        .opacity(items.count > 4 ? 1 : 0)
    }

    private func page(_ direction: Int) {
        let current = items.firstIndex { $0.id == scrolledId } ?? 0
        let target = min(max(current + direction * 4, 0), max(items.count - 1, 0))
        withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { scrolledId = items[target].id }
    }
}

// youtube's quick picks: songs four to a column, paged sideways
struct QuickPicks: View {
    let section: FeedSection

    @Environment(PlayerModel.self) private var player

    var body: some View {
        let songs = section.items.compactMap(\.song)
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: section.title)
                .padding(.horizontal, Theme.gutter)
            ScrollView(.horizontal) {
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(52), spacing: 2), count: min(4, max(songs.count, 1))), spacing: 14) {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { offset, song in
                        SongRow(song: song, showsAlbum: false) { player.play(songs, startAt: offset, title: section.title) }
                            .frame(width: 340)
                    }
                }
                .padding(.horizontal, Theme.gutter - 10)
            }
            .scrollIndicators(.never)
        }
    }
}
