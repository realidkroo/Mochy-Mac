import SwiftUI

// one row: how bright, how blurred and how big it is depends only on how far it is from the line being sung
struct LyricRowView: View {
    let row: LyricRowModel
    let distance: Int
    let isLive: Bool
    let metrics: LyricsMetrics
    let width: CGFloat
    let blurOn: Bool
    let glowOn: Bool
    let isScrolling: Bool
    let onTap: (Double) -> Void

    @State private var isHovered = false

    var body: some View {
        switch row.kind {
        case .gap:
            GapDots(start: row.start, end: row.end, isActive: distance == 0, metrics: metrics)
                .frame(width: width, height: metrics.gapHeight, alignment: .leading)
        case .line(let line):
            Group {
                if line.words.isEmpty {
                    PlainLine(line: line, isActive: distance == 0, metrics: metrics, glowOn: glowOn)
                } else {
                    WordLine(line: line, mode: isLive ? .live : (distance < 0 ? .sung : .waiting), metrics: metrics, glowOn: glowOn)
                }
            }
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(isHovered ? 0.07 : 0)))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onTapGesture { onTap(line.time) }
            .onHover { isHovered = $0 }
            .padding(.horizontal, -10)
            .scaleEffect(distance == 0 ? 1 : 0.97, anchor: .leading)
            .opacity(opacity)
            .blur(radius: blur)
        }
    }

    private var opacity: Double {
        if distance == 0 { return 1 }
        if isScrolling { return 0.55 }
        return distance > 0 ? max(0.5 - Double(distance - 1) * 0.04, 0.36) : 0.28
    }

    // blur grows with the distance, which keeps the eye on the line being sung
    private var blur: CGFloat {
        guard blurOn, distance != 0 else { return 0 }
        let step = metrics.fontSize / 26
        return min(CGFloat(abs(distance)) * 1.1 * step, 4.4 * step)
    }
}

// a line timed only as a whole: it lights up and gets a soft glow while it's the one being sung
private struct PlainLine: View {
    let line: LyricLine
    let isActive: Bool
    let metrics: LyricsMetrics
    let glowOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(line.text)
                .font(.system(size: metrics.fontSize, weight: .bold))
                .tracking(-metrics.fontSize * 0.012)
                .shadow(color: .white.opacity(isActive && glowOn ? 0.35 : 0), radius: metrics.fontSize * 0.3)
            if let backing = line.backing {
                Text(backing.text)
                    .font(.system(size: metrics.backingSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// a word-timed line: each word fills with light as it's sung, climbs into place, and glows on held notes
struct WordLine: View {
    enum Mode { case live, sung, waiting }

    let line: LyricLine
    let mode: Mode
    let metrics: LyricsMetrics
    let glowOn: Bool

    @Environment(PlayerModel.self) private var player

    // always the same views whatever the mode, swapping them made swiftui fade a ghost copy out at the old spot
    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: mode != .live || !player.isPlaying)) { _ in
            let time: Double = switch mode {
            case .live: player.currentTime
            case .sung: .greatestFiniteMagnitude
            case .waiting: -1
            }
            content(time: time, live: mode == .live)
        }
    }

    private func content(time: Double, live: Bool) -> some View {
        // the words settle to their waiting spot as the line comes up, rather than snapping there
        let activation = live ? smoothstep((time - line.time + 0.4) / 0.4) : 0
        return VStack(alignment: .leading, spacing: metrics.lineGap * 3) {
            WordFlow(alignment: .leading, spacing: metrics.wordSpacing, lineSpacing: metrics.lineGap) {
                ForEach(Array(line.words.enumerated()), id: \.offset) { _, word in
                    SungWord(word: word, time: time, fontSize: metrics.fontSize, weight: .bold, activation: activation, glowOn: glowOn, live: live)
                        .flowSpaceAfter(word.spaceAfter)
                }
            }
            if let backing = line.backing {
                if backing.words.isEmpty {
                    Text(backing.text)
                        .font(.system(size: metrics.backingSize, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))
                } else {
                    WordFlow(alignment: .leading, spacing: metrics.wordSpacing * 0.7, lineSpacing: metrics.lineGap) {
                        ForEach(Array(backing.words.enumerated()), id: \.offset) { _, word in
                            SungWord(word: word, time: time, fontSize: metrics.backingSize, weight: .semibold, activation: activation, glowOn: glowOn, live: live, dimmed: true)
                                .flowSpaceAfter(word.spaceAfter)
                        }
                    }
                }
            }
        }
    }
}

// one word: a dim copy, a bright copy revealed by a soft-edged sweep, the rise shader while it's being sung and the bloom shader while it glows
private struct SungWord: View {
    let word: LyricWord
    let time: Double
    let fontSize: CGFloat
    let weight: Font.Weight
    let activation: Double
    let glowOn: Bool
    let live: Bool
    var dimmed = false

