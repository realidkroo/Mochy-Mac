import AppKit
import SwiftUI

// how big and where: the side panel is compact, the full player's stage is big and roomy
struct LyricsMetrics {
    let fontSize: CGFloat
    let rowSpacing: CGFloat
    let anchor: CGFloat
    let padding: CGFloat
    let wordSpacing: CGFloat
    let lineGap: CGFloat

    var backingSize: CGFloat { (fontSize * 0.6).rounded() }
    var gapHeight: CGFloat { fontSize * 0.9 }

    static func make(_ style: LyricsView.Style, width: CGFloat, scale: Double) -> LyricsMetrics {
        let size: CGFloat = switch style {
        case .panel: min(max(width / 13.5, 20), 27)
        case .stage: min(max(width / 15, 26), 42)
        }
        let font = (size * CGFloat(scale)).rounded()
        return LyricsMetrics(
            fontSize: font,
            rowSpacing: style == .stage ? font * 0.62 : font * 0.55,
            anchor: style == .stage ? 0.3 : 0.26,
            padding: style == .stage ? 30 : 20,
            wordSpacing: font * 0.26,
            lineGap: font * 0.1
        )
    }
}

struct LyricsView: View {
    enum Style { case panel, stage }
    let style: Style

    @Environment(PlayerModel.self) private var player

    var body: some View {
        Group {
            switch player.lyricsState {
            case .loading, .idle:
                LyricsLoading(style: style)
            case .missing:
                NoLyrics(style: style)
            case .found:
                if let lyrics = player.lyrics, let song = player.current {
                    if lyrics.isSynced {
                        // a fresh view for every new set of lyrics, so nothing measured for the last song lingers
                        SyncedLyricsView(lyrics: lyrics, style: style)
                            .id(song.id + lyrics.provider.rawValue + String(lyrics.lines.count))
                    } else {
                        PlainLyricsView(lyrics: lyrics, style: style)
                    }
                } else {
                    NoLyrics(style: style)
                }
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: player.lyricsState)
    }
}

// one row of the list: a sung line, or the breathing dots over an instrumental gap
struct LyricRowModel: Identifiable {
    enum Kind {
        case line(LyricLine)
        case gap
    }

    let id: Int
    let kind: Kind
    let start: Double
    let end: Double
    // how early the row lights up, so the eye is already there when the singing starts
    let lead: Double

    static func build(_ lyrics: Lyrics) -> [LyricRowModel] {
        var rows: [LyricRowModel] = []
        let lines = lyrics.lines
        guard let first = lines.first else { return [] }
        if first.time > 4.5 {
            rows.append(LyricRowModel(id: 0, kind: .gap, start: 0, end: first.time - 0.25, lead: 0))
        }
        for (index, line) in lines.enumerated() {
            let next = lines.indices.contains(index + 1) ? lines[index + 1].time : nil
            rows.append(LyricRowModel(id: rows.count, kind: .line(line), start: line.time, end: line.end ?? next ?? line.time + 4, lead: 0.25))
            if let next, let end = line.end, next - end > 5 {
                rows.append(LyricRowModel(id: rows.count, kind: .gap, start: end + 0.35, end: next - 0.25, lead: 0))
            }
        }
        return rows
    }

    static func active(in rows: [LyricRowModel], at time: Double) -> Int {
        var result = -1
        for row in rows {
            guard row.start - row.lead <= time else { break }
            result = row.id
        }
        return result
    }
}

// scrolling the lyrics by hand: they stop following the song for a moment, unblur, then glide back
@Observable
final class LyricsScrollState {
    private(set) var offset: CGFloat = 0
    private(set) var isScrolling = false
    @ObservationIgnored var hovering = false
    @ObservationIgnored var range: ClosedRange<CGFloat> = -100_000...100_000
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var settleTask: Task<Void, Never>?

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.hovering else { return event }
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 14
            self.scroll(by: delta)
            return nil
        }
    }

    func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        settleTask?.cancel()
    }

    private func scroll(by delta: CGFloat) {
        if !isScrolling {
            withAnimation(.easeOut(duration: 0.25)) { isScrolling = true }
        }
        offset = min(max(offset + delta, range.lowerBound), range.upperBound)
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            self?.release()
        }
    }

    func release() {
        settleTask?.cancel()
        withAnimation(.spring(response: 0.7, dampingFraction: 0.86)) {
            offset = 0
            isScrolling = false
        }
    }
}

