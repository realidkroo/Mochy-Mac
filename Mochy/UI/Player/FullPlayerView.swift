import SwiftUI

// the full player, the concept's ipad page: the cover deck and the song on the left, the lyrics stage on the right, all over the cover's own colours
struct FullPlayerView: View {
    @Environment(PlayerModel.self) private var player
    @Environment(Router.self) private var router
    @Environment(WindowState.self) private var window
    @AppStorage(AppSettings.animatedBackgroundsKey) private var animated = true

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let coverSide = min(max(min(size.width * 0.3, size.height * 0.5), 200), 480)
            ZStack(alignment: .topTrailing) {
                ZStack {
                    AmbientBackdrop(palette: player.palette, animate: animated && window.isVisible)
                        .id(player.palette)
                        .transition(.opacity)
                }
                .animation(.easeInOut(duration: 0.9), value: player.palette)
                LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.22)], startPoint: .leading, endPoint: .trailing)

                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 20) {
                        CoverDeck(side: coverSide)
                        SongInfo(width: coverSide)
                        SeekBar()
                            .frame(width: coverSide)
                        VolumeRow()
                            .frame(width: coverSide)
                    }
                    .frame(width: max(size.width * 0.44, coverSide + 60))
                    .frame(maxHeight: .infinity)

                    ZStack(alignment: .bottomTrailing) {
                        Group {
                            if router.queueOpen {
                                QueuePanel()
                                    .padding(.top, 70)
                                    .padding(.bottom, 110)
                            } else {
                                LyricsView(style: .stage)
                                    .padding(.top, 40)
                                    .padding(.bottom, 80)
                            }
                        }
                        .transition(.opacity)
                        TransportButtons()
                            .padding(.trailing, 36)
                            .padding(.bottom, 34)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(.easeInOut(duration: 0.25), value: router.queueOpen)
                }

                HStack(spacing: 8) {
                    if player.current != nil, !router.queueOpen { LyricsSourceMenu() }
                    BarButton(systemImage: router.queueOpen ? "quote.bubble" : "list.bullet", size: 32, iconSize: 12, help: router.queueOpen ? "Show lyrics" : "Up next") {
                        router.queueOpen.toggle()
                    }
                    .glassPill(tint: 0.25)
                    BarButton(systemImage: "chevron.down", size: 32, iconSize: 12, help: "Close the player") { router.togglePlayer() }
                        .glassPill(tint: 0.25)
                }
                .padding(.top, 14)
                .padding(.trailing, 18)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
    }
}

// the cover's colours drifting under everything, drawn at a quarter size since they're soft pools anyway
struct AmbientBackdrop: View {
    let palette: CoverPalette
    let animate: Bool

    var body: some View {
        GeometryReader { geometry in
            let small = CGSize(width: max(geometry.size.width / 4, 1), height: max(geometry.size.height / 4, 1))
            // the drift is slow, so 30 steps a second look like 120 and cost a quarter as much
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animate)) { context in
                let time = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 100)
                Rectangle()
                    .frame(width: small.width, height: small.height)
                    .colorEffect(ShaderLibrary.ambient(
                        .float2(small), .float(time),
                        .color(palette.tone(0)), .color(palette.tone(1)), .color(palette.tone(2)), .color(palette.tone(3))
                    ))
                    .scaleEffect(4, anchor: .topLeading)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            }
        }
        .allowsHitTesting(false)
    }
}

// the playing cover in front and the next one peeking out behind it; a click on the back card skips to it
private struct CoverDeck: View {
    let side: CGFloat

    @Environment(PlayerModel.self) private var player

    var body: some View {
        let cards: [(role: Int, song: SongItem)] = [player.next.map { (1, $0) }, player.current.map { (0, $0) }].compactMap { $0 }
        ZStack(alignment: .leading) {
            ForEach(cards, id: \.song.id) { role, song in
                let front = role == 0
                RemoteImage(url: song.thumbnail, size: side)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: side * 0.07, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: side * 0.07, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 0.75))
                    .shadow(color: .black.opacity(front ? 0.4 : 0.2), radius: front ? 30 : 14, y: front ? 18 : 8)
                    .brightness(front ? 0 : -0.12)
                    .scaleEffect(front ? (player.isPlaying ? 1 : 0.95) : 0.88, anchor: front ? .center : .trailing)
                    .offset(x: front ? 0 : side * 0.085)
                    .zIndex(front ? 1 : 0)
                    .onTapGesture { if !front { player.skipNext() } }
                    .help(front ? "" : String(localized: "Up next: \(song.title)"))
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(x: side * 0.12)),
                        removal: .opacity.combined(with: .offset(x: -side * 0.25)).combined(with: .scale(scale: 0.92))
                    ))
            }
        }
        .frame(width: side * 1.1, height: side, alignment: .leading)
        .animation(.spring(response: 0.55, dampingFraction: 0.8), value: player.current?.id)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: player.isPlaying)
    }
}

// the title and artist with a heart and a menu beside them, the concept's two little dots
private struct SongInfo: View {
    let width: CGFloat

