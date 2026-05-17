import SwiftUI

struct LocalPlaylistView: View {
    let playlistId: String

    @Environment(Library.self) private var library
    @Environment(PlayerModel.self) private var player
    @Environment(Router.self) private var router
    @State private var songs: [SongItem] = []
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        let playlist = library.playlist(id: playlistId)
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 22) {
                CollectionHeader(
                    thumbnail: songs.first?.thumbnail,
                    kind: "Playlist",
                    title: playlist?.name ?? "",
                    subtitle: nil,
                    detail: String(localized: "\(songs.count) songs"),
                    onPlay: { if !songs.isEmpty { player.play(songs, title: playlist?.name) } },
                    onShuffle: { if !songs.isEmpty { player.play(songs.shuffled(), title: playlist?.name) } }
                )
                .contextMenu {
                    Button("Rename…") { newName = playlist?.name ?? ""; renaming = true }
                    Button("Delete Playlist", role: .destructive) {
                        if let playlist { library.delete(playlist) }
                        router.pop()
                    }
                }
                if songs.isEmpty {
                    ContentUnavailableView("Nothing here yet", systemImage: "music.note.list", description: Text("Right-click any song and choose Add to Playlist."))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { offset, song in
                            SongRow(song: song) { player.play(songs, startAt: offset, title: playlist?.name) }
                                .contextMenu {
                                    ItemMenu(item: .song(song))
                                    Divider()
                                    Button("Remove from This Playlist", role: .destructive) {
                                        if let playlist { library.remove(song.id, from: playlist) }
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, Theme.gutter - 10)
                }
            }
            .padding(.bottom, Theme.bottomBarRoom)
        }
        .background(alignment: .top) { CoverBackdrop(thumbnail: songs.first?.thumbnail) }
        .scrollIndicators(.never)
        .task(id: library.playlistsVersion) { songs = library.songs(ids: playlist?.songIds ?? []) }
        .alert("Rename playlist", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let playlist, !newName.trimmingCharacters(in: .whitespaces).isEmpty { library.rename(playlist, to: newName) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct LikedSongsView: View {
    @Environment(Library.self) private var library
    @Environment(PlayerModel.self) private var player
    @State private var songs: [SongItem] = []

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 22) {
                CollectionHeader(
                    thumbnail: nil,
                    kind: "Playlist",
                    title: String(localized: "Liked songs"),
                    subtitle: nil,
                    detail: String(localized: "\(songs.count) songs"),
                    gradientCover: true,
                    onPlay: { if !songs.isEmpty { player.play(songs, title: String(localized: "Liked songs")) } },
                    onShuffle: { if !songs.isEmpty { player.play(songs.shuffled(), title: String(localized: "Liked songs")) } }
                )
                if songs.isEmpty {
                    ContentUnavailableView("No liked songs yet", systemImage: "heart", description: Text("Tap the heart on a song and it lands here."))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                } else {
                    SongList(songs: songs, title: String(localized: "Liked songs"))
                }
            }
            .padding(.bottom, Theme.bottomBarRoom)
        }
        .scrollIndicators(.never)
        .task(id: library.likedIds) { songs = library.likedSongs() }
    }
}

struct HistoryView: View {
    @Environment(Library.self) private var library
    @State private var songs: [SongItem] = []

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 22) {
                PageTitle(title: "History", subtitle: String(localized: "The songs you played, newest first"))
                    .padding(.horizontal, Theme.gutter)
                    .padding(.top, 64)
                if songs.isEmpty {
                    ContentUnavailableView("Nothing played yet", systemImage: "clock", description: Text("Songs you play show up here."))
                        .frame(maxWidth: .infinity)
                } else {
                    SongList(songs: songs, title: String(localized: "History"))
                }
            }
            .padding(.bottom, Theme.bottomBarRoom)
        }
        .scrollIndicators(.never)
        .task(id: library.historyVersion) { songs = library.recentSongs(limit: 300) }
    }
}

// the month so far in music: plays, minutes, your top songs and artists
struct RecapView: View {
    @Environment(Library.self) private var library
    @Environment(PlayerModel.self) private var player
    @Environment(Router.self) private var router
    @State private var recap: MonthRecap?

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 30) {
                if let recap {
                    header(recap)
                    if recap.isEmpty {
                        ContentUnavailableView("Your month starts now", systemImage: "sparkles", description: Text("Play a few songs and your recap fills in as you listen."))
                            .frame(maxWidth: .infinity)
                    } else {
                        stats(recap)
                        topSongs(recap)
                        topArtists(recap)
                    }
                }
            }
            .padding(.bottom, Theme.bottomBarRoom)
        }
        .scrollIndicators(.never)
        .background(alignment: .top) { CoverBackdrop(thumbnail: recap?.topSongs.first?.song.thumbnail) }
        .task(id: library.historyVersion) { recap = library.recap() }
    }

    private func header(_ recap: MonthRecap) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(recap.month.formatted(.dateTime.month(.wide).year()).uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(2.4)
                .foregroundStyle(.white.opacity(0.7))
            Text("Your month recap")
                .font(.system(size: 44, weight: .bold))
                .tracking(-1)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 70)
    }

    private func stats(_ recap: MonthRecap) -> some View {
        HStack(spacing: 14) {
            StatTile(value: "\(recap.plays)", label: "plays")
            StatTile(value: "\(recap.minutes)", label: "minutes")
            StatTile(value: "\(recap.topSongs.count)", label: "different songs")
            StatTile(value: "\(recap.topArtists.count)", label: "artists")
        }
        .padding(.horizontal, Theme.gutter)
    }

    private func topSongs(_ recap: MonthRecap) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: String(localized: "Top songs"))
                Spacer()
                CapsuleButton(title: "Play all", systemImage: "play.fill", prominent: true) {
                    player.play(recap.topSongs.map(\.song), title: String(localized: "Your top songs this month"))
                }
            }
            .padding(.horizontal, Theme.gutter)
            LazyVStack(spacing: 2) {
                ForEach(Array(recap.topSongs.enumerated()), id: \.element.song.id) { offset, entry in
                    HStack(spacing: 0) {
                        SongRow(song: entry.song, number: offset + 1) {
                            player.play(recap.topSongs.map(\.song), startAt: offset, title: String(localized: "Your top songs this month"))
                        }
                        Text("\(entry.plays)×")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Theme.tertiaryText)
                            .frame(width: 40)
                    }
                }
            }
            .padding(.horizontal, Theme.gutter - 10)
        }
    }

    private func topArtists(_ recap: MonthRecap) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: String(localized: "Top artists"))
            WordFlow(alignment: .leading, spacing: 10, lineSpacing: 10) {
                ForEach(Array(recap.topArtists.enumerated()), id: \.offset) { offset, artist in
                    Button {
                        if let id = artist.id { router.push(.artist(id)) }
                    } label: {
                        HStack(spacing: 8) {
                            Text("\(offset + 1)").font(.system(size: 11, weight: .bold).monospacedDigit()).foregroundStyle(Theme.tertiaryText)
                            Text(artist.name).font(.system(size: 13, weight: .semibold))
                            Text("\(artist.plays)").font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.secondaryText)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Capsule().fill(Theme.surface))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
    }
}

private struct StatTile: View {
    let value: String
    let label: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 30, weight: .bold).monospacedDigit()).tracking(-0.5)
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}
