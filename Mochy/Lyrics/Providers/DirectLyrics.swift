import Foundation

// deezer with an anonymous login: word-timed when deezer has that, line-timed otherwise
nonisolated enum DeezerLyrics {
    static func lyrics(_ query: LyricsQuery) async throws -> String? {
        let search = try await LyricsHTTP.json("https://api.deezer.com/search", query: ["q": "\(LyricsMatch.cleanTitle(query.title)) \(query.firstArtist)", "limit": "10"])
        let candidates = search["data"].array.compactMap { track -> TrackCandidate<Int>? in
            guard let id = track["id"].int else { return nil }
            return TrackCandidate(
                titles: [track["title"].string ?? "", track["title_short"].string ?? ""],
                artists: [track["artist"]["name"].string ?? ""],
                durationSec: track["duration"].int ?? 0,
                ref: id
            )
        }
        guard let trackId = candidates.bestMatch(title: LyricsMatch.cleanTitle(query.title), artist: query.artist, durationSec: query.duration) else { return nil }

        let graphQL = "query { track(trackId: \"\(trackId)\") { lyrics { text synchronizedLines { milliseconds line } synchronizedWordByWordLines { start words { start end word } } } } }"
        let token = try await DeezerToken.shared.value()
        let response: JSON
        do {
            response = try JSON(data: try await LyricsHTTP.post("https://pipe.deezer.com/api", json: ["query": graphQL], headers: ["Authorization": "Bearer \(token)"]))
        } catch {
            // most likely the token went stale early, the next song logs in again
            await DeezerToken.shared.forget()
            throw error
        }
        let lyrics = response["data"]["track"]["lyrics"]
        var lines = lyrics["synchronizedWordByWordLines"].array.map { line in
            let words = line["words"].array.map { (text: $0["word"].string ?? "", startMs: $0["start"].int ?? 0, endMs: $0["end"].int ?? 0) }
            return TimedLine(startMs: line["start"].int ?? 0, text: joinWords(words.map(\.text)), words: words)
        }
        if lines.isEmpty {
            lines = lyrics["synchronizedLines"].array.map { TimedLine(startMs: $0["milliseconds"].int ?? 0, text: ($0["line"].string ?? "").trimmingCharacters(in: .whitespaces)) }
        }
        if lines.hasLyrics { return lines.toLRC() }
        return lyrics["text"].string?.replacingOccurrences(of: "\r\n", with: "\n").nilIfBlank
    }

    // deezer sends bare words, so spaces go back between them except before punctuation and inside unspaced scripts
    private static func joinWords(_ words: [String]) -> String {
        var out = ""
        for word in words.map({ $0.trimmingCharacters(in: .whitespaces) }) where !word.isEmpty {
            let attached = ",.!?;:)]}…".contains(word.first!) || (out.last.map(Script.isUnspaced) == true && Script.isUnspaced(word.first!))
            if !out.isEmpty, !attached { out += " " }
            out += word
        }
        return out
    }
}

// the anonymous token only lasts a few minutes, so it's kept until shortly before it runs out
actor DeezerToken {
    static let shared = DeezerToken()
    private var token: String?
    private var expiresAt = Date.distantPast

    func value() async throws -> String {
        if let token, Date() < expiresAt { return token }
        let json = try await LyricsHTTP.json("https://auth.deezer.com/login/anonymous", query: ["jo": "p", "rto": "c"])
        guard let jwt = json["jwt"].string else { throw LyricsHTTPError.status(401) }
        token = jwt
        expiresAt = (Self.expiry(of: jwt) ?? Date().addingTimeInterval(300)).addingTimeInterval(-30)
        return jwt
    }

    func forget() { token = nil }

    private static func expiry(of jwt: String) -> Date? {
        let parts = jwt.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload), let exp = (try? JSON(data: data))?["exp"].double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}