// synced lyrics: every line placed by hand so each one can spring to its spot a beat after the one above, like a wave
struct SyncedLyricsView: View {
    let lyrics: Lyrics
    let style: LyricsView.Style

    @Environment(PlayerModel.self) private var player
    @AppStorage(AppSettings.lyricsBlurKey) private var blurOn = true
    @AppStorage(AppSettings.lyricsGlowKey) private var glowOn = true
    @AppStorage(AppSettings.lyricsSizeKey) private var sizeScale = 1.0
    @State private var rows: [LyricRowModel]
    @State private var active = -1
    @State private var heights: [Int: CGFloat] = [:]
    @State private var scroll = LyricsScrollState()

    init(lyrics: Lyrics, style: LyricsView.Style) {
        self.lyrics = lyrics
        self.style = style
        _rows = State(initialValue: LyricRowModel.build(lyrics))
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = LyricsMetrics.make(style, width: geometry.size.width, scale: sizeScale)
            let contentWidth = max(geometry.size.width - metrics.padding * 2, 100)
            let viewport = geometry.size.height
            let tops = rowTops(metrics)
            let focus = max(active, 0)
            let target = (tops[focus] ?? 0) - viewport * metrics.anchor
            let total = (tops[rows.count - 1] ?? 0) + (heights[rows.count - 1] ?? 0)

            ZStack(alignment: .topLeading) {
                ForEach(rows) { row in
                    let y = (tops[row.id] ?? 0) - target + scroll.offset
                    // rows well outside the view aren't drawn at all, a blurred line costs a pass on every frame it moves
                    if y > -viewport * 0.7, y < viewport * 1.6 {
                        LyricRowView(
                            row: row,
                            distance: row.id - focus,
                            isLive: isLive(row),
                            metrics: metrics,
                            width: contentWidth,
                            blurOn: blurOn && !scroll.isScrolling,
                            glowOn: glowOn,
                            isScrolling: scroll.isScrolling,
                            onTap: { time in
                                player.seek(to: time)
                                scroll.release()
                            }
                        )
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[row.id] = $0 }
                        .offset(x: metrics.padding, y: y)
                        .animation(.spring(response: 0.6, dampingFraction: 0.88).delay(delay(for: row)), value: active)
                        .transition(.identity)
                    }
                }
            }
            .frame(width: geometry.size.width, height: viewport, alignment: .topLeading)
            .clipped()
            .mask(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.1),
                    .init(color: .black, location: 0.8),
                    .init(color: .clear, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            )
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                if case .active = phase { scroll.hovering = true } else { scroll.hovering = false }
            }
            .onChange(of: total + target, initial: true) {
                // you can scroll back to the first line and on to the last, not into empty space
                scroll.range = min(target - total + viewport * 0.3, 0)...max(target + viewport * 0.2, 0)
            }
        }
        .onAppear { scroll.install() }
        .onDisappear { scroll.remove() }
        .task {
            active = LyricRowModel.active(in: rows, at: player.currentTime)
            // a cheap poll is enough to notice a new line, the words themselves move on the frame clock
            while !Task.isCancelled {
                let now = LyricRowModel.active(in: rows, at: player.currentTime)
                if now != active { active = now }
                try? await Task.sleep(for: .milliseconds(player.isPlaying ? 33 : 160))
            }
        }
    }

    private func rowTops(_ metrics: LyricsMetrics) -> [Int: CGFloat] {
        var tops: [Int: CGFloat] = [:]
        var y: CGFloat = 0
        for row in rows {
            tops[row.id] = y
            y += (heights[row.id] ?? estimatedHeight(row, metrics)) + metrics.rowSpacing
        }
        return tops
    }

    private func estimatedHeight(_ row: LyricRowModel, _ metrics: LyricsMetrics) -> CGFloat {
        if case .gap = row.kind { return metrics.gapHeight }
        return metrics.fontSize * 1.35
    }

    // the line being sung and the one just before it run on the frame clock, the rest are still pictures
    private func isLive(_ row: LyricRowModel) -> Bool {
        row.id == active || (row.id == active - 1 && player.currentTime < row.end + 1)
    }

    // lines below the singing one follow a little later each, which is what makes the list ripple
    private func delay(for row: LyricRowModel) -> Double {
        let after = row.id - active + 1
        return after <= 0 ? 0 : min(Double(after) * 0.035, 0.25)
    }
}