    @Environment(PlayerModel.self) private var player
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(player.current?.title ?? String(localized: "Nothing playing"))
                    .font(.system(size: 21, weight: .bold))
                    .tracking(-0.3)
                    .lineLimit(1)
                Button {
                    if let id = player.current?.artists.first(where: { $0.id != nil })?.id { router.push(.artist(id)) }
                } label: {
                    Text(player.current?.artistNames ?? " ")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            if let song = player.current {
                Button { library.toggleLike(song) } label: {
                    Image(systemName: library.isLiked(song.id) ? "heart.fill" : "heart")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(library.isLiked(song.id) ? Color.pink : .white)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(.white.opacity(0.14)))
                }
                .buttonStyle(PressableStyle(scale: 0.88))
                .help("Like")
                Menu {
                    ItemMenu(item: .song(song))
                    Divider()
                    Button(player.isShuffled ? "Turn Shuffle Off" : "Shuffle", systemImage: "shuffle") { player.toggleShuffle() }
                    Button("Repeat: \(repeatLabel)", systemImage: "repeat") { player.cycleRepeat() }
                    if let stream = player.stream {
                        Divider()
                        Text("Streaming \(stream.formatLabel)")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(.white.opacity(0.14)))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .frame(width: width)
    }

    private var repeatLabel: String {
        switch player.repeatMode {
        case .off: String(localized: "Off")
        case .all: String(localized: "All")
        case .one: String(localized: "One")
        }
    }
}

// a thin bar that thickens under the pointer, drag or click anywhere on it to jump
struct SeekBar: View {
    @Environment(PlayerModel.self) private var player
    @State private var dragFraction: Double?
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 6) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !player.isPlaying || dragFraction != nil)) { _ in
                let fraction = dragFraction ?? (player.duration > 0 ? clamp01(player.currentTime / player.duration) : 0)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.2))
                        Capsule().fill(.white.opacity(0.92)).frame(width: max(geometry.size.width * fraction, 0))
                    }
                    .frame(height: isHovered || dragFraction != nil ? 8 : 5)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in dragFraction = clamp01(value.location.x / max(geometry.size.width, 1)) }
                        .onEnded { value in
                            let target = clamp01(value.location.x / max(geometry.size.width, 1))
                            player.seek(to: target * player.duration)
                            dragFraction = nil
                        })
                }
                .frame(height: 14)
            }
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                let elapsed = dragFraction.map { $0 * player.duration } ?? player.currentTime
                HStack {
                    Text(elapsed.clock)
                    Spacer()
                    Text("-" + max(player.duration - elapsed, 0).clock)
                }
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
            }
        }
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
    }
}

private struct VolumeRow: View {
    @Environment(PlayerModel.self) private var player

    var body: some View {
        @Bindable var player = player
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill").font(.system(size: 10))
            Slider(value: $player.volume, in: 0...1)
                .controlSize(.mini)
                .tint(.white)
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 10))
        }
        .foregroundStyle(.white.opacity(0.55))
    }
}

// back, play and next as three soft squares in the bottom right, like the concept
private struct TransportButtons: View {
    @Environment(PlayerModel.self) private var player

    var body: some View {
        HStack(spacing: 12) {
            square("backward.fill", help: "Previous") { player.skipPrevious() }
            square(player.isPlaying ? "pause.fill" : "play.fill", help: player.isPlaying ? "Pause" : "Play", prominent: true) { player.togglePlayPause() }
            square("forward.fill", help: "Next") { player.skipNext() }
        }
    }

    private func square(_ icon: String, help: LocalizedStringKey, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        TransportSquare(icon: icon, prominent: prominent, action: action).help(help)
    }
}

private struct TransportSquare: View {
    let icon: String
    let prominent: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(prominent ? Color.black : .white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 58, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(prominent ? Color.white.opacity(isHovered ? 0.85 : 0.95) : Color.white.opacity(isHovered ? 0.3 : 0.2))
                )
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .onHover { isHovered = $0 }
    }
}

// what plays next, drag to reorder, right-click to remove
private struct QueuePanel: View {
    @Environment(PlayerModel.self) private var player

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                Text("Up next").font(.system(size: 22, weight: .bold))
                if let title = player.queueTitle {
                    Text(title).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 30)
            let start = player.index + 1
            List {
                ForEach(Array(player.upNext.enumerated()), id: \.offset) { offset, song in
                    QueueRow(song: song) { player.jump(to: start + offset) }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .contextMenu {
                            Button("Remove from Queue") { player.removeFromQueue(at: IndexSet(integer: start + offset)) }
                            Button("Play Next") {
                                player.removeFromQueue(at: IndexSet(integer: start + offset))
                                player.playNext(song)
                            }
                        }
                }
                .onMove { source, destination in
                    player.moveInQueue(from: IndexSet(source.map { $0 + start }), to: destination + start)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 20)
        }
    }
}

private struct QueueRow: View {
    let song: SongItem
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: song.thumbnail, size: 40)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.system(size: 13, weight: .semibold))
                Text(song.artistNames).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.6))
            }
            .lineLimit(1)
            Spacer()
            Text(song.duration.map { TimeInterval($0).clock } ?? "")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(isHovered ? 0.1 : 0)))
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: action)
        .onHover { isHovered = $0 }
    }
}
