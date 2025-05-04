import Foundation

// one sung word, or a piece of one, timed in seconds from the start of the song
nonisolated struct LyricWord: Hashable, Sendable {
    let text: String
    let start: Double
    let end: Double
    // chinese, japanese and thai pieces sit flush, everything else gets a space after
    var spaceAfter: Bool
}

// the quieter echo some songs carry under a line, sung at its own time
nonisolated struct BackingVocal: Hashable, Sendable {
    let time: Double
    let text: String
    let words: [LyricWord]
}

nonisolated struct LyricLine: Hashable, Sendable, Identifiable {
    let id: Int
    let time: Double
    let text: String
    let words: [LyricWord]
    var agent: String? = nil
    var backing: BackingVocal? = nil
    // when the singing stops, from the last word or from an empty stamped line after it
    var end: Double? = nil

    // the second singer of a duet sits on the right, like the android app lays it out
    var isOppositeVoice: Bool {
        guard let agent else { return false }
        return agent == "v2" || agent == "v2000"
    }
}

nonisolated enum LyricsSync: Int, Comparable, Sendable {
    case plain = 1, line, word

    static func < (lhs: LyricsSync, rhs: LyricsSync) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .plain: String(localized: "Plain")
        case .line: String(localized: "Line synced")
        case .word: String(localized: "Word synced")
        }
    }
}

nonisolated struct Lyrics: Sendable {
    let lines: [LyricLine]
    let sync: LyricsSync
    let provider: LyricsProvider

    var isSynced: Bool { sync != .plain }
    var hasDuet: Bool { lines.contains { $0.isOppositeVoice } && lines.contains { !$0.isOppositeVoice && $0.agent != nil } }
    var hasVoiceTags: Bool { lines.contains { $0.agent != nil } }
}

nonisolated extension Double {
    var nonZero: Double? { self > 0 ? self : nil }
}
