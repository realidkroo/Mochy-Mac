import Foundation

// apple music's ttml through the better lyrics server
nonisolated enum BetterLyrics {
    static func lyrics(_ query: LyricsQuery) async throws -> String? {
        let json = try await LyricsHTTP.json("https://lyrics-api.boidu.dev/getLyrics", query: [
            "s": LyricsMatch.cleanTitle(query.title),
            "a": query.artist,
            "d": query.duration > 0 ? String(query.duration) : nil,
            "al": query.album?.isEmpty == false ? query.album : nil,
        ], timeout: 15)
        guard let ttml = json["ttml"].string else { return nil }
        return TTMLParser.toLRC(ttml)
    }
}

// apple music lyrics through paxsenix: search, score the hits, then take the best one that has word timing
nonisolated enum Paxsenix {
    private static let base = "https://lyrics.paxsenix.org"
    private static let headers = ["User-Agent": "Mochy/0.1 (macOS)"]

    private struct Hit: Sendable {
        let id: String
        let name: String
        let artist: String
        let durationMs: Int?
    }

    static func lyrics(_ query: LyricsQuery) async -> String? {
        let title = LyricsMatch.cleanTitle(query.title)
        let artist = LyricsMatch.cleanArtist(query.artist)
        var queries = ["\(title) \(artist)", title]
        if let album = query.album, !album.isEmpty { queries.append("\(title) \(artist) \(album)") }

        var scored: [Hit] = []
        for text in queries where scored.isEmpty {
            let hits = await search(text)
            if !hits.isEmpty { scored = score(hits, title: query.title, artist: query.artist, duration: query.duration) }
        }
        guard !scored.isEmpty else { return nil }

        // the top few are asked at once, word-timed lyrics win, line-timed ones are kept as a fallback
        return await withTaskGroup(of: (String, Bool)?.self) { group in
            for hit in scored.prefix(5) {
                group.addTask { await fetch(hit.id) }
            }
            var fallback: String?
            for await result in group {
                guard let (lrc, hasWords) = result, !lrc.isEmpty else { continue }
                if hasWords {
                    group.cancelAll()
                    return lrc
                }
                fallback = fallback ?? lrc
            }
            return fallback
        }
    }

    private static func search(_ text: String) async -> [Hit] {
        guard let json = try? await LyricsHTTP.json(base + "/apple-music/search", query: ["q": text], headers: headers, timeout: 6) else { return [] }
        return json.array.compactMap { item in
            guard let id = item["id"].string ?? item["id"].int.map(String.init) else { return nil }
            return Hit(
                id: id,
                name: item["trackName"].string ?? item["songName"].string ?? "",
                artist: item["artistName"].string ?? "",
                durationMs: item["duration"].int
            )
        }
    }

    private static func score(_ hits: [Hit], title: String, artist: String, duration: Int) -> [Hit] {
        let bracketed = "\\s*\\(.*?\\)|\\s*\\[.*?\\]"
        let wantedTitle = title.replacingOccurrences(of: bracketed, with: "", options: .regularExpression).lowercased().trimmingCharacters(in: .whitespaces)
        let wantedArtist = LyricsMatch.cleanArtist(artist).lowercased()
        let wantsMixed = title.localizedCaseInsensitiveContains("mixed")
        let wantsRemix = title.localizedCaseInsensitiveContains("remix")

        let ranked = hits.map { hit -> (Hit, Double) in
            var score = 0.0
            if let ms = hit.durationMs, duration > 0 {
                let diff = abs(ms - duration * 1000)
                score += diff <= 2000 ? 100 : diff <= 5000 ? 50 : diff <= 10000 ? 10 : -50
            }
            let name = hit.name.replacingOccurrences(of: bracketed, with: "", options: .regularExpression).lowercased().trimmingCharacters(in: .whitespaces)
            if name == wantedTitle { score += 80 } else if name.contains(wantedTitle) || wantedTitle.contains(name) { score += 40 }
            if hit.name.localizedCaseInsensitiveContains("mixed"), !wantsMixed { score -= 60 }
            if hit.name.localizedCaseInsensitiveContains("remix"), !wantsRemix { score -= 40 }
            let hitArtist = hit.artist.lowercased()
            if hitArtist.contains(wantedArtist) {
                score += 50
            } else if wantedArtist.split(separator: " ").contains(where: { $0.count > 2 && hitArtist.contains($0) }) {
                score += 25
            }
            return (hit, score)
        }
        return ranked.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(10).map(\.0)
    }

    // the lyrics for one apple music track, and whether they carry word timing
    private static func fetch(_ id: String) async -> (String, Bool)? {
        guard let json = try? await LyricsHTTP.json(base + "/apple-music/lyrics", query: ["id": id], headers: headers, timeout: 8) else { return nil }
        let lrc: String? = {
            if let ttml = json["ttmlContent"].string, !ttml.isEmpty, let converted = TTMLParser.toLRC(ttml) { return converted }
            if let elrc = json["elrcMultiPerson"].string, !elrc.isEmpty { return elrc }
            if let elrc = json["elrc"].string, !elrc.isEmpty { return elrc }
            if let plain = json["plain"].string, !plain.isEmpty { return plain }
            return fromContent(json["content"].array, wordLevel: json["type"].string == "Syllable")
        }()
        guard let lrc, !lrc.isEmpty else { return nil }
        return (lrc, lrc.contains("<") && lrc.contains(">"))
    }

    private static func fromContent(_ content: [JSON], wordLevel: Bool) -> String? {
        guard !content.isEmpty else { return nil }
        let timed = content.contains { ($0["timestamp"].int ?? 0) > 0 }
        var out: [String] = []
        for line in content {
            let pieces = line["text"].array
            let text = joinedText(pieces)
            guard !text.isEmpty else { continue }
            let ms = line["timestamp"].int ?? 0
            if !timed {
                out.append(text)
                continue
            }
            guard wordLevel else {
                out.append(TimedLine.stamp(ms) + text)
                continue
            }
            let agent = line["background"].bool == true ? "{bg}" : line["oppositeTurn"].bool == true ? "{agent:v2}" : "{agent:v1}"
            out.append(TimedLine.stamp(ms) + agent + text)
            let words = pieces.map { piece in
                let start = Double(piece["timestamp"].int ?? 0) / 1000
                let end = Double(piece["endtime"].int ?? 0) / 1000
                return "\((piece["text"].string ?? "").filter { !":|<>".contains($0) }):\(start):\(end)"
            }
            if !words.isEmpty { out.append("<" + words.joined(separator: "|") + ">") }
        }
        return out.joined(separator: "\n")
    }

    // syllable pieces are joined by the api's own trailing space or its "part" flag, so words don't fall apart into "wa nt yo u"
    private static func joinedText(_ pieces: [JSON]) -> String {
        let texts = pieces.map { $0["text"].string ?? "" }
        let spacedByApi = texts.dropLast().contains { $0.last?.isWhitespace == true }
        var out = ""
        for (index, piece) in pieces.enumerated() {
            let text = texts[index]
            out += text
            let isLast = index == pieces.count - 1
            if !spacedByApi, !isLast, piece["part"].bool != true, text.last?.isWhitespace != true { out += " " }
        }
        return out.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }
}
