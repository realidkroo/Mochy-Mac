import SwiftUI

// the narrow column on the left: the logo, the three tabs, pinned places as circles, and the profile at the bottom
struct Sidebar: View {
    @Environment(Router.self) private var router
    @Environment(Library.self) private var library

    @State private var pins: [Pin] = []

    struct Pin: Identifiable, Hashable {
        let id: String
        let title: String
        let thumbnail: String?
        let route: Route
        var isLiked = false
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: TrafficLights.clearance + 4)
            Button { router.select(.home) } label: {
                IconShape(icon: .mochy)
                    .fill(.white)
                    .frame(width: 20, height: 20)
                    .frame(width: 36, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .help("Home")
            .padding(.bottom, 10)

            VStack(spacing: 4) {
                TabButton(tab: .home, icon: .home, filled: .homeFilled, title: "Home")
                TabButton(tab: .search, icon: .search, filled: .search, title: "Search")
                TabButton(tab: .library, icon: .library, filled: .libraryFilled, title: "Library")
            }

            Capsule().fill(Theme.hairline).frame(width: 22, height: 1.5).padding(.vertical, 11)

            ScrollView(.vertical) {
                VStack(spacing: 10) {
                    ForEach(pins) { pin in PinButton(pin: pin) }
                    Button { router.newPlaylistPrompt = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 30, height: 30)
                            .background(Circle().strokeBorder(Theme.hairline, lineWidth: 1.5))
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressableStyle(scale: 0.9))
                    .help("New playlist")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never)

            ProfileButton()
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
        .frame(width: Theme.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(Theme.sidebar)
        .task(id: library.historyVersion &+ library.playlistsVersion &* 31) { pins = buildPins() }
    }

    // liked songs first, then your playlists, then albums you've been playing
    private func buildPins() -> [Pin] {
        var result = [Pin(id: "liked", title: String(localized: "Liked songs"), thumbnail: nil, route: .liked, isLiked: true)]
        for playlist in library.playlists() where playlist.isPinned {
            let cover = library.songs(ids: Array(playlist.songIds.prefix(1))).first?.thumbnail
            result.append(Pin(id: "playlist-\(playlist.id)", title: playlist.name, thumbnail: cover, route: .localPlaylist(playlist.id)))
        }
        var seenAlbums = Set<String>()
        for song in library.recentSongs(limit: 60) {
            guard let album = song.album, seenAlbums.insert(album.id).inserted else { continue }
            result.append(Pin(id: "album-\(album.id)", title: album.name, thumbnail: song.thumbnail, route: .album(album.id)))
            if seenAlbums.count == 6 { break }
        }
        return result
    }
}

private struct TabButton: View {
    let tab: AppTab
    let icon: VectorIcon
    let filled: VectorIcon
    let title: LocalizedStringKey

    @Environment(Router.self) private var router
    @State private var isHovered = false

    var body: some View {
        let selected = router.tab == tab && !router.playerOpen
        Button { router.select(tab) } label: {
            IconShape(icon: selected ? filled : icon)
                .fill(selected ? Color.white : Color.white.opacity(isHovered ? 0.9 : 0.62))
                .frame(width: 15, height: 15)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(selected ? Theme.selected : (isHovered ? Theme.hover : .clear)))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .onHover { isHovered = $0 }
        .help(title)
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

private struct PinButton: View {
    let pin: Sidebar.Pin

    @Environment(Router.self) private var router
    @State private var isHovered = false

    var body: some View {
        Button { router.push(pin.route) } label: {
            Group {
                if pin.isLiked {
                    Circle()
                        .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.36, blue: 0.5), Color(red: 0.55, green: 0.3, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(Image(systemName: "heart.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.white))
                } else if let thumbnail = pin.thumbnail {
                    RemoteImage(url: thumbnail, size: 40)
                        .clipShape(Circle())
                } else {
                    Circle().fill(Theme.surface)
                        .overlay(Image(systemName: "music.note.list").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondaryText))
                }
            }
            .frame(width: 30, height: 30)
            .overlay(Circle().strokeBorder(Color.white.opacity(isHovered ? 0.5 : 0), lineWidth: 1.5))
            .scaleEffect(isHovered ? 1.06 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        .help(pin.title)
    }
}

// the circle at the bottom left: your recap, settings and the rest of the app's housekeeping
struct ProfileButton: View {
    @Environment(Router.self) private var router
    @Environment(Library.self) private var library
    @Environment(\.openSettings) private var openSettings
    @AppStorage("profileName") private var name = ""
    @State private var showsMenu = false
    @State private var confirmClear = false

    var body: some View {
        Button { showsMenu.toggle() } label: {
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.55)], startPoint: .top, endPoint: .bottom))
                .overlay(
                    Text(initials)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.75))
                )
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .help("Profile")
        .popover(isPresented: $showsMenu, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Circle().fill(Color(white: 0.75)).frame(width: 36, height: 36)
                        .overlay(Text(initials).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.black.opacity(0.75)))
                    VStack(alignment: .leading, spacing: 1) {
                        TextField("Your name", text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, weight: .semibold))
                        Text("Listening as a guest").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                    }
                }
                .padding(.bottom, 8)
                menuRow("Your month in music", "sparkles") { router.push(.recap) }
                menuRow("Listening history", "clock") { router.push(.history) }
                menuRow("Liked songs", "heart") { router.push(.liked) }
                Divider().padding(.vertical, 4)
                menuRow("Settings…", "gearshape") { openSettings() }
                menuRow("Clear listening history", "trash") { confirmClear = true }
            }
            .padding(14)
            .frame(width: 250)
        }
        .confirmationDialog("Clear your listening history?", isPresented: $confirmClear) {
            Button("Clear history", role: .destructive) { library.clearHistory() }
        } message: {
            Text("Your recap and recently played will start over. Likes and playlists stay.")
        }
    }

    private var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "M" : String(letters).uppercased()
    }

    private func menuRow(_ title: LocalizedStringKey, _ icon: String, action: @escaping () -> Void) -> some View {
        MenuRow(title: title, icon: icon) {
            showsMenu = false
            action()
        }
    }
}

private struct MenuRow: View {
    let title: LocalizedStringKey
    let icon: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 18).foregroundStyle(Theme.secondaryText)
                Text(title)
                Spacer()
            }
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(isHovered ? Theme.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
