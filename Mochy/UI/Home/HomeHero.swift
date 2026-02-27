import SwiftUI

// the big top of home: this month's recap over your most played cover, slowly swimming, with your top songs stacked on the right
struct HomeHero: View {
    let recap: MonthRecap?
    let fallback: (item: YTItem, label: String)?

    @Environment(PlayerModel.self) private var player
    @Environment(Router.self) private var router
    @Environment(WindowState.self) private var window
    @Environment(\.isPageVisible) private var isPageVisible
    @AppStorage(AppSettings.animatedBackgroundsKey) private var animated = true

    private var hasRecap: Bool { recap.map { !$0.isEmpty } ?? false }

    private var covers: [String] {
        if let recap, !recap.isEmpty { return recap.topSongs.prefix(3).map(\.song.thumbnail) }
        if let thumbnail = fallback?.item.thumbnail { return [thumbnail] }
        return []
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                SwimmingCover(url: covers.first, animate: animated && isPageVisible && window.isVisible && !router.playerOpen)
                    .frame(width: size.width, height: size.height)

                LinearGradient(stops: [
                    .init(color: .black.opacity(0.35), location: 0),
                    .init(color: .clear, location: 0.25),
                    .init(color: .black.opacity(0.55), location: 0.62),
                    .init(color: .black, location: 1),
                ], startPoint: .top, endPoint: .bottom)

                if !covers.isEmpty {
                    CardStack(covers: covers, side: min(size.height * 0.4, 210)) { playTop() }
                        .position(x: size.width * 0.66, y: size.height * 0.38)
                }

                caption
                    .frame(maxWidth: size.width * 0.55, alignment: .leading)
                    .padding(.leading, Theme.gutter + 6)
                    .frame(width: size.width, height: size.height * 0.84, alignment: .bottomLeading)
            }
            .clipped()
        }
    }

    @ViewBuilder
    private var caption: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Rectangle().fill(.white.opacity(0.5)).frame(width: 40, height: 1)
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(2.4)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.leading, -(Theme.gutter + 6))
            .padding(.bottom, 14)

            if hasRecap {
                HStack(alignment: .top, spacing: 8) {
                    Text("See this")
                    Text(yearMark)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.top, 7)
                }
                Text("month recap!")
            } else {
                Text(fallback?.item.title ?? String(localized: "Your music, all in one place"))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }

            HStack(spacing: 10) {
                if hasRecap {
                    CapsuleButton(title: "View", systemImage: "arrow.right") { router.push(.recap) }
                    if let recap {
                        Text("\(recap.plays) plays · \(recap.minutes) minutes")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                } else if let item = fallback?.item {
                    CapsuleButton(title: item.song == nil ? "View" : "Play", systemImage: "arrow.right") {
                        if let song = item.song { player.play(song) } else { router.open(item) }
                    }
                }
            }
            .padding(.top, 18)
        }
        .font(.system(size: 42, weight: .bold))
        .tracking(-1)
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }

    private var label: String {
        if hasRecap { return Date.now.formatted(.dateTime.month(.wide)).uppercased() }
        return (fallback?.label ?? String(localized: "Welcome")).uppercased()
    }

    // "’26", the year as the concept writes it next to the title
    private var yearMark: String {
        "’" + String(Calendar.current.component(.year, from: .now) % 100)
    }

    private func playTop() {
        if let recap, !recap.isEmpty {
            player.play(recap.topSongs.map(\.song), title: String(localized: "Your top songs this month"))
        } else if let item = fallback?.item {
            if let song = item.song { player.play(song) } else { router.open(item) }
        }
    }
}

// the cover blown up, softened and warped by the shader on a slow loop, standing in for the concept's landscape
struct SwimmingCover: View {
    let url: String?
    let animate: Bool

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animate)) { context in
                let time = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
                RemoteImage(url: url, size: 180)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .blur(radius: 14, opaque: true)
                    .saturation(1.2)
                    .layerEffect(
                        ShaderLibrary.coverWarp(.float2(geometry.size), .float(time), .float(1.25)),
                        maxSampleOffset: .zero
                    )
            }
        }
    }
}

// your top three covers fanned out, front one first; the bottom melts into a progressive blur like the concept
private struct CardStack: View {
    let covers: [String]
    let side: CGFloat
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        let step = side * (isHovered ? 0.26 : 0.2)
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                ForEach(Array(covers.enumerated().reversed()), id: \.offset) { index, url in
                    let depth = CGFloat(covers.count - 1 - index)
                    RemoteImage(url: url, size: side)
                        .frame(width: side, height: side)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.75))
                        .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
                        .brightness(index == 0 ? 0 : -0.08 * Double(index))
                        .offset(x: depth * step, y: depth * step * 0.45)
                }
            }
            .frame(width: side + step * CGFloat(covers.count - 1), height: side + step * 0.45 * CGFloat(covers.count - 1), alignment: .topLeading)
            .padding(20)
            .layerEffect(
                ShaderLibrary.progressiveBlur(.boundingRect, .float(16), .float(0.5), .float(1)),
                maxSampleOffset: CGSize(width: 16, height: 16)
            )
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.62), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: isHovered)
        .help("Play your top songs")
    }
}
