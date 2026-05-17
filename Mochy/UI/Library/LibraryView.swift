import SwiftUI

struct LibraryView: View {
    enum Shelf: Hashable { case playlists, liked, history }

    @Environment(Library.self) private var library
    @Environment(PlayerModel.self) private var player
    @Environment(Router.self) private var router
    @Environment(\.showsSidebar) private var showsSidebar
    @State private var shelf: Shelf = .playlists
    @State private var playlists: [LocalPlaylist] = []
    @State private var liked: [SongItem] = []
    @State private var history: [SongItem] = []

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 22) {
                PageTitle(title: "Library")
                    .padding(.horizontal, Theme.gutter)
                HStack(spacing: 8) {
                    CapsuleButton(title: "Playlists", isSelected: shelf == .playlists) { shelf = .playlists }
                    CapsuleButton(title: "Liked songs", isSelected: shelf == .liked) { shelf = .liked }
                    CapsuleButton(title: "History", isSelected: shelf == .history) { shelf = .history }
                }
                .padding(.horizontal, Theme.gutter)

                switch shelf {
                case .playlists: playlistGrid
                case .liked: songList(liked, title: String(localized: "Liked songs"), empty: "Songs you like show up here.")
                case .history: songList(history, title: String(localized: "History"), empty: "Songs you play show up here.")
                }
            }
            .padding(.top, showsSidebar ? 34 : 56)
            .padding(.bottom, Theme.bottomBarRoom)
        }
        .scrollIndicators(.never)
        .task(id: library.playlistsVersion &+ library.historyVersion &* 7 &+ library.likedIds.count &* 13) { reload() }
    }

    private func reload() {
        playlists = library.playlists()
        liked = library.likedSongs()
        history = library.recentSongs(limit: 200)
    }

    private var playlistGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 18, alignment: .top)], alignment: .leading, spacing: 24) {
            LibraryTile(title: String(localized: "Liked songs"), subtitle: String(localized: "\(liked.count) songs"), covers: [], gradient: true) { router.push(.liked) }
            LibraryTile(title: String(localized: "History"), subtitle: String(localized: "Recently played"), covers: history.prefix(4).map(\.thumbnail)) { router.push(.history) }
            ForEach(playlists) { playlist in
                LibraryTile(title: playlist.name, subtitle: String(localized: "\(playlist.songIds.count) songs"), covers: library.songs(ids: Array(playlist.songIds.prefix(4))).map(\.thumbnail)) {
                    router.push(.localPlaylist(playlist.id))
                }
                .contextMenu {
                    Button(playlist.isPinned ? "Unpin from Sidebar" : "Pin to Sidebar") { library.togglePin(playlist) }
                    Button("Delete Playlist", role: .destructive) { library.delete(playlist) }
                }
            }
            Button { router.newPlaylistPrompt = true } label: {
                VStack(alignment: .leading, spacing: 7) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                        .overlay(Image(systemName: "plus").font(.system(size: 24, weight: .light)).foregroundStyle(Theme.secondaryText))
                        .aspectRatio(1, contentMode: .fit)
                    Text("New playlist").font(.system(size: 12.5, weight: .semibold))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.horizontal, Theme.gutter)
    }

    @ViewBuilder
    private func songList(_ songs: [SongItem], title: String, empty: LocalizedStringKey) -> some View {
        if songs.isEmpty {
            ContentUnavailableView(title, systemImage: "music.note", description: Text(empty))
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else {
            LazyVStack(spacing: 2) {
                ForEach(Array(songs.enumerated()), id: \.element.id) { offset, song in
                    SongRow(song: song) { player.play(songs, startAt: offset, title: title) }
                }
            }
            .padding(.horizontal, Theme.gutter - 10)
        }
    }
}

// a playlist's tile: a grid of its first four covers, or a gradient for liked songs
private struct LibraryTile: View {
    let title: String
    let subtitle: String
    let covers: [String]
    var gradient = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                Group {
                    if gradient {
                        LinearGradient(colors: [Color(red: 0.98, green: 0.36, blue: 0.5), Color(red: 0.45, green: 0.28, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            .overlay(Image(systemName: "heart.fill").font(.system(size: 34)).foregroundStyle(.white))
                    } else if covers.count >= 4 {
                        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                            GridRow { RemoteImage(url: covers[0], size: 90); RemoteImage(url: covers[1], size: 90) }
                            GridRow { RemoteImage(url: covers[2], size: 90); RemoteImage(url: covers[3], size: 90) }
                        }
                    } else if let first = covers.first {
                        RemoteImage(url: first, size: 180)
                    } else {
                        Theme.surface.overlay(Image(systemName: "music.note.list").font(.system(size: 28)).foregroundStyle(Theme.secondaryText))
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .scaleEffect(isHovered ? 1.025 : 1)
                .shadow(color: .black.opacity(isHovered ? 0.45 : 0), radius: 14, y: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12.5, weight: .semibold))
                    Text(subtitle).font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText)
                }
                .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isHovered)
    }
}

struct AddToPlaylistSheet: View {
    let song: SongItem

    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add to playlist").font(.system(size: 17, weight: .bold))
            Text(song.title).font(.system(size: 12)).foregroundStyle(Theme.secondaryText).lineLimit(1)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(library.playlists()) { playlist in
                        Button {
                            library.add(song, to: playlist)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "music.note.list").foregroundStyle(Theme.secondaryText)
                                Text(playlist.name)
                                Spacer()
                                if playlist.songIds.contains(song.id) { Image(systemName: "checkmark").foregroundStyle(Theme.secondaryText) }
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 34)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 240)
            HStack {
                TextField("New playlist name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(createAndAdd)
                Button("Create", action: createAndAdd).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func createAndAdd() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        library.add(song, to: library.createPlaylist(named: name))
        dismiss()
    }
}

struct NewPlaylistSheet: View {
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New playlist").font(.system(size: 17, weight: .bold))
            TextField("Give it a name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let playlist = library.createPlaylist(named: trimmed)
        dismiss()
        router.push(.localPlaylist(playlist.id))
    }
}
