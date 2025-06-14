import Foundation

// what every source is asked with, all artists joined the way the android app passes them
nonisolated struct LyricsQuery: Sendable, Hashable {
    let videoId: String
    let title: String
    let artist: String
    let firstArtist: String
    let album: String?
    // seconds, -1 when we don't know it yet
    let duration: Int
    let lyricsBrowseId: String?

    init(song: SongItem, duration: Int?, lyricsBrowseId: String?) {
        videoId = song.id
        title = song.title
        artist = song.artists.map(\.name).joined(separator: ", ")
        firstArtist = song.artists.first?.name ?? ""
        album = song.album?.name
        self.duration = duration ?? song.duration ?? -1
        self.lyricsBrowseId = lyricsBrowseId
    }
}

nonisolated enum LyricsHTTPError: Error {
    case status(Int)
}

// one session for every lyrics source, and it says who's asking so a server owner can reach us instead of blocking us
nonisolated enum LyricsHTTP {
    static let userAgent = "Mochy (+https://github.com/realidkroo/Mochy-Music)"

    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.httpAdditionalHeaders = ["User-Agent": userAgent, "Accept": "application/json, text/plain, */*"]
        return URLSession(configuration: config)
    }()

    static func get(_ base: String, query: [String: String?] = [:], headers: [String: String] = [:], timeout: TimeInterval = 10) async throws -> Data {
        var components = URLComponents(string: base)!
        // encoded the way android's ktor does it, commas and all, so we land on the same cached answers on these servers
        let pairs = query.compactMap { key, value in value.map { (key, $0) } }.sorted { $0.0 < $1.0 }
        if !pairs.isEmpty {
            let encoded = pairs.map { "\(encode($0.0))=\(encode($0.1))" }.joined(separator: "&")
            components.percentEncodedQuery = [components.percentEncodedQuery, encoded].compactMap { $0 }.joined(separator: "&")
        }
        var request = URLRequest(url: components.url!, timeoutInterval: timeout)
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        return try await send(request)
    }

    private static let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    private static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }

    static func post(_ url: String, json: [String: Any], headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: URL(string: url)!, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        return try await send(request)
    }

    static func json(_ base: String, query: [String: String?] = [:], headers: [String: String] = [:], timeout: TimeInterval = 10) async throws -> JSON {
        try JSON(data: try await get(base, query: query, headers: headers, timeout: timeout))
    }

    private static func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LyricsHTTPError.status(http.statusCode)
        }
        return data
    }
}

// the clean-ups and matching every search-based source shares
nonisolated enum LyricsMatch {
    private static let noiseWords = "official|video|audio|lyrics|lyric|visualizer|hd|hq|4k|remaster|remix|live|acoustic|version|edit|extended|radio|clean|explicit"
    private static let titlePatterns = [
        "\\s*\\(.*?(\(noiseWords)).*?\\)",
        "\\s*\\[.*?(\(noiseWords)).*?\\]",
        "\\s*【.*?】",
        "\\s*\\|.*$",
        "\\s*-\\s*(official|video|audio|lyrics|lyric|visualizer).*$",
        "\\s*\\(feat\\..*?\\)",
        "\\s*\\(ft\\..*?\\)",
        "\\s*feat\\..*$",
        "\\s*ft\\..*$",
    ]
    private static let artistSeparators = [" & ", " and ", ", ", " x ", " X ", " feat. ", " feat ", " ft. ", " ft ", " featuring ", " with "]

    // "song (official video) [hd]" down to "song"
    static func cleanTitle(_ title: String) -> String {
        var cleaned = title.trimmingCharacters(in: .whitespaces)
        for pattern in titlePatterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    // "a & b, c" down to "a"
    static func cleanArtist(_ artist: String) -> String {
        let trimmed = artist.trimmingCharacters(in: .whitespaces)
        for separator in artistSeparators {
            if let range = trimmed.range(of: separator, options: .caseInsensitive) {
                return String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
        }
        return trimmed
    }

    // "blinding lights (remastered)", "晴天（深情版）" and "song [live]" all come down to the bare name
    static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s*[(（\\[【「『《].*?[)）\\]】」』》]", with: "", options: .regularExpression)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    static func similarity(_ first: String, _ second: String) -> Double {
        let a = first.trimmingCharacters(in: .whitespaces).lowercased()
        let b = second.trimmingCharacters(in: .whitespaces).lowercased()
        if a == b { return 1 }
        if a.isEmpty || b.isEmpty { return 0 }
        let contains = a.contains(b) || b.contains(a) ? 0.8 : 0
        let distance = levenshtein(Array(a), Array(b))
        return max(contains, 1 - Double(distance) / Double(max(a.count, b.count)))
    }

    private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        var previous = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...max(b.count, 1) where !b.isEmpty {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            previous = current
        }
        return previous[b.count]
    }
}