// netease cloud music with no account, many songs including english ones come with real word timing
nonisolated enum NetEaseLyrics {
    static func lyrics(_ query: LyricsQuery) async throws -> String? {
        let search = try await LyricsHTTP.json("https://music.163.com/api/search/get", query: ["s": "\(LyricsMatch.cleanTitle(query.title)) \(query.firstArtist)", "type": "1", "limit": "10"])
        let candidates = search["result"]["songs"].array.compactMap { song -> TrackCandidate<Int>? in
            guard let id = song["id"].int else { return nil }
            return TrackCandidate(
                titles: [song["name"].string ?? ""] + song["alias"].array.compactMap(\.string),
                artists: song["artists"].array.compactMap { $0["name"].string },
                durationSec: (song["duration"].int ?? 0) / 1000,
                ref: id
            )
        }
        guard let songId = candidates.bestMatch(title: LyricsMatch.cleanTitle(query.title), artist: query.artist, durationSec: query.duration) else { return nil }
        let response = try await LyricsHTTP.json("https://music.163.com/api/song/lyric", query: ["id": String(songId), "lv": "1", "yv": "1"])
        var lines = (response["yrc"]["lyric"].string).map(parseYRC) ?? []
        if lines.isEmpty { lines = response["lrc"]["lyric"].string.map(LRC.lines) ?? [] }
        let clean = lines.withoutCredits()
        return clean.hasLyrics ? clean.toLRC() : nil
    }

    // "[lineStart,lineLength](wordStart,wordLength,0)word" in milliseconds, the json credit lines have no stamp and drop out
    private static func parseYRC(_ yrc: String) -> [TimedLine] {
        let lineRegex = try! NSRegularExpression(pattern: "^\\[(\\d+),\\d+\\](.*)$")
        let wordRegex = try! NSRegularExpression(pattern: "\\((\\d+),(\\d+),-?\\d+\\)(.*?)(?=\\(\\d+,\\d+,-?\\d+\\)|$)")
        return yrc.components(separatedBy: .newlines).compactMap { raw in
            let row = raw.trimmingCharacters(in: .whitespaces) as NSString
            guard let match = lineRegex.firstMatch(in: row as String, range: NSRange(location: 0, length: row.length)) else { return nil }
            let start = Int(row.substring(with: match.range(at: 1))) ?? 0
            let body = row.substring(with: match.range(at: 2)) as NSString
            let words = wordRegex.matches(in: body as String, range: NSRange(location: 0, length: body.length)).map { word in
                let wordStart = Int(body.substring(with: word.range(at: 1))) ?? 0
                let length = Int(body.substring(with: word.range(at: 2))) ?? 0
                return (text: body.substring(with: word.range(at: 3)), startMs: wordStart, endMs: wordStart + length)
            }
            return TimedLine(startMs: start, text: words.map(\.text).joined().trimmingCharacters(in: .whitespaces), words: words)
        }
    }
}

// qq music with no account, timed per line, its word timing comes encrypted so it isn't read
nonisolated enum QQMusicLyrics {
    static func lyrics(_ query: LyricsQuery) async throws -> String? {
        let search = try await musicu(module: "music.search.SearchCgiService", method: "DoSearchForQQMusicDesktop", param: [
            "query": "\(LyricsMatch.cleanTitle(query.title)) \(query.firstArtist)",
            "num_per_page": 10,
            "page_num": 1,
            "search_type": 0,
        ])
        let candidates = search["req"]["data"]["body"]["song"]["list"].array.compactMap { song -> TrackCandidate<(Int, String)>? in
            guard let id = song["id"].int, let mid = song["mid"].string else { return nil }
            return TrackCandidate(
                titles: [song["name"].string ?? ""],
                artists: song["singer"].array.compactMap { $0["name"].string },
                durationSec: song["interval"].int ?? 0,
                ref: (id, mid)
            )
        }
        guard let (id, mid) = candidates.bestMatch(title: LyricsMatch.cleanTitle(query.title), artist: query.artist, durationSec: query.duration) else { return nil }
        let response = try await musicu(module: "music.musichallSong.PlayLyricInfo", method: "GetPlayLyricInfo", param: ["songMID": mid, "songID": id])
        guard let encoded = response["req"]["data"]["lyric"].string, let data = Data(base64Encoded: encoded), let lrc = String(data: data, encoding: .utf8) else { return nil }
        let lines = LRC.lines(lrc).withoutCredits()
        return lines.hasLyrics ? lines.toLRC() : nil
    }

    // every qq music call goes through this one endpoint, named by a module and a method
    private static func musicu(module: String, method: String, param: [String: Any]) async throws -> JSON {
        try JSON(data: try await LyricsHTTP.post("https://u.y.qq.com/cgi-bin/musicu.fcg", json: [
            "req": ["module": module, "method": method, "param": param],
        ]))
    }
}

