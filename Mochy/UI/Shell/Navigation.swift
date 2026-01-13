import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case home, search, library
}

enum Route: Hashable {
    case album(String)
    case artist(String)
    case playlist(String)
    case localPlaylist(String)
    case liked
    case history
    case section(FeedSection)
    case recap
}

// one stack per tab, so "go to artist" from a menu or the player lands in whichever tab is open
@Observable
final class Router {
    private(set) var tab: AppTab = .home
    private var paths: [AppTab: [Route]] = [:]
    var lyricsOpen = UserDefaults.standard.bool(forKey: "lyricsPanelOpen") {
        didSet { UserDefaults.standard.set(lyricsOpen, forKey: "lyricsPanelOpen") }
    }
    var playerOpen = false
    var queueOpen = false
    var addToPlaylist: SongItem?
    var newPlaylistPrompt = false
    // bumps when cmd-f asks the search field for focus
    private(set) var searchFocusRequest = 0

    var path: [Route] { paths[tab] ?? [] }
    var top: Route? { path.last }

    func select(_ newTab: AppTab) {
        if tab == newTab {
            // a second click on the tab goes back to its start, like every other app
            paths[newTab] = []
        }
        tab = newTab
    }

    func push(_ route: Route) {
        playerOpen = false
        if paths[tab]?.last == route { return }
        paths[tab, default: []].append(route)
    }

    func pop() {
        guard !(paths[tab] ?? []).isEmpty else { return }
        paths[tab]?.removeLast()
    }

    func focusSearch() {
        playerOpen = false
        tab = .search
        paths[.search] = []
        searchFocusRequest += 1
    }

    func open(_ item: YTItem) {
        switch item {
        case .album(let album): push(.album(album.browseId))
        case .artist(let artist): push(.artist(artist.id))
        case .playlist(let playlist): push(.playlist(playlist.id))
        case .song: break
        }
    }

    func togglePlayer() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { playerOpen.toggle() }
    }

    func toggleLyrics() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) { lyricsOpen.toggle() }
    }
}

enum Theme {
    static let background = Color.black
    static let sidebar = Color(white: 0.03)
    static let surface = Color(white: 0.12)
    static let panel = Color(white: 0.085)
    static let placeholder = Color(white: 0.15)
    static let hover = Color.white.opacity(0.07)
    static let selected = Color.white.opacity(0.13)
    static let secondaryText = Color.white.opacity(0.58)
    static let tertiaryText = Color.white.opacity(0.36)
    static let hairline = Color.white.opacity(0.08)
    static let gutter: CGFloat = 28
    static let sidebarWidth: CGFloat = 70
    // room at the bottom of every page so the floating player never covers the last row
    static let bottomBarRoom: CGFloat = 96
}

extension TimeInterval {
    // 3:07, or 1:02:03 for long ones
    var clock: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(self)
        let hours = total / 3600, minutes = total / 60 % 60, seconds = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%d:%02d", minutes, seconds)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension Error {
    var friendlyMessage: String {
        (self as? LocalizedError)?.errorDescription ?? String(localized: "Check your connection and try again.")
    }
}
