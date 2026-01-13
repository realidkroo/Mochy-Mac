import SwiftUI

// how the window splits up at its current size, the sidebar goes first when it gets narrow
struct ShellLayout: Equatable {
    let showsSidebar: Bool
    let panelWidth: CGFloat
    let barStyle: BarStyle

    init(width: CGFloat, lyricsOpen: Bool) {
        showsSidebar = width >= 860
        panelWidth = min(max(width * 0.3, 300), 440)
        let main = width - (showsSidebar ? Theme.sidebarWidth : 0) - (lyricsOpen ? panelWidth : 0)
        if showsSidebar {
            barStyle = main >= 540 ? .classic : .compact
        } else {
            barStyle = main >= 700 ? .classicWithNav : .compactWithNav
        }
    }
}

struct ShowsSidebarKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var showsSidebar: Bool {
        get { self[ShowsSidebarKey.self] }
        set { self[ShowsSidebarKey.self] = newValue }
    }
}

struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(PlayerModel.self) private var player
    @Environment(WindowState.self) private var window

    var body: some View {
        GeometryReader { geometry in
            let layout = ShellLayout(width: geometry.size.width, lyricsOpen: router.lyricsOpen)
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    if layout.showsSidebar {
                        Sidebar()
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    MainArea(barStyle: layout.barStyle)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                    if router.lyricsOpen {
                        LyricsPanel()
                            .frame(width: layout.panelWidth)
                            .transition(.move(edge: .trailing))
                    }
                }
                .environment(\.showsSidebar, layout.showsSidebar)

                if router.playerOpen {
                    FullPlayerView()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 1.03)),
                            removal: .opacity.combined(with: .scale(scale: 1.03))
                        ))
                        .zIndex(2)
                }

                if !window.isFullScreen {
                    TrafficLightPill().zIndex(3)
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.88), value: layout.showsSidebar)
        }
        .background(Theme.background)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .sheet(item: Binding(get: { router.addToPlaylist }, set: { router.addToPlaylist = $0 })) { song in
            AddToPlaylistSheet(song: song)
        }
        .sheet(isPresented: Binding(get: { router.newPlaylistPrompt }, set: { router.newPlaylistPrompt = $0 })) {
            NewPlaylistSheet()
        }
    }
}

// the page of the open tab, with the floating player over its bottom edge
private struct MainArea: View {
    let barStyle: BarStyle

    @Environment(Router.self) private var router
    @Environment(PlayerModel.self) private var player

    var body: some View {
        ZStack(alignment: .bottom) {
            PageStack()
            VStack(spacing: 10) {
                if let message = player.errorMessage {
                    ErrorToast(message: message)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                BottomBar(style: barStyle)
            }
            .padding(.bottom, 16)
            .padding(.horizontal, 12)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: player.errorMessage)
        }
        .background(Theme.background)
    }
}

// every tab keeps its own root page alive, so coming back finds it where you left it
private struct PageStack: View {
    @Environment(Router.self) private var router
    @Environment(\.showsSidebar) private var showsSidebar

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let visible = router.tab == tab && router.path.isEmpty
                rootPage(tab)
                    .opacity(visible ? 1 : 0)
                    .allowsHitTesting(visible)
                    .environment(\.isPageVisible, visible && !router.playerOpen)
            }
            if let route = router.top {
                RoutePage(route: route)
                    .id(route)
                    .background(Theme.background)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                    .environment(\.isPageVisible, !router.playerOpen)
                BackButton()
                    .padding(.top, 14)
                    .padding(.leading, showsSidebar ? 18 : 92)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: router.path)
        .animation(.easeInOut(duration: 0.2), value: router.tab)
    }

    @ViewBuilder
    private func rootPage(_ tab: AppTab) -> some View {
        switch tab {
        case .home: HomeView()
        case .search: SearchView()
        case .library: LibraryView()
        }
    }
}

private struct RoutePage: View {
    let route: Route

    var body: some View {
        switch route {
        case .album(let id): AlbumView(browseId: id)
        case .artist(let id): ArtistView(browseId: id)
        case .playlist(let id): PlaylistView(playlistId: id)
        case .localPlaylist(let id): LocalPlaylistView(playlistId: id)
        case .liked: LikedSongsView()
        case .history: HistoryView()
        case .section(let section): SectionView(section: section)
        case .recap: RecapView()
        }
    }
}

struct PageVisibleKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    // false while a page sits hidden behind another tab or the player, so its loops can rest
    var isPageVisible: Bool {
        get { self[PageVisibleKey.self] }
        set { self[PageVisibleKey.self] = newValue }
    }
}

private struct ErrorToast: View {
    let message: String
    @Environment(PlayerModel.self) private var player

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.yellow)
            Text(message).font(.system(size: 12, weight: .medium)).lineLimit(2)
            Button { player.dismissError() } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassPill()
    }
}
