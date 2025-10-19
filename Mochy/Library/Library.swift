import Foundation
import SwiftData

// a month of listening, for the home hero and the recap page
struct MonthRecap {
    let month: Date
    let plays: Int
    let minutes: Int
    let topSongs: [(song: SongItem, plays: Int)]
    let topArtists: [(name: String, id: String?, plays: Int)]

    var isEmpty: Bool { plays == 0 }
}

// the few things the rest of the app asks of the library, so views don't each hand-roll fetches
@Observable
final class Library {
    let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    // likes and plays bump these, so hearts and the recap redraw without each one running a fetch
    private(set) var likedIds: Set<String> = []
    private(set) var historyVersion = 0
    private(set) var playlistsVersion = 0

    init() {
        let schema = Schema([LibrarySong.self, LocalPlaylist.self, PlayEvent.self])
        do {
            // its own folder, an app outside the sandbox would otherwise share swiftdata's default.store with every other one
            let folder = URL.applicationSupportDirectory.appending(path: Library.folderName, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: folder.appending(path: "Library.store")))
        } catch {
            // a library that can't open would crash every launch, an in-memory one at least lets people listen
            container = try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        let liked = (try? context.fetch(FetchDescriptor<LibrarySong>(predicate: #Predicate { $0.likedAt != nil }))) ?? []
        likedIds = Set(liked.map(\.id))
    }

    #if DEBUG
    // the debug tour keeps its plays out of your real library
    private static var folderName: String { ProcessInfo.processInfo.environment["MOCHY_TOUR_DIR"] == nil ? "Mochy" : "Mochy-tour" }
    #else
    private static let folderName = "Mochy"
    #endif

    func isLiked(_ id: String) -> Bool { likedIds.contains(id) }

    func toggleLike(_ song: SongItem) {
        let stored = upsert(song)
        stored.likedAt = stored.likedAt == nil ? .now : nil
        if stored.likedAt == nil { likedIds.remove(song.id) } else { likedIds.insert(song.id) }
        try? context.save()
    }

    func recordPlay(_ song: SongItem) {
        let stored = upsert(song)
        stored.lastPlayedAt = .now
        stored.playCount += 1
        context.insert(PlayEvent(songId: song.id))
        try? context.save()
        historyVersion += 1
    }

    func add(_ song: SongItem, to playlist: LocalPlaylist) {
        upsert(song)
        guard !playlist.songIds.contains(song.id) else { return }
        playlist.songIds.append(song.id)
        try? context.save()
        playlistsVersion += 1
    }

    func remove(_ songId: String, from playlist: LocalPlaylist) {
        playlist.songIds.removeAll { $0 == songId }
        try? context.save()
        playlistsVersion += 1
    }

    @discardableResult
    func createPlaylist(named name: String) -> LocalPlaylist {
        let playlist = LocalPlaylist(name: name)
        context.insert(playlist)
        try? context.save()
        playlistsVersion += 1
        return playlist
    }

    func rename(_ playlist: LocalPlaylist, to name: String) {
        playlist.name = name
        try? context.save()
        playlistsVersion += 1
    }

    func togglePin(_ playlist: LocalPlaylist) {
        playlist.isPinned.toggle()
        try? context.save()
        playlistsVersion += 1
    }

    func delete(_ playlist: LocalPlaylist) {
        context.delete(playlist)
        try? context.save()
        playlistsVersion += 1
    }

    func clearHistory() {
        try? context.delete(model: PlayEvent.self)
        let played = (try? context.fetch(FetchDescriptor<LibrarySong>(predicate: #Predicate { $0.lastPlayedAt != nil }))) ?? []
        for song in played {
            song.lastPlayedAt = nil
            song.playCount = 0
        }
        try? context.save()
        historyVersion += 1
    }

    func songs(ids: [String]) -> [SongItem] {
        let stored = (try? context.fetch(FetchDescriptor<LibrarySong>(predicate: #Predicate { ids.contains($0.id) }))) ?? []
        let byId = Dictionary(stored.map { ($0.id, $0.item) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byId[$0] }
    }

    func playlists() -> [LocalPlaylist] {
        (try? context.fetch(FetchDescriptor<LocalPlaylist>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    func playlist(id: String) -> LocalPlaylist? {
        try? context.fetch(FetchDescriptor<LocalPlaylist>(predicate: #Predicate { $0.id == id })).first
    }

    func likedSongs() -> [SongItem] {
        var descriptor = FetchDescriptor<LibrarySong>(predicate: #Predicate { $0.likedAt != nil }, sortBy: [SortDescriptor(\.likedAt, order: .reverse)])
        descriptor.fetchLimit = 2000
        return ((try? context.fetch(descriptor)) ?? []).map(\.item)
    }

    func recentSongs(limit: Int = 30) -> [SongItem] {
        var descriptor = FetchDescriptor<LibrarySong>(predicate: #Predicate { $0.lastPlayedAt != nil }, sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return ((try? context.fetch(descriptor)) ?? []).map(\.item)
    }

    // the month so far: plays, minutes, and what got played the most
    func recap(for month: Date = .now) -> MonthRecap {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .month, for: month)?.start ?? month
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? .distantFuture
        let events = (try? context.fetch(FetchDescriptor<PlayEvent>(predicate: #Predicate { $0.playedAt >= start && $0.playedAt < end }))) ?? []
        var counts: [String: Int] = [:]
        for event in events { counts[event.songId, default: 0] += 1 }
        let songs = songs(ids: Array(counts.keys))
        let byId = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let topSongs = counts.sorted { $0.value > $1.value }.compactMap { id, plays in byId[id].map { (song: $0, plays: plays) } }
        var artistPlays: [String: (id: String?, plays: Int)] = [:]
        var seconds = 0
        for (id, plays) in counts {
            guard let song = byId[id] else { continue }
            seconds += (song.duration ?? 200) * plays
            for artist in song.artists.prefix(2) {
                let existing = artistPlays[artist.name]
                artistPlays[artist.name] = (existing?.id ?? artist.id, (existing?.plays ?? 0) + plays)
            }
        }
        let topArtists = artistPlays.sorted { $0.value.plays > $1.value.plays }.map { (name: $0.key, id: $0.value.id, plays: $0.value.plays) }
        return MonthRecap(month: start, plays: events.count, minutes: seconds / 60, topSongs: Array(topSongs.prefix(20)), topArtists: Array(topArtists.prefix(10)))
    }

    @discardableResult
    private func upsert(_ song: SongItem) -> LibrarySong {
        let id = song.id
        if let existing = try? context.fetch(FetchDescriptor<LibrarySong>(predicate: #Predicate { $0.id == id })).first {
            existing.refresh(from: song)
            return existing
        }
        let created = LibrarySong(song)
        context.insert(created)
        return created
    }
}
