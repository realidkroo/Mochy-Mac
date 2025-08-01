import Foundation

// one source's answer, parsed and graded so the picker can say what each has
nonisolated struct LyricsCandidate: Sendable, Identifiable {
    let provider: LyricsProvider
    let lyrics: Lyrics
    let order: Int
    let script: Script

    var id: String { provider.rawValue }
}

nonisolated struct LyricsOutcome: Sendable {
    let best: Lyrics?
    let candidates: [LyricsCandidate]
}

// asks every lyrics source at once and keeps the one most likely to be the song as sung, graded like the android app
actor LyricsService {
    static let shared = LyricsService()

    private var cache: [String: LyricsOutcome] = [:]
    private var chosen: [String: Lyrics] = [:]

    // the best lyrics we can find quickly: waits for everyone, but not long once good word-timed lyrics are in
    func lyrics(for query: LyricsQuery) async -> LyricsOutcome {
        if let picked = chosen[query.videoId] {
            return LyricsOutcome(best: picked, candidates: cache[query.videoId]?.candidates ?? [])
        }
        if let cached = cache[query.videoId] { return cached }

        let providers = LyricsSettings.orderedEnabled
        let regular = providers.filter { $0 != .youTubeCaptions }
        var candidates = await collect(query, providers: regular, settleEarly: true)
        var best = Self.pickBest(candidates, query: query, providerCount: providers.count)
        // youtube's auto captions are speech recognition, only worth asking when nobody else had anything
        if best == nil, providers.contains(.youTubeCaptions) {
            candidates += await collect(query, providers: [.youTubeCaptions], settleEarly: false)
            best = Self.pickBest(candidates, query: query, providerCount: providers.count)
        }
        let outcome = LyricsOutcome(best: best?.lyrics, candidates: candidates)
        // plain text may only mean the better sources were slow this time, so only synced answers are kept
        if best?.lyrics.isSynced == true { cache[query.videoId] = outcome }
        return outcome
    }

    // every enabled source, waiting for all of them, for the source picker
    func allCandidates(for query: LyricsQuery) async -> [LyricsCandidate] {
        let candidates = await collect(query, providers: LyricsSettings.orderedEnabled, settleEarly: false)
        if let existing = cache[query.videoId] {
            cache[query.videoId] = LyricsOutcome(best: existing.best, candidates: candidates)
        }
        return candidates
    }

    // remembers a source picked by hand, so coming back to the song shows it again
    func choose(_ lyrics: Lyrics, for videoId: String) {
        chosen[videoId] = lyrics
    }

    func forget(_ videoId: String) {
        cache[videoId] = nil
        chosen[videoId] = nil
    }

    private enum Event: Sendable {
        case answer(LyricsCandidate?)
        case settle
        case deadline
    }

    private func collect(_ query: LyricsQuery, providers: [LyricsProvider], settleEarly: Bool) async -> [LyricsCandidate] {
        let order = LyricsSettings.orderedEnabled
        return await withTaskGroup(of: Event.self) { group in
            for provider in providers {
                let rank = order.firstIndex(of: provider) ?? order.count
                group.addTask { .answer(await Self.ask(provider, query: query, order: rank)) }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(settleEarly ? 9 : 14))
                return .deadline
            }
            var found: [LyricsCandidate] = []
            var pending = providers.count
            var settling = false
            for await event in group {
                switch event {
                case .answer(let candidate):
                    pending -= 1
                    if let candidate { found.append(candidate) }
                    if pending == 0 {
                        group.cancelAll()
                        return found
                    }
                    // once a trusted source has word timing, the rest get a short grace period
                    if settleEarly, !settling, let candidate, candidate.lyrics.sync == .word, !candidate.provider.isChinese {
                        settling = true
                        group.addTask {
                            try? await Task.sleep(for: .seconds(1.5))
                            return .settle
                        }
                    } else if settleEarly, !settling, candidate != nil, found.count == 1 {
                        settling = true
                        group.addTask {
                            try? await Task.sleep(for: .seconds(4))
                            return .settle
                        }
                    }
                case .settle, .deadline:
                    group.cancelAll()
                    return found
                }
            }
            return found
        }
    }

    nonisolated private static func ask(_ provider: LyricsProvider, query: LyricsQuery, order: Int) async -> LyricsCandidate? {
        guard let raw = try? await provider.fetch(query), !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let lyrics = LyricsParser.parse(raw, provider: provider), !lyrics.lines.isEmpty else { return nil }
        let text = lyrics.lines.prefix(40).map(\.text).joined(separator: " ")
        guard text.contains(where: \.isLetter) else { return nil }
        return LyricsCandidate(provider: provider, lyrics: lyrics, order: order, script: Script.dominant(in: text))
    }

    // language first (decided from the song itself when it can be), then word over line over plain timing, then duet tags, then the user's order
    nonisolated static func pickBest(_ candidates: [LyricsCandidate], query: LyricsQuery, providerCount: Int) -> LyricsCandidate? {
        guard !candidates.isEmpty else { return nil }
        let metadata = Script.dominant(in: [query.title, query.artist, query.album ?? ""].joined(separator: " "))
        var reference: Script? = metadata.isNative ? metadata : candidates.first { $0.provider.isLanguageReference && $0.script.isNative }?.script
        // chinese sources don't put kana into chinese songs, so any kana makes an all-kanji name japanese
        if reference == .han, candidates.contains(where: { $0.script == .kana }) { reference = .kana }

        let regular = candidates.filter { !$0.provider.isChinese && $0.provider != .youTubeCaptions }
        let chineseSong = reference == .han || (reference == nil && majority(regular.map(\.script), minVotes: 1) == .han && !candidates.contains { $0.script == .kana })
        let songScript = reference ?? majority(regular.map(\.script), minVotes: 1)

        var pool = regular
        if chineseSong {
            pool += candidates.filter(\.provider.isChinese)
        } else {
            // their word timing is often the only word timing there is, as long as it's in the song's own script
            pool += candidates.filter { $0.provider.isChinese && $0.lyrics.sync == .word && (songScript == nil || $0.script == songScript) }
        }
        if pool.isEmpty { pool = candidates.filter { $0.provider.isChinese && (songScript == nil || $0.script == songScript || !$0.script.isNative) } }
        if pool.isEmpty { pool = candidates.filter { $0.provider == .youTubeCaptions } }
        guard !pool.isEmpty else { return nil }

        let majorityScript = reference == nil ? majority(pool.map(\.script), minVotes: 2) : nil
        var trustedNative: Set<Script> = []
        if reference == nil, majorityScript == nil {
            // a non-latin answer is believed when two sources agree on it, or when it's japanese or korean
            var counts: [Script: Int] = [:]
            for script in pool.map(\.script) where script.isNative { counts[script, default: 0] += 1 }
            trustedNative = Set(counts.filter { $0.value >= 2 || $0.key == .kana || $0.key == .hangul }.map(\.key))
        }

        func score(_ candidate: LyricsCandidate) -> Int {
            let scriptScore: Int
            if let reference {
                let sameFamily = Set([candidate.script, reference]) == Set<Script>([.han, .kana])
                scriptScore = candidate.script == reference ? 3 : (sameFamily ? 2 : (candidate.script == .unknown ? 1 : 0))
            } else if let majorityScript {
                scriptScore = candidate.script == majorityScript ? 3 : (candidate.script == .unknown ? 1 : 0)
            } else if !trustedNative.isEmpty {
                scriptScore = trustedNative.contains(candidate.script) ? 2 : (candidate.script == .unknown ? 1 : 0)
            } else {
                // nothing points at a non-latin original, so a lone non-latin answer is the odd one out
                scriptScore = candidate.script.isNative ? 0 : 1
            }
            let syncScore = candidate.lyrics.sync.rawValue
            let duetScore = candidate.lyrics.hasDuet ? 2 : (candidate.lyrics.hasVoiceTags ? 1 : 0)
            let orderScore: Int = chineseSong && candidate.provider.isChinese ? providerCount * 2 - candidate.order : providerCount - candidate.order
            let weighted: Int = scriptScore * 10_000 + syncScore * 1000
            return weighted + duetScore * 100 + orderScore
        }
        return pool.max { score($0) < score($1) }
    }

    // the script there's clearly the most of, nil on a tie
    nonisolated private static func majority(_ scripts: [Script], minVotes: Int) -> Script? {
        let ranked = Dictionary(grouping: scripts.filter { $0 != .unknown }, by: { $0 }).mapValues(\.count).sorted { $0.value > $1.value }
        guard let top = ranked.first else { return nil }
        let runnerUp = ranked.count > 1 ? ranked[1].value : 0
        return top.value >= minVotes && top.value > runnerUp ? top.key : nil
    }
}

