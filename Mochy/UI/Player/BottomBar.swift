import SwiftUI

// which of the concept's responsive bars fits the space we have
enum BarStyle {
    // controls, the song, and the extras in one pill, the sidebar does the navigation
    case classic
    // the classic pill with the tabs in their own pill beside it, for when the sidebar is gone
    case classicWithNav
    // the song and three controls, for narrow windows
    case compact
    // the compact pill and the tabs pill, for the narrowest windows without a sidebar
    case compactWithNav
}

struct BottomBar: View {
    let style: BarStyle

    var body: some View {
        HStack(spacing: 10) {
            switch style {
            case .classic:
                ClassicPlayerPill()
            case .classicWithNav:
                ClassicPlayerPill()
                NavPill()
            case .compact:
                CompactPlayerPill()
            case .compactWithNav:
                CompactPlayerPill()
                NavPill()
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: style)
    }
}

// shuffle, back, play, next, repeat | the song | lyrics, queue, volume
private struct ClassicPlayerPill: View {
    @Environment(PlayerModel.self) private var player
    @Environment(Router.self) private var router

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 2) {
                BarButton(systemImage: "shuffle", size: 28, iconSize: 11, isActive: player.isShuffled, help: "Shuffle") { player.toggleShuffle() }
                BarButton(systemImage: "backward.fill", size: 28, iconSize: 11, help: "Previous") { player.skipPrevious() }
                PlayPauseButton(size: 32, iconSize: 13)
                BarButton(systemImage: "forward.fill", size: 28, iconSize: 11, help: "Next") { player.skipNext() }
                BarButton(systemImage: player.repeatMode == .one ? "repeat.1" : "repeat", size: 28, iconSize: 11, isActive: player.repeatMode != .off, help: "Repeat") { player.cycleRepeat() }
            }
            NowPlayingChip(width: 210)
            HStack(spacing: 2) {
                BarButton(systemImage: "quote.bubble", size: 28, iconSize: 12, isActive: router.lyricsOpen, help: "Lyrics") { router.toggleLyrics() }
                QueueButton()
                VolumeButton()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 50)
        .glassPill()
        .disabled(player.current == nil)
    }
}

// the song and back, play, next, the concept's "type 1" bar
private struct CompactPlayerPill: View {
    @Environment(PlayerModel.self) private var player

    var body: some View {
        HStack(spacing: 4) {
            NowPlayingChip(width: 170)
            BarButton(systemImage: "backward.fill", size: 28, iconSize: 11, help: "Previous") { player.skipPrevious() }
            PlayPauseButton(size: 32, iconSize: 13)
            BarButton(systemImage: "forward.fill", size: 28, iconSize: 11, help: "Next") { player.skipNext() }
        }
        .padding(.horizontal, 8)
        .frame(height: 50)
        .glassPill()
    }
}

// the tabs as a pill, plus a way into the full player, for when the sidebar is hidden
struct NavPill: View {
    @Environment(Router.self) private var router

    var body: some View {
        HStack(spacing: 2) {
            navButton(.home, .home, .homeFilled, "Home")
            navButton(.search, .search, .search, "Search")
            navButton(.library, .library, .libraryFilled, "Library")
            BarButton(systemImage: "play.circle", size: 34, iconSize: 15, isActive: router.playerOpen, help: "Now playing") { router.togglePlayer() }
        }
        .padding(.horizontal, 7)
        .frame(height: 50)
        .glassPill()
    }

    private func navButton(_ tab: AppTab, _ icon: VectorIcon, _ filled: VectorIcon, _ title: LocalizedStringKey) -> some View {
        let selected = router.tab == tab && !router.playerOpen
        return Button {
            router.playerOpen = false
            router.select(tab)
        } label: {
            IconShape(icon: selected ? filled : icon)
                .fill(.white.opacity(selected ? 1 : 0.75))
                .frame(width: 15, height: 15)
                .frame(width: 34, height: 34)
                .background(Circle().fill(selected ? Theme.selected : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .help(title)
    }
}

// the cover and the song's name, with a thin line under it for how far in we are; a click opens the full player
struct NowPlayingChip: View {
    let width: CGFloat

    @Environment(PlayerModel.self) private var player
    @Environment(Router.self) private var router
    @State private var isHovered = false

    var body: some View {
        Button { router.togglePlayer() } label: {
            HStack(spacing: 9) {
                ZStack {
                    RemoteImage(url: player.current?.thumbnail, size: 36)
                    if player.isBuffering {
                        Color.black.opacity(0.45)
                        ProgressView().controlSize(.mini).tint(.white)
                    }
                }
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.current?.title ?? String(localized: "Nothing playing"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(player.current == nil ? Theme.secondaryText : .white)
                    Text(player.current?.artistNames ?? String(localized: "Pick a song to start"))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                    ProgressLine()
                        .frame(height: 2.5)
                        .padding(.top, 2)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 6)
            .frame(width: width, height: 42)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(isHovered ? Theme.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .onHover { isHovered = $0 }
        .help("Open the player")
    }
}

// how far into the song we are, redrawn twice a second on its own so the rest of the bar stays still
private struct ProgressLine: View {
    @Environment(PlayerModel.self) private var player

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let fraction = player.duration > 0 ? min(max(player.currentTime / player.duration, 0), 1) : 0
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule().fill(Color.white.opacity(0.85)).frame(width: geometry.size.width * fraction)
                }
            }
        }
    }
}

struct PlayPauseButton: View {
    var size: CGFloat = 32
    var iconSize: CGFloat = 13

    @Environment(PlayerModel.self) private var player
    @State private var isHovered = false

    var body: some View {
        Button { player.togglePlayPause() } label: {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(.black)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(isHovered ? 0.88 : 1)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .onHover { isHovered = $0 }
        .help(player.isPlaying ? "Pause" : "Play")
    }
}

private struct QueueButton: View {
    @Environment(Router.self) private var router

    var body: some View {
        BarButton(systemImage: "list.bullet", size: 28, iconSize: 12, isActive: router.playerOpen && router.queueOpen, help: "Up next") {
            if router.playerOpen && router.queueOpen {
                router.togglePlayer()
            } else {
                router.queueOpen = true
                if !router.playerOpen { router.togglePlayer() }
            }
        }
    }
}

// a speaker that opens a small slider, scrolling over it nudges the volume too
struct VolumeButton: View {
    @Environment(PlayerModel.self) private var player
    @State private var showsSlider = false

    var body: some View {
        @Bindable var player = player
        BarButton(systemImage: icon, size: 28, iconSize: 12, help: "Volume") { showsSlider.toggle() }
            .popover(isPresented: $showsSlider, arrowEdge: .top) {
                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill").font(.system(size: 10)).foregroundStyle(Theme.secondaryText)
                    Slider(value: $player.volume, in: 0...1)
                        .frame(width: 140)
                        .controlSize(.small)
                    Image(systemName: "speaker.wave.3.fill").font(.system(size: 10)).foregroundStyle(Theme.secondaryText)
                }
                .padding(12)
            }
    }

    private var icon: String {
        switch player.volume {
        case 0: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}
