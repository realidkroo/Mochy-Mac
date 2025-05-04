import Foundation

// turns every lyrics format the sources send into timed lines: plain lrc, lrc with a "<word:start:end|...>" line under it, and enhanced lrc with "<mm:ss.xx>" before each word
nonisolated enum LyricsParser {
    private struct Piece {
        var text: String
        var start: Double
        var end: Double
    }

    private struct RawLine {
        var time: Double
        var text: String
        var pieces: [Piece] = []
        var agent: String?
        var isBackground = false
    }

    static func parse(_ raw: String, provider: LyricsProvider) -> Lyrics? {
        let text = cleaned(raw)
        let rows = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("[offset:") }
        guard !rows.isEmpty else { return nil }

        let isEnhanced = rows.contains { row in
            !leadingStamps(row).times.isEmpty && row.contains("<") && firstInlineStamp(in: row) != nil
        }
        let raws = isEnhanced ? parseEnhanced(rows) : parseStandard(rows)
        let timed = raws.filter { !$0.text.isEmpty || !$0.pieces.isEmpty }
        // stamps that are all the same moment carry no timing at all
        if timed.isEmpty || Set(timed.map(\.time)).count == 1 && timed.count > 1 || timed.count == 1 && timed[0].time == 0 {
            return plain(text, provider: provider)
        }
        return assemble(raws, provider: provider)
    }

    // untimed text, one line per row, blank rows kept once as a gap between verses
    static func plain(_ text: String, provider: LyricsProvider) -> Lyrics? {
        var lines: [LyricLine] = []
        var lastWasBlank = true
        for row in cleaned(text).components(separatedBy: .newlines) {
            let line = stripStamps(row).trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if lastWasBlank { continue }
                lastWasBlank = true
            } else {
                lastWasBlank = false
            }
            lines.append(LyricLine(id: lines.count, time: 0, text: line, words: []))
        }
        while lines.last?.text.isEmpty == true { lines.removeLast() }
        guard lines.contains(where: { !$0.text.isEmpty }) else { return nil }
        return Lyrics(lines: lines, sync: .plain, provider: provider)
    }

    // MARK: formats

    private static func parseStandard(_ rows: [String]) -> [RawLine] {
        var result: [RawLine] = []
        var lastRowRange: Range<Int>?
        for row in rows {
            if row.hasPrefix("<"), row.hasSuffix(">"), let range = lastRowRange {
                let pieces = wordLine(String(row.dropFirst().dropLast()))
                for index in range { result[index].pieces = pieces }
                lastRowRange = nil
                continue
            }
            let (times, rest) = leadingStamps(row)
            guard !times.isEmpty else { lastRowRange = nil; continue }
            let (agent, isBackground, content) = markers(rest)
            let start = result.count
            for time in times {
                result.append(RawLine(time: time, text: collapse(content), agent: agent, isBackground: isBackground))
            }
            lastRowRange = start..<result.count
        }
        return result
    }

    private static func parseEnhanced(_ rows: [String]) -> [RawLine] {
        var parsed: [(time: Double, rest: Substring)] = []
        for row in rows {
            let (times, rest) = leadingStamps(row)
            guard let time = times.first else { continue }
            parsed.append((time, rest))
        }
        var result: [RawLine] = []
        for (index, entry) in parsed.enumerated() {
            let (agent, isBackground, content) = markers(entry.rest)
            let nextLine = parsed.indices.contains(index + 1) ? parsed[index + 1].time : nil
            var pieces = inlinePieces(content)
            // a final stamp with no word after it is where the last word stops
            if let last = pieces.last, last.text.trimmingCharacters(in: .whitespaces).isEmpty, pieces.count > 1 {
                pieces.removeLast()
                pieces[pieces.count - 1].end = last.start
            } else if !pieces.isEmpty {
                let spans = pieces.dropLast().map { $0.end - $0.start }
                let typical = spans.isEmpty ? 0.6 : spans.reduce(0, +) / Double(spans.count)
                let guess = pieces[pieces.count - 1].start + max(1.2, typical * 2.5)
                pieces[pieces.count - 1].end = min(nextLine ?? guess, guess)
            }
            let plainText = collapse(removeInlineStamps(content))
            result.append(RawLine(time: entry.time, text: plainText, pieces: pieces, agent: agent, isBackground: isBackground))
        }
        return result
    }

    // "<word:1.2:1.5|next:1.5:1.9>" in seconds, a word may not hold the separators
    private static func wordLine(_ data: String) -> [Piece] {
        data.split(separator: "|").compactMap { part in
            let fields = part.split(separator: ":", omittingEmptySubsequences: false)
            guard fields.count >= 3, let start = Double(fields[fields.count - 2]), let end = Double(fields[fields.count - 1]) else { return nil }
            let text = fields[0..<(fields.count - 2)].joined(separator: ":")
            return Piece(text: text, start: start, end: max(end, start))
        }
    }

    // MARK: building lines

    private static func assemble(_ raws: [RawLine], provider: LyricsProvider) -> Lyrics? {
        let gluedSong = spacesDropped(raws)
        var mains: [RawLine] = []
        var backings: [Int: RawLine] = [:]
        var blankEnds: [Int: Double] = [:]

        for line in raws {
            if line.text.isEmpty && line.pieces.isEmpty {
                // an empty stamped line in plain lrc marks where the line before it stops
                if !mains.isEmpty { blankEnds[mains.count - 1] = line.time }
                continue
            }
            if line.isBackground, !mains.isEmpty {
                let owner = mains.count - 1
                if var existing = backings[owner] {
                    existing.text += " " + line.text
                    existing.pieces += line.pieces
                    backings[owner] = existing
                } else {
                    backings[owner] = line
                }
                continue
            }
            mains.append(line)
        }
        guard !mains.isEmpty else { return nil }

        let order = mains.indices.sorted { mains[$0].time < mains[$1].time }
        var lines: [LyricLine] = []
        for index in order {
            let raw = mains[index]
            let words = buildWords(text: raw.text, pieces: raw.pieces, gluedSong: gluedSong)
            let text = gluedSong && words.count > 1 && !raw.text.contains(where: \.isWhitespace) ? spacedText(words) : raw.text
            var backing: BackingVocal?
            if let back = backings[index] {
                let backWords = buildWords(text: back.text, pieces: back.pieces, gluedSong: gluedSong)
                backing = BackingVocal(time: back.time, text: back.text.isEmpty ? spacedText(backWords) : back.text, words: backWords)
            }
            let wordsEnd = max(words.last?.end ?? 0, backing?.words.last?.end ?? 0)
            lines.append(LyricLine(
                id: lines.count,
                time: raw.time,
                text: text.isEmpty ? spacedText(words) : text,
                words: words,
                agent: raw.agent,
                backing: backing,
                end: wordsEnd > 0 ? wordsEnd : blankEnds[index]
            ))
        }
        let wordLines = lines.filter { !$0.words.isEmpty }.count
        let sync: LyricsSync = wordLines * 2 >= lines.count && wordLines > 0 ? .word : .line
        return Lyrics(lines: lines, sync: sync, provider: provider)
    }

    // the timed pieces as whole words: pieces with nothing between them in the line's text are one word, sung from the first's start to the last's end
    private static func buildWords(text: String, pieces: [Piece], gluedSong: Bool) -> [LyricWord] {
        guard !pieces.isEmpty else { return [] }
        let gluedLine = gluedSong && !text.contains(where: \.isWhitespace)
        var words: [LyricWord] = []
        var cursor = text.startIndex
        var lastEnd: String.Index?

        for piece in pieces {
            let trimmed = piece.text.trimmingCharacters(in: .whitespaces)
            guard let first = trimmed.first else {
                // a timed space is a word boundary
                if !words.isEmpty { words[words.count - 1].spaceAfter = true }
                lastEnd = nil
                continue
            }
            if gluedLine {
                words.append(LyricWord(text: trimmed, start: piece.start, end: piece.end, spaceAfter: !Script.isUnspaced(first)))
                continue
            }
            if let range = find(trimmed, in: text, from: cursor) {
                let spaceAfter = range.upperBound < text.endIndex && text[range.upperBound].isWhitespace
                let glued = lastEnd == range.lowerBound
                    && range.lowerBound > text.startIndex
                    && !Script.isUnspaced(text[text.index(before: range.lowerBound)])
                    && !Script.isUnspaced(first)
                if glued, let previous = words.popLast() {
                    words.append(LyricWord(text: previous.text + trimmed, start: previous.start, end: max(previous.end, piece.end), spaceAfter: spaceAfter))
                } else {
                    words.append(LyricWord(text: trimmed, start: piece.start, end: piece.end, spaceAfter: spaceAfter))
                }
                cursor = range.upperBound
                lastEnd = range.upperBound
            } else {
                let spaceAfter = piece.text.last?.isWhitespace == true || !Script.isUnspaced(first)
                words.append(LyricWord(text: trimmed, start: piece.start, end: piece.end, spaceAfter: spaceAfter))
                lastEnd = nil
            }
        }
        // a word that starts with punctuation hugs the one before it
        for index in words.indices.dropFirst() where ",.!?;:)]}…".contains(words[index].text.first ?? " ") {
            words[index - 1].spaceAfter = false
        }
        if !words.isEmpty { words[words.count - 1].spaceAfter = false }
        return words
    }

    // finds a piece in the line, but only past text that holds no letters, so a repeated word can't jump ahead
    private static func find(_ piece: String, in text: String, from cursor: String.Index) -> Range<String.Index>? {
        guard cursor < text.endIndex, let range = text.range(of: piece, range: cursor..<text.endIndex) else { return nil }
        let skipped = text[cursor..<range.lowerBound]
        return skipped.contains(where: { $0.isLetter || $0.isNumber }) ? nil : range
    }

    // some sources drop every space: most multi-piece lines then read like "Iloveyou"
    private static func spacesDropped(_ raws: [RawLine]) -> Bool {
        let candidates = raws.filter { line in
            line.pieces.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }.count >= 2
                && !Script.dominant(in: line.text).isUnspaced && Script.dominant(in: line.text) != .unknown
        }
        guard candidates.count >= 3 else { return false }
        let glued = candidates.filter { !$0.text.contains(where: \.isWhitespace) }
        return glued.count * 5 >= candidates.count * 4
    }

    private static func spacedText(_ words: [LyricWord]) -> String {
        words.map { $0.text + ($0.spaceAfter ? " " : "") }.joined().trimmingCharacters(in: .whitespaces)
    }

    // MARK: small readers

    // the "[mm:ss.xx]" stamps at the start of a row, and what's left after them
    private static func leadingStamps(_ row: String) -> (times: [Double], rest: Substring) {
        var rest = Substring(row)
        var times: [Double] = []
        while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
            let inner = rest[rest.index(after: rest.startIndex)..<close]
            guard let time = stamp(inner) else { break }
            times.append(time)
            rest = rest[rest.index(after: close)...]
        }
        return (times, rest)
    }

    private static func stripStamps(_ row: String) -> String {
        String(leadingStamps(row).rest)
    }

    // "01:23.45", "1:23", "01:23:45" (a colon before the hundredths) into seconds
    private static func stamp(_ text: Substring) -> Double? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isNumber || $0 == "." } }) else { return nil }
        guard let minutes = Double(parts[0]) else { return nil }
        if parts.count == 2 {
            guard let seconds = Double(parts[1]) else { return nil }
            return minutes * 60 + seconds
        }
        guard let seconds = Double(parts[1]), let fraction = Double("0." + parts[2]) else { return nil }
        return minutes * 60 + seconds + fraction
    }

    private static func markers(_ text: Substring) -> (agent: String?, isBackground: Bool, rest: String) {
        var rest = text.drop(while: \.isWhitespace)
        var agent: String?
        var isBackground = false
        while true {
            if rest.hasPrefix("{bg}") {
                isBackground = true
                rest = rest.dropFirst(4).drop(while: \.isWhitespace)
            } else if rest.hasPrefix("{agent:"), let close = rest.firstIndex(of: "}") {
                agent = String(rest[rest.index(rest.startIndex, offsetBy: 7)..<close])
                rest = rest[rest.index(after: close)...].drop(while: \.isWhitespace)
            } else {
                break
            }
        }
        return (agent, isBackground, String(rest))
    }

    private static func firstInlineStamp(in row: String) -> Range<String.Index>? {
        var search = row.startIndex
        while let open = row[search...].firstIndex(of: "<") {
            guard let close = row[open...].firstIndex(of: ">") else { return nil }
            if stamp(row[row.index(after: open)..<close]) != nil { return open..<row.index(after: close) }
            search = row.index(after: open)
        }
        return nil
    }

    // "<00:12.34>word <00:12.80>next" into pieces, each running until the next one starts
    private static func inlinePieces(_ content: String) -> [Piece] {
        var pieces: [Piece] = []
        var rest = Substring(content)
        while let range = firstInlineStamp(in: String(rest)) {
            let local = String(rest)
            let inner = local[local.index(after: range.lowerBound)..<local.index(before: range.upperBound)]
            guard let time = stamp(inner) else { break }
            let after = local[range.upperBound...]
            let nextRange = firstInlineStamp(in: String(after))
            let wordText: String
            if let nextRange {
                let afterString = String(after)
                wordText = String(afterString[..<nextRange.lowerBound])
                rest = Substring(afterString[nextRange.lowerBound...])
            } else {
                wordText = String(after)
                rest = ""
            }
            if !pieces.isEmpty { pieces[pieces.count - 1].end = time }
            pieces.append(Piece(text: wordText, start: time, end: time + 0.5))
            if nextRange == nil { break }
        }
        return pieces
    }

    private static func removeInlineStamps(_ content: String) -> String {
        var result = content
        while let range = firstInlineStamp(in: result) {
            result.removeSubrange(range)
        }
        return result
    }

    private static func collapse(_ text: String) -> String {
        text.replacingOccurrences(of: "[\\t\\u00A0 ]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    // json-escaped answers and html entities show up in a few sources
    private static func cleaned(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("\""), text.hasSuffix("\""), text.count > 1 { text = String(text.dropFirst().dropLast()) }
        if !text.contains("\n"), text.contains("\\n") {
            text = text.replacingOccurrences(of: "\\r", with: "").replacingOccurrences(of: "\\n", with: "\n")
        }
        let entities = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&#x27;": "'"]
        for (entity, value) in entities where text.contains(entity) {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        return text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}

// which writing system a line is in, used to tell a translation from the original
nonisolated enum Script: String, Sendable {
    case latin, han, kana, hangul, cyrillic, arabic, devanagari, thai, greek, hebrew, unknown

    var isNative: Bool { self != .latin && self != .unknown }
    var isUnspaced: Bool { self == .han || self == .kana || self == .thai }

    static func of(_ scalar: Unicode.Scalar) -> Script? {
        switch scalar.value {
        case 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F, 0x1E00...0x1EFF: .latin
        case 0x3040...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F: .kana
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF: .han
        case 0xAC00...0xD7AF, 0x1100...0x11FF, 0x3130...0x318F: .hangul
        case 0x0400...0x04FF: .cyrillic
        case 0x0600...0x06FF, 0x0750...0x077F: .arabic
        case 0x0900...0x097F: .devanagari
        case 0x0E00...0x0E7F: .thai
        case 0x0370...0x03FF: .greek
        case 0x0590...0x05FF: .hebrew
        default: nil
        }
    }

    static func isUnspaced(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first, let script = of(scalar) else { return false }
        return script.isUnspaced
    }

    // the script most letters are in; any kana at all makes kanji japanese
    static func dominant(in text: String) -> Script {
        var counts: [Script: Int] = [:]
        for scalar in text.unicodeScalars {
            if let script = of(scalar) { counts[script, default: 0] += 1 }
        }
        guard let top = counts.max(by: { $0.value < $1.value }) else { return .unknown }
        if top.key == .han, (counts[.kana] ?? 0) > 0 { return .kana }
        return top.key
    }
}
