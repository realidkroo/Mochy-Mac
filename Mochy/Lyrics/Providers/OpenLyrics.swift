import Foundation

// lyricsplus, racing the two mirrors still alive and taking whichever answers first
nonisolated enum YouLyPlus {
    private static let servers = ["https://lyricsplus.prjktla.my.id", "https://lyricsplus.binimum.org"]

    static func lyrics(_ query: LyricsQuery) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            for server in servers {
                group.addTask { await fetch(server, query) }
            }
            for await result in group {
                if let result, !result.isEmpty {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }
    }

    private static func fetch(_ server: String, _ query: LyricsQuery) async -> String? {
        guard let json = try? await LyricsHTTP.json(server + "/v2/lyrics/get", query: [
            "title": LyricsMatch.cleanTitle(query.title),
            "artist": query.artist,
            "duration": String(query.duration),
            "album": query.album,
            "id": query.videoId,
        ], timeout: 8) else { return nil }
        if let synced = json["syncedLyrics"].string, !synced.isEmpty { return synced }
        if let converted = convert(json["lyrics"].array), !converted.isEmpty { return converted }
        if let plain = json["plainLyrics"].string, !plain.isEmpty { return plain }
        return nil
    }

    // syllables become enhanced lrc, "<mm:ss.xxx>" before each piece, with the voice or {bg} marker after the line stamp
    private static func convert(_ items: [JSON]) -> String? {
        guard !items.isEmpty else { return nil }
        return items.map { item -> String in
            let lineStamp = format(item["time"].int ?? 0, syllable: false)
            let syllables = item["syllabus"].array
            let isBackground = syllables.contains { $0["isBackground"].bool == true }
            let singer = item["element"]["singer"].string ?? ""
            let marker = isBackground ? "{bg}" : (singer.isEmpty ? "" : "{agent:\(singer)}")
            guard !syllables.isEmpty else { return lineStamp + marker + (item["text"].string ?? "") }
            let texts = syllables.map { $0["text"].string ?? "" }
            // the api carries word boundaries in the text itself, spaces are only added when a line has none
            let spacedByApi = texts.dropLast().contains { $0.last?.isWhitespace == true }
            var line = lineStamp + marker
            for (index, syllable) in syllables.enumerated() {
                line += format(syllable["time"].int ?? 0, syllable: true) + texts[index]
                if !spacedByApi, index < syllables.count - 1, texts[index].last?.isWhitespace != true { line += " " }
            }
            return line.trimmingCharacters(in: .whitespaces)
        }.joined(separator: "\n")
    }

    private static func format(_ ms: Int, syllable: Bool) -> String {
        let body = String(format: "%02d:%02d.%03d", ms / 1000 / 60, ms / 1000 % 60, ms % 1000)
        return syllable ? "<\(body)>" : "[\(body)]"
    }
}

// simpmusic keeps lyrics per youtube video, so there's no guessing which song it is
nonisolated enum SimpMusicLyrics {
    private static let servers = ["https://api-lyrics.simpmusic.org/v1/", "https://musicfy-yt-music-server.onrender.com/v1/"]

    static func lyrics(_ query: LyricsQuery) async -> String? {
        for server in servers {
            guard let json = try? await LyricsHTTP.json(server + query.videoId, headers: ["User-Agent": "SimpMusicLyrics/1.0"], timeout: 10) else { continue }
            guard json["type"].string == "success" else { return nil }
            var tracks = json["data"].array
            if query.duration > 0 {
                tracks = tracks.filter { abs(($0["durationSeconds"].int ?? 0) - query.duration) <= 10 }
                    .sorted { abs(($0["durationSeconds"].int ?? 0) - query.duration) < abs(($1["durationSeconds"].int ?? 0) - query.duration) }
            }
            guard let best = tracks.first else { return nil }
            for key in ["richSyncLyrics", "syncedLyrics", "plainLyric"] {
                if let text = best[key].string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
            }
            return nil
        }
        return nil
    }
}

// lrclib, free community lyrics, searched a few ways from strict to loose
nonisolated enum LrcLib {
    private struct Track: Sendable {
        let trackName: String
        let artistName: String
        let duration: Double
        let synced: String?
        let plain: String?
    }

    static func lyrics(_ query: LyricsQuery) async -> String? {
        let tracks = await search(title: query.title, artist: query.artist, album: query.album)
        guard !tracks.isEmpty else { return nil }
        let pick: Track?
        if query.duration <= 0 {
            let title = LyricsMatch.cleanTitle(query.title)
            let artist = LyricsMatch.cleanArtist(query.artist)
            pick = tracks.max { score($0, title, artist) < score($1, title, artist) }
                .flatMap { score($0, title, artist) > 0.6 ? $0 : nil }
        } else {
            let close = { (track: Track) in abs(Int(track.duration) - query.duration) <= 5 }
            pick = tracks.filter { $0.synced != nil && close($0) }.min { abs($0.duration - Double(query.duration)) < abs($1.duration - Double(query.duration)) }
                ?? tracks.filter(close).min { abs($0.duration - Double(query.duration)) < abs($1.duration - Double(query.duration)) }
        }
        return pick?.synced ?? pick?.plain
    }

    private static func score(_ track: Track, _ title: String, _ artist: String) -> Double {
        (LyricsMatch.similarity(title, track.trackName) + LyricsMatch.similarity(artist, track.artistName)) / 2 + (track.synced != nil ? 0.1 : 0)
    }

    private static func search(title: String, artist: String, album: String?) async -> [Track] {
        let cleanTitle = LyricsMatch.cleanTitle(title)
        let cleanArtist = LyricsMatch.cleanArtist(artist)
        var attempts: [[String: String?]] = [
            ["track_name": cleanTitle, "artist_name": cleanArtist, "album_name": album],
            ["track_name": cleanTitle],
            ["q": "\(cleanArtist) \(cleanTitle)"],
            ["q": cleanTitle],
        ]
        if cleanTitle != title.trimmingCharacters(in: .whitespaces) {
            attempts.append(["track_name": title, "artist_name": artist])
        }
        for parameters in attempts {
            guard let json = try? await LyricsHTTP.json("https://lrclib.net/api/search", query: parameters) else { continue }
            let tracks = json.array.compactMap { item -> Track? in
                let synced = item["syncedLyrics"].string?.nilIfBlank
                let plain = item["plainLyrics"].string?.nilIfBlank
                guard synced != nil || plain != nil else { return nil }
                return Track(trackName: item["trackName"].string ?? "", artistName: item["artistName"].string ?? "", duration: item["duration"].double ?? 0, synced: synced, plain: plain)
            }
            if !tracks.isEmpty { return tracks }
        }
        return []
    }
}

nonisolated extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}