// the lyrics sources people turned on, in the order they like, saved like the android app saves it
nonisolated enum LyricsSettings {
    static let orderKey = "lyricsProviderOrder"
    static let disabledKey = "lyricsProvidersDisabled"

    static var order: [LyricsProvider] {
        let saved = (UserDefaults.standard.string(forKey: orderKey) ?? "")
            .split(separator: ",")
            .compactMap { LyricsProvider(rawValue: String($0).trimmingCharacters(in: .whitespaces)) }
        var seen = Set<LyricsProvider>()
        let unique = saved.filter { seen.insert($0).inserted }
        // a source added since the order was saved goes in at its default place, at the end
        return unique + LyricsProvider.defaultOrder.filter { !seen.contains($0) }
    }

    static var disabled: Set<LyricsProvider> {
        Set((UserDefaults.standard.stringArray(forKey: disabledKey) ?? []).compactMap(LyricsProvider.init(rawValue:)))
    }

    static var orderedEnabled: [LyricsProvider] {
        let off = disabled
        return order.filter { !off.contains($0) }
    }

    static func save(order: [LyricsProvider]) {
        UserDefaults.standard.set(order.map(\.rawValue).joined(separator: ","), forKey: orderKey)
    }

    static func setEnabled(_ provider: LyricsProvider, _ enabled: Bool) {
        var off = disabled
        if enabled { off.remove(provider) } else { off.insert(provider) }
        UserDefaults.standard.set(off.map(\.rawValue), forKey: disabledKey)
    }
}
