import AVFoundation
import Foundation
import Observation
import SwiftUI

enum RepeatMode: String, CaseIterable {
    case off, all, one
}

enum LyricsState: Equatable {
    case idle, loading, found, missing
}

// the one player the whole app shares: the queue, the avplayer under it and everything the screens show about it
@Observable
final class PlayerModel {
    private(set) var queue: [SongItem] = []
    private(set) var index = 0
    private(set) var isPlaying = false
    private(set) var isBuffering = false
    private(set) var duration: TimeInterval = 0
    private(set) var stream: StreamInfo?
    private(set) var errorMessage: String?
    private(set) var queueTitle: String?
    private(set) var lyrics: Lyrics?
    private(set) var lyricsState: LyricsState = .idle
    private(set) var lyricsCandidates: [LyricsCandidate] = []
    private(set) var isLoadingAllLyrics = false
    private(set) var palette = CoverPalette.fallback
    private(set) var isShuffled = false
    var repeatMode: RepeatMode = .off
    var volume: Double = UserDefaults.standard.object(forKey: "playerVolume") as? Double ?? 1 {
        didSet {
            UserDefaults.standard.set(volume, forKey: "playerVolume")
            applyVolume()
        }
    }

    var current: SongItem? { queue.indices.contains(index) ? queue[index] : nil }
    var next: SongItem? { queue.indices.contains(index + 1) ? queue[index + 1] : nil }
    var upNext: ArraySlice<SongItem> { queue.indices.contains(index + 1) ? queue[(index + 1)...] : [] }

    // read straight from avplayer, the views that need it read it per frame so nothing else redraws
    var currentTime: TimeInterval {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : 0
    }