// lyrics with no timing: just the words, scrollable
struct PlainLyricsView: View {
    let lyrics: Lyrics
    let style: LyricsView.Style

    @AppStorage(AppSettings.lyricsSizeKey) private var sizeScale = 1.0

    var body: some View {
        GeometryReader { geometry in
            let metrics = LyricsMetrics.make(style, width: geometry.size.width, scale: sizeScale)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: metrics.fontSize * 0.32) {
                    Text("These lyrics aren't synced")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.tertiaryText)
                        .padding(.bottom, 8)
                    ForEach(lyrics.lines) { line in
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.system(size: metrics.fontSize * 0.8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, metrics.padding)
                .padding(.vertical, geometry.size.height * 0.12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.08), .init(color: .black, location: 0.85), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
        }
    }
}

// soft bars breathing in place of lines while the sources are asked
private struct LyricsLoading: View {
    let style: LyricsView.Style
    @State private var pulse = false

    var body: some View {
        GeometryReader { geometry in
            let metrics = LyricsMetrics.make(style, width: geometry.size.width, scale: 1)
            VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                ForEach(Array([0.82, 0.64, 0.9, 0.5, 0.72].enumerated()), id: \.offset) { index, fraction in
                    RoundedRectangle(cornerRadius: metrics.fontSize * 0.25, style: .continuous)
                        .fill(.white.opacity(pulse ? 0.14 : 0.06))
                        .frame(width: (geometry.size.width - metrics.padding * 2) * fraction, height: metrics.fontSize * 0.8)
                        .animation(.easeInOut(duration: 0.9).repeatForever().delay(Double(index) * 0.12), value: pulse)
                }
            }
            .padding(.horizontal, metrics.padding)
            .padding(.top, geometry.size.height * metrics.anchor)
        }
        .onAppear { pulse = true }
    }
}

private struct NoLyrics: View {
    let style: LyricsView.Style
    @Environment(PlayerModel.self) private var player

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "quote.bubble")
                .font(.system(size: style == .stage ? 34 : 26, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
            Text(player.current == nil ? "Play something to see its lyrics" : "No lyrics for this song")
                .font(.system(size: style == .stage ? 20 : 15, weight: .semibold))
            if player.current != nil {
                Text("None of the lyrics sources had it. You can ask them again.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                CapsuleButton(title: "Search again", systemImage: "arrow.clockwise") { player.refetchLyrics() }
                    .padding(.top, 4)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// which source the lyrics came from, and a way to pick another one
struct LyricsSourceMenu: View {
    @Environment(PlayerModel.self) private var player

    var body: some View {
        Menu {
            if let lyrics = player.lyrics {
                Text("Showing \(lyrics.provider.displayName) · \(lyrics.sync.label)")
            }
            Section("Sources that have this song") {
                ForEach(player.lyricsCandidates.sorted { $0.lyrics.sync.rawValue > $1.lyrics.sync.rawValue }) { candidate in
                    Button {
                        player.choose(candidate)
                    } label: {
                        if candidate.provider == player.lyrics?.provider {
                            Label("\(candidate.provider.displayName) · \(candidate.lyrics.sync.label)", systemImage: "checkmark")
                        } else {
                            Text("\(candidate.provider.displayName) · \(candidate.lyrics.sync.label)")
                        }
                    }
                }
                if player.lyricsCandidates.isEmpty {
                    Text("None yet")
                }
            }
            Divider()
            Button(player.isLoadingAllLyrics ? "Asking every source…" : "Ask Every Source") { player.loadAllLyrics() }
                .disabled(player.isLoadingAllLyrics || player.current == nil)
            Button("Search Again") { player.refetchLyrics() }
                .disabled(player.current == nil)
        } label: {
            HStack(spacing: 5) {
                if player.isLoadingAllLyrics { ProgressView().controlSize(.mini) }
                Text(player.lyrics?.provider.displayName ?? String(localized: "Source"))
                    .font(.system(size: 11, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(Color.white.opacity(0.1)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Lyrics source")
    }
}