// kugou: songs by keyword, lyrics by each song's hash, then a keyword lyrics search as a last try
nonisolated enum KuGou {
    static func lyrics(_ query: LyricsQuery) async throws -> String? {
        let title = normalizeTitle(query.title)
        let artist = normalizeArtist(query.artist)
        var keyword = "\(title) - \(artist)"
        if let album = query.album, !album.isEmpty { keyword += " \(album)" }

        let songs = try await LyricsHTTP.json("https://mobileservice.kugou.com/api/v3/search/song", query: [
            "version": "9108", "plat": "0", "pagesize": "8", "showtype": "0", "keyword": keyword,
        ])
        for song in songs["data"]["info"].array {
            guard let hash = song["hash"].string else { continue }
            if query.duration > 0, abs((song["duration"].int ?? 0) - query.duration) > 8 { continue }
            if let candidate = try? await searchLyrics(["hash": hash]).first, let lrc = try await download(candidate) {
                return lrc
            }
        }
        var byKeyword: [String: String?] = ["keyword": keyword]
        if query.duration > 0 { byKeyword["duration"] = String(query.duration * 1000) }
        guard let candidate = try await searchLyrics(byKeyword).first else { return nil }
        return try await download(candidate)
    }

    private static func searchLyrics(_ parameters: [String: String?]) async throws -> [(id: String, key: String)] {
        let json = try await LyricsHTTP.json("https://lyrics.kugou.com/search", query: parameters.merging(["ver": "1", "man": "yes", "client": "pc"]) { first, _ in first })
        return json["candidates"].array.compactMap { candidate in
            guard let id = candidate["id"].string ?? candidate["id"].int.map(String.init), let key = candidate["accesskey"].string else { return nil }
            return (id, key)
        }
    }

    private static func download(_ candidate: (id: String, key: String)) async throws -> String? {
        let json = try await LyricsHTTP.json("https://lyrics.kugou.com/download", query: [
            "fmt": "lrc", "charset": "utf8", "client": "pc", "ver": "1", "id": candidate.id, "accesskey": candidate.key,
        ])
        guard let content = json["content"].string, let data = Data(base64Encoded: content), let lrc = String(data: data, encoding: .utf8) else { return nil }
        let lines = LRC.lines(trimmedCredits(lrc)).withoutCredits()
        return lines.hasLyrics ? lines.toLRC() : nil
    }

    // kugou's own rule: any "label：value" line in the first or last thirty is a credit, it and everything outside it goes
    private static func trimmedCredits(_ lrc: String) -> String {
        let lines = lrc.components(separatedBy: .newlines).filter { $0.range(of: "^\\[(\\d\\d):(\\d\\d)\\.(\\d{2,3})\\].*", options: .regularExpression) != nil }
        let isCredit = { (line: String) in line.range(of: ".+\\].+[:：].+", options: .regularExpression) != nil }
        guard !lines.isEmpty else { return lrc }
        var head = 0
        for index in stride(from: min(30, lines.count - 1), through: 0, by: -1) where isCredit(lines[index]) {
            head = index + 1
            break
        }
        var tail = 0
        for offset in stride(from: min(lines.count - 30, lines.count - 1), through: 0, by: -1) where offset >= 0 && isCredit(lines[lines.count - 1 - offset]) {
            tail = offset + 1
            break
        }
        let kept = lines.dropFirst(head).dropLast(tail)
        return kept.joined(separator: "\n")
    }

    private static func normalizeTitle(_ title: String) -> String {
        var out = title
        for pattern in ["\\(.*\\)", "（.*）", "「.*」", "『.*』", "<.*>", "《.*》", "〈.*〉", "＜.*＞"] {
            out = out.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    private static func normalizeArtist(_ artist: String) -> String {
        artist.replacingOccurrences(of: ", ", with: "、").replacingOccurrences(of: " & ", with: "、")
            .replacingOccurrences(of: ".", with: "").replacingOccurrences(of: "和", with: "、")
            .replacingOccurrences(of: "\\(.*\\)|（.*）", with: "", options: .regularExpression)
    }
}