    @ObservationIgnored let player = AVPlayer()
    @ObservationIgnored var library: Library?
    @ObservationIgnored private let nowPlaying = NowPlayingCenter()
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var moreTask: Task<Void, Never>?
    @ObservationIgnored private var lyricsTask: Task<Void, Never>?
    @ObservationIgnored private var paletteTask: Task<Void, Never>?
    @ObservationIgnored private var streamCache: [String: StreamInfo] = [:]
    @ObservationIgnored private var retriedIds: Set<String> = []
    @ObservationIgnored private var queueContinuation: String?
    @ObservationIgnored private var lyricsBrowseId: String?
    @ObservationIgnored private var unshuffledQueue: [SongItem]?
    @ObservationIgnored private var loudnessGain: Float = 1
    @ObservationIgnored private var restoredPosition: TimeInterval?
    @ObservationIgnored private var shownSongId: String?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var itemObservation: NSKeyValueObservation?

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        observePlayer()
        nowPlaying.attach(to: self)
        restoreSession()
    }

    // MARK: starting playback

    // one song now, then youtube's radio for it fills the queue behind it
    func play(_ song: SongItem) {
        if current?.id == song.id { return togglePlayPause() }
        startQueue([song], at: 0, title: nil)
        fetchQueue(.radio(for: song.id), keepingFirst: song)
    }

    func play(_ songs: [SongItem], startAt start: Int = 0, title: String? = nil) {
        guard songs.indices.contains(start) else { return }
        startQueue(songs, at: start, title: title)
    }

    func play(endpoint: WatchEndpoint, title: String? = nil) {
        loadTask?.cancel()
        isBuffering = true
        Task {
            do {
                let result = try await InnerTube.shared.next(endpoint)
                guard !result.items.isEmpty else { return }
                startQueue(result.items, at: result.currentIndex ?? 0, title: title)
                queueContinuation = result.continuation
                lyricsBrowseId = result.lyricsBrowseId
            } catch {
                isBuffering = false
                show(error: String(localized: "Couldn't start this. Check your connection and try again."))
            }
        }
    }

    func startRadio(for song: SongItem) {
        startQueue([song], at: 0, title: String(localized: "\(song.title) radio"))
        fetchQueue(.radio(for: song.id), keepingFirst: song)
    }

    func playNext(_ song: SongItem) {
        guard current != nil else { return play(song) }
        queue.removeAll { $0.id == song.id && $0.id != current?.id }
        queue.insert(song, at: min(index + 1, queue.count))
        saveSession()
    }

    func addToQueue(_ song: SongItem) {
        guard current != nil else { return play(song) }
        queue.removeAll { $0.id == song.id && $0.id != current?.id }
        queue.append(song)
        saveSession()
    }

    // MARK: controls

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func resume() {
        guard current != nil else { return }
        isPlaying = true
        if player.currentItem == nil { load(index, resumeAt: restoredPosition) } else { player.play() }
        restoredPosition = nil
        nowPlaying.update()
    }

    func pause() {
        isPlaying = false
        player.pause()
        nowPlaying.update()
        saveSession()
    }

    func skipNext() {
        if queue.indices.contains(index + 1) {
            load(index + 1)
        } else if repeatMode == .all, !queue.isEmpty {
            load(0)
        }
    }

    // like every player: a few seconds in, back goes to the start of the song, not the one before
    func skipPrevious() {
        if currentTime > 3 || index == 0 {
            seek(to: 0)
        } else {
            load(index - 1)
        }
    }

    func seek(to time: TimeInterval) {
        if player.currentItem == nil {
            restoredPosition = time
            return
        }
        player.seek(to: CMTime(seconds: max(0, time), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in self?.nowPlaying.update() }
        }
    }

    func seek(by delta: TimeInterval) {
        seek(to: min(max(0, currentTime + delta), max(duration - 1, 0)))
    }

    func jump(to newIndex: Int) {
        guard queue.indices.contains(newIndex) else { return }
        load(newIndex)
    }

    func removeFromQueue(at offsets: IndexSet) {
        guard !offsets.contains(index) else { return }
        let shift = offsets.filter { $0 < index }.count
        queue.remove(atOffsets: offsets)
        index -= shift
        saveSession()
    }

    func moveInQueue(from source: IndexSet, to destination: Int) {
        guard let playing = current else { return }
        queue.move(fromOffsets: source, toOffset: destination)
        index = queue.firstIndex(of: playing) ?? index
        saveSession()
    }

    func cycleRepeat() {
        let all = RepeatMode.allCases
        repeatMode = all[(all.firstIndex(of: repeatMode)! + 1) % all.count]
    }

    // shuffles what's left to play, and turning it off puts the songs back in their old order
    func toggleShuffle() {
        guard let playing = current else { return }
        if isShuffled, let original = unshuffledQueue {
            let known = Set(original.map(\.id))
            queue = original + queue.filter { !known.contains($0.id) }
            index = queue.firstIndex(of: playing) ?? 0
            unshuffledQueue = nil
            isShuffled = false
        } else {
            unshuffledQueue = queue
            var rest = queue
            rest.remove(at: index)
            queue = [playing] + rest.shuffled()
            index = 0
            isShuffled = true
        }
        saveSession()
    }

    func dismissError() { errorMessage = nil }

    // MARK: lyrics

    // the source picker wants every source's answer, not just the quick pick
    func loadAllLyrics() {
        guard let song = current, !isLoadingAllLyrics else { return }
        isLoadingAllLyrics = true
        let query = LyricsQuery(song: song, duration: duration > 0 ? Int(duration) : nil, lyricsBrowseId: lyricsBrowseId)
        Task {
            let all = await LyricsService.shared.allCandidates(for: query)
            guard current?.id == song.id else { return }
            lyricsCandidates = all
            isLoadingAllLyrics = false
        }
    }

    func choose(_ candidate: LyricsCandidate) {
        guard let song = current else { return }
        lyrics = candidate.lyrics
        lyricsState = .found
        Task { await LyricsService.shared.choose(candidate.lyrics, for: song.id) }
    }

    func refetchLyrics() {
        guard let song = current else { return }
        Task {
            await LyricsService.shared.forget(song.id)
            loadLyrics(for: song)
        }
    }

    // MARK: loading

    private func startQueue(_ songs: [SongItem], at start: Int, title: String?) {
        queue = songs
        queueTitle = title
        queueContinuation = nil
        lyricsBrowseId = nil
        unshuffledQueue = nil
        isShuffled = false
        isPlaying = true
        load(start)
    }

    private func load(_ newIndex: Int, resumeAt: TimeInterval? = nil) {
        loadTask?.cancel()
        index = newIndex
        guard let song = current else { return }
        // a retry or a resumed session keeps the lyrics and colours it already has
        let songChanged = shownSongId != song.id
        shownSongId = song.id

        player.replaceCurrentItem(with: nil)
        errorMessage = nil
        isBuffering = true
        duration = TimeInterval(song.duration ?? 0)
        stream = nil
        if songChanged {
            lyrics = nil
            lyricsState = .loading
            lyricsCandidates = []
            loadPalette(for: song)
        }
        nowPlaying.update()
        saveSession()

        loadTask = Task {
            do {
                let info = try await streamInfo(for: song.id)
                try Task.checkCancellation()
                stream = info
                if let length = info.approxDuration, length > 0 { duration = length }
                player.replaceCurrentItem(with: playerItem(for: info))
                applyLoudness(info)
                if let resumeAt, resumeAt > 1 { seek(to: resumeAt) }
                if isPlaying { player.play() }
                library?.recordPlay(song)
                nowPlaying.update()
                if songChanged || lyricsState != .found { loadLyrics(for: song) }
                prefetchNext()
                fetchMoreIfNeeded()
            } catch is CancellationError {
                return
            } catch {
                isBuffering = false
                show(error: error.localizedDescription)
            }
        }
    }

    private func streamInfo(for id: String) async throws -> StreamInfo {
        if let cached = streamCache[id], cached.expiresAt > .now { return cached }
        let info = try await InnerTube.shared.stream(for: id, preferHighQuality: AppSettings.highQualityAudio)
        streamCache[id] = info
        return info
    }

    private func playerItem(for info: StreamInfo) -> AVPlayerItem {
        let asset = AVURLAsset(url: info.url, options: [
            AVURLAssetHTTPUserAgentKey: info.headers["User-Agent"] ?? "",
            "AVURLAssetHTTPHeaderFieldsKey": info.headers,
        ])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 30
        return item
    }

    // youtube says how loud each song is mastered, turning loud ones down keeps a mix from jumping in volume
    private func applyLoudness(_ info: StreamInfo) {
        if AppSettings.normalizeVolume, let loudness = info.loudnessDb, loudness > 0 {
            loudnessGain = Float(pow(10, -loudness / 20))
        } else {
            loudnessGain = 1
        }
        applyVolume()
    }

    private func applyVolume() {
        player.volume = Float(volume) * loudnessGain
    }

    private func prefetchNext() {
        guard let next = upNext.first, streamCache[next.id] == nil else { return }
        Task { _ = try? await streamInfo(for: next.id) }
    }

    // radio queues are endless, ask for the next page while there are still a few songs to go
    private func fetchMoreIfNeeded() {
        guard moreTask == nil, let token = queueContinuation, queue.count - index < 5 else { return }
        moreTask = Task {
            defer { moreTask = nil }
            guard let result = try? await InnerTube.shared.next(WatchEndpoint(), continuation: token) else { return }
            let known = Set(queue.map(\.id))
            queue.append(contentsOf: result.items.filter { !known.contains($0.id) })
            queueContinuation = result.continuation
        }
    }

    private func fetchQueue(_ endpoint: WatchEndpoint, keepingFirst first: SongItem) {
        Task {
            guard let result = try? await InnerTube.shared.next(endpoint), current?.id == first.id else { return }
            let rest = result.items.filter { $0.id != first.id }
            queue = [first] + rest
            index = 0
            queueContinuation = result.continuation
            lyricsBrowseId = result.lyricsBrowseId
            prefetchNext()
            saveSession()
        }
    }

    private func loadLyrics(for song: SongItem) {
        lyricsTask?.cancel()
        lyricsState = .loading
        let query = LyricsQuery(song: song, duration: duration > 0 ? Int(duration) : nil, lyricsBrowseId: lyricsBrowseId)
        lyricsTask = Task {
            let outcome = await LyricsService.shared.lyrics(for: query)
            guard !Task.isCancelled, current?.id == song.id else { return }
            lyrics = outcome.best
            lyricsCandidates = outcome.candidates
            lyricsState = outcome.best == nil ? .missing : .found
        }
    }

    private func loadPalette(for song: SongItem) {
        paletteTask?.cancel()
        let url = song.thumbnail.resizedThumbnail(120)
        paletteTask = Task {
            guard let image = await ImageLoader.shared.image(url, pixels: 120) else { return }
            let colors = await CoverPalette.extract(from: image)
            guard !Task.isCancelled, current?.id == song.id else { return }
            withAnimation(.easeInOut(duration: 0.9)) { palette = colors }
        }
    }

    private func show(error message: String) {
        errorMessage = message
        Task {
            try? await Task.sleep(for: .seconds(5))
            if errorMessage == message { errorMessage = nil }
        }
    }

    // MARK: remembering the session

    private struct Session: Codable {
        let queue: [SongItem]
        let index: Int
        let position: TimeInterval
        let title: String?
    }

    // the queue and spot are kept so the next launch picks up where this one left off, paused
    func saveSession() {
        guard !queue.isEmpty else { return }
        let session = Session(queue: Array(queue.prefix(200)), index: min(index, 199), position: currentTime, title: queueTitle)
        if let data = try? JSONEncoder().encode(session) { UserDefaults.standard.set(data, forKey: "playerSession") }
    }

    private func restoreSession() {
        guard let data = UserDefaults.standard.data(forKey: "playerSession"),
              let session = try? JSONDecoder().decode(Session.self, from: data),
              session.queue.indices.contains(session.index)
        else { return }
        queue = session.queue
        index = session.index
        queueTitle = session.title
        restoredPosition = session.position
        duration = TimeInterval(session.queue[session.index].duration ?? 0)
        if let song = current {
            shownSongId = song.id
            loadPalette(for: song)
            loadLyrics(for: song)
        }
    }

    // MARK: avplayer events

    private func observePlayer() {
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.syncStatus() }
        }
        itemObservation = player.observe(\.currentItem?.status, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.syncItemStatus() }
        }
        NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] note in
            let item = note.object as? AVPlayerItem
            MainActor.assumeIsolated {
                guard let self, item === self.player.currentItem else { return }
                self.songFinished()
            }
        }
    }

    private func syncStatus() {
        switch player.timeControlStatus {
        case .playing: isBuffering = false
        case .waitingToPlayAtSpecifiedRate: isBuffering = true
        // with no item yet we're still fetching the link, so the spinner load() started stays up
        case .paused: if player.currentItem != nil { isBuffering = false }
        @unknown default: break
        }
        nowPlaying.update()
    }

    private func syncItemStatus() {
        guard let item = player.currentItem else { return }
        switch item.status {
        case .readyToPlay:
            // only trusted when nothing better is known, some streams report double their real length
            let seconds = item.duration.seconds
            if seconds.isFinite, seconds > 0, stream?.approxDuration == nil, current?.duration == nil { duration = seconds }
            isBuffering = player.timeControlStatus != .playing && isPlaying
            nowPlaying.update()
        case .failed:
            // links run out after a few hours, so one fresh try before telling anyone
            guard let song = current else { return }
            streamCache[song.id] = nil
            if retriedIds.insert(song.id).inserted {
                load(index, resumeAt: currentTime)
            } else {
                isBuffering = false
                show(error: String(localized: "Couldn't play this song. Check your connection and try again."))
            }
        default:
            break
        }
    }

    private func songFinished() {
        switch repeatMode {
        case .one:
            seek(to: 0)
            player.play()
        case .all where !queue.indices.contains(index + 1):
            load(0)
        default:
            if queue.indices.contains(index + 1) {
                load(index + 1)
            } else {
                pause()
                seek(to: 0)
            }
        }
    }
}

// the switches people can flip in settings, read by code that isn't a view and so can't use appstorage
enum AppSettings {
    static let highQualityAudioKey = "highQualityAudio"
    static let normalizeVolumeKey = "normalizeVolume"
    static let hideExplicitKey = "hideExplicit"
    static let lyricsBlurKey = "lyricsBlur"
    static let lyricsGlowKey = "lyricsGlow"
    static let animatedBackgroundsKey = "animatedBackgrounds"
    static let lyricsSizeKey = "lyricsSize"

    static var highQualityAudio: Bool { UserDefaults.standard.object(forKey: highQualityAudioKey) as? Bool ?? true }
    static var normalizeVolume: Bool { UserDefaults.standard.object(forKey: normalizeVolumeKey) as? Bool ?? true }
    static var hideExplicit: Bool { UserDefaults.standard.bool(forKey: hideExplicitKey) }
}