    var body: some View {
        let font = Font.system(size: fontSize, weight: weight)
        let tracking = -fontSize * 0.012
        let duration = max(word.end - word.start, 0.05)
        let progress = live ? clamp01((time - word.start) / duration) : 1
        // a long note glows harder and swells a little, like the android lyrics
        let held = clamp01((duration - 0.85) / 1.3)
        let glowIn = smoothstep((time - word.start + 0.05) / 0.25)
        let glowOut = 1 - smoothstep((time - word.end) / 0.7)
        let glow = live && glowOn ? glowIn * glowOut * (0.5 + 0.95 * held) * (dimmed ? 0.6 : 1) : 0
        let swell = live ? held * glowIn * (1 - smoothstep((time - word.end + 0.05) / 0.45)) : 0
        // the glow keeps travelling past the word's end at the same speed, so it slides off instead of switching off
        let head = time < word.end ? progress : 1 + (time - word.end) / max(duration, 0.3)
        // a small dip for words still to come, big enough to feel them rise but not enough to break the line
        let drop = live ? fontSize * 0.035 * activation : 0
        let pad = (fontSize * 0.34).rounded(.up)
        let soft = min(0.45, 1.1 / Double(max(word.text.count, 1)))
        let restingAlpha = dimmed ? 0.7 : 1.0
        let unsungAlpha = dimmed ? 0.32 : 0.42

        Text(word.text)
            .font(font)
            .tracking(tracking)
            .foregroundStyle(.white.opacity(live ? unsungAlpha : restingAlpha))
            .overlay {
                Text(word.text)
                    .font(font)
                    .tracking(tracking)
                    .foregroundStyle(.white.opacity(dimmed ? 0.8 : 1))
                    .mask(SweepMask(progress: progress, soft: soft))
                    .opacity(live ? 1 : 0)
            }
            .padding(pad)
            .distortionEffect(
                ShaderLibrary.lyricRise(.boundingRect, .float(pad), .float(progress), .float(drop), .float(fontSize * 1.1)),
                maxSampleOffset: CGSize(width: 0, height: drop + 1),
                isEnabled: progress > 0 && progress < 1 && drop > 0.05
            )
            .layerEffect(
                ShaderLibrary.lyricBloom(.boundingRect, .float(pad), .float(head), .float(glow), .float(fontSize * 0.1), .float(fontSize * 0.7), .float(fontSize * 2.2)),
                maxSampleOffset: CGSize(width: pad, height: pad),
                isEnabled: glow > 0.01
            )
            .padding(-pad)
            .offset(y: progress <= 0 ? drop : 0)
            .scaleEffect(1 + 0.06 * swell, anchor: .bottomLeading)
            .offset(y: -fontSize * 0.05 * swell)
    }
}

// the reveal for the bright copy: solid up to the sweep, a soft edge, then nothing
private struct SweepMask: View {
    let progress: Double
    let soft: Double

    var body: some View {
        let centre = -soft + (1 + soft * 2) * progress
        let low = min(max(centre - soft, 0), 1)
        let high = min(max(centre + soft, low), 1)
        LinearGradient(stops: [
            .init(color: .black, location: 0),
            .init(color: .black, location: low),
            .init(color: .clear, location: high),
            .init(color: .clear, location: 1),
        ], startPoint: .leading, endPoint: .trailing)
    }
}

// three dots that fill one by one across an instrumental gap, breathing, then shrink away right before the singing comes back
private struct GapDots: View {
    let start: Double
    let end: Double
    let isActive: Bool
    let metrics: LyricsMetrics

    @Environment(PlayerModel.self) private var player

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !isActive || !player.isPlaying)) { _ in
            dots(time: isActive ? player.currentTime : start)
                .opacity(isActive ? 1 : 0)
        }
    }

    private func dots(time: Double) -> some View {
        let progress = clamp01((time - start) / max(end - start, 0.1))
        let breath = 1 + 0.07 * sin(time * 2.8)
        let outro = 1 - smoothstep((time - (end - 0.5)) / 0.5)
        let size = metrics.fontSize * 0.36
        return HStack(spacing: size * 0.7) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.white)
                    .frame(width: size, height: size)
                    .opacity(0.22 + 0.78 * clamp01(progress * 3 - Double(index)))
            }
        }
        .scaleEffect(breath * outro, anchor: .leading)
        .opacity(outro)
        .frame(maxHeight: .infinity)
    }
}

func clamp01(_ value: Double) -> Double { min(max(value, 0), 1) }

// eased 0 to 1, flat at both ends
func smoothstep(_ value: Double) -> Double {
    let t = clamp01(value)
    return t * t * (3 - 2 * t)
}