// a search result cut down to what tells whether it's the song being played
nonisolated struct TrackCandidate<Ref: Sendable>: Sendable {
    let titles: [String]
    let artists: [String]
    let durationSec: Int
    let ref: Ref
}

nonisolated extension Array {
    // about the same length, same title and same artist when one matches, the top hit is often a cover or a live take
    func bestMatch<Ref>(title: String, artist: String, durationSec: Int) -> Ref? where Element == TrackCandidate<Ref> {
        let wantedTitle = LyricsMatch.normalize(title)
        let wantedArtist = LyricsMatch.normalize(artist)
        guard !wantedTitle.isEmpty else { return nil }
        var best: (ref: Ref, score: Int)?
        for candidate in self where durationSec <= 0 || abs(candidate.durationSec - durationSec) <= 8 {
            let titleScore = candidate.titles.map(LyricsMatch.normalize).filter { !$0.isEmpty }.map { name in
                name == wantedTitle ? 2 : (name.contains(wantedTitle) || wantedTitle.contains(name) ? 1 : 0)
            }.max() ?? 0
            guard titleScore > 0 else { continue }
            let artistScore = !wantedArtist.isEmpty && candidate.artists.map(LyricsMatch.normalize).contains { name in
                !name.isEmpty && (wantedArtist.contains(name) || name.contains(wantedArtist))
            } ? 2 : 0
            let score = titleScore + artistScore
            if best == nil || score > best!.score { best = (candidate.ref, score) }
        }
        return best?.ref
    }
}

// lines in the app's own lyrics format, a word-timed line is followed by its words as "<word:start:end|...>" in seconds
nonisolated struct TimedLine: Sendable {
    let startMs: Int
    let text: String
    var words: [(text: String, startMs: Int, endMs: Int)] = []

    static func stamp(_ ms: Int) -> String {
        String(format: "[%02d:%02d.%03d]", ms / 60_000, ms / 1000 % 60, ms % 1000)
    }
}

nonisolated extension Array where Element == TimedLine {
    func toLRC() -> String {
        var out = ""
        for line in self {
            out += TimedLine.stamp(line.startMs) + line.text + "\n"
            let words = line.words
                .map { (text: $0.text.trimmingCharacters(in: .whitespaces).filter { !":|<>".contains($0) }, $0.startMs, $0.endMs) }
                .filter { !$0.text.isEmpty }
            if !words.isEmpty {
                out += "<" + words.map { "\($0.text):\(Double($0.1) / 1000):\(Double($0.2) / 1000)" }.joined(separator: "|") + ">\n"
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // drops the credits chinese services put around the lyrics, "作词 : 方文山" and the like
    func withoutCredits() -> [TimedLine] {
        func isCredit(_ line: TimedLine) -> Bool {
            guard line.text.range(of: "^[^:：]{1,32}[:：].+$", options: .regularExpression) != nil else { return false }
            let label = line.text.split(whereSeparator: { $0 == ":" || $0 == "：" }).first ?? ""
            return label.split(separator: " ").count <= 4
        }
        let headCut = (prefix(15).lastIndex(where: isCredit) ?? -1) + 1
        let body = Array(dropFirst(headCut))
        let tailStart = Swift.max(body.count - 6, 0)
        if let tailCut = body[tailStart...].firstIndex(where: isCredit) {
            return Array(body[..<tailCut])
        }
        return body
    }

    // whether there's anything to sing along to, rather than "纯音乐，请欣赏" (instrumental, enjoy)
    var hasLyrics: Bool {
        let sung = filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        return !sung.isEmpty && !sung.contains { $0.text.contains("纯音乐") }
    }
}

nonisolated enum LRC {
    static let stampPattern = "^\\[(\\d{1,3}):(\\d{2})(?:[.:](\\d{1,3}))?\\](.*)$"

    // standard "[mm:ss.xx]text" lines, tag lines like [ti:] and anything untimed are dropped
    static func lines(_ lrc: String) -> [TimedLine] {
        let regex = try! NSRegularExpression(pattern: stampPattern)
        return lrc.components(separatedBy: .newlines).compactMap { raw in
            let row = raw.trimmingCharacters(in: .whitespaces)
            let ns = row as NSString
            guard let match = regex.firstMatch(in: row, range: NSRange(location: 0, length: ns.length)) else { return nil }
            let minutes = Int(ns.substring(with: match.range(at: 1))) ?? 0
            let seconds = Int(ns.substring(with: match.range(at: 2))) ?? 0
            let fraction = match.range(at: 3).location == NSNotFound ? "0" : ns.substring(with: match.range(at: 3))
            let millis = Int(String((fraction + "000").prefix(3))) ?? 0
            let text = ns.substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespaces)
            return TimedLine(startMs: minutes * 60_000 + seconds * 1000 + millis, text: text)
        }
    }
}
