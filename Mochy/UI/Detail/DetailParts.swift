import SwiftUI

// the shared top of album and playlist pages: the cover on the left, its name and play / shuffle on the right
struct CollectionHeader: View {
    let thumbnail: String?
    let kind: LocalizedStringKey
    let title: String
    let subtitle: String?
    let detail: String?
    var onSubtitleTap: (() -> Void)? = nil
    var gradientCover = false
    let onPlay: () -> Void
    let onShuffle: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 26) {
            Group {
                if gradientCover {
                    LinearGradient(colors: [Color(red: 0.98, green: 0.36, blue: 0.5), Color(red: 0.45, green: 0.28, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay(Image(systemName: "heart.fill").font(.system(size: 64)).foregroundStyle(.white))
                } else {
                    RemoteImage(url: thumbnail, size: 220)
                }
            }
            .frame(width: 210, height: 210)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 26, y: 14)

            VStack(alignment: .leading, spacing: 8) {
                Text(kind)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.6)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.secondaryText)
                Text(title)
                    .font(.system(size: 36, weight: .bold))
                    .tracking(-0.8)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                if let subtitle {
                    Button(subtitle) { onSubtitleTap?() }
                        .buttonStyle(.plain)
                        .font(.system(size: 14, weight: .semibold))
                        .disabled(onSubtitleTap == nil)
                }
                if let detail {
                    Text(detail).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                }
                HStack(spacing: 10) {
                    CapsuleButton(title: "Play", systemImage: "play.fill", prominent: true, action: onPlay)
                    CapsuleButton(title: "Shuffle", systemImage: "shuffle", action: onShuffle)
                }
                .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 64)
        .padding(.bottom, 10)
    }
}

// the soft glow of the cover behind a page's header, a tiny copy of the image blurred
struct CoverBackdrop: View {
    let thumbnail: String?

    var body: some View {
        RemoteImage(url: thumbnail, size: 60)
            .frame(height: 440)
            .frame(maxWidth: .infinity)
            .blur(radius: 70, opaque: true)
            .opacity(0.5)
            .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
            .allowsHitTesting(false)
    }
}

// a list of songs that plays as one queue
struct SongList: View {
    let songs: [SongItem]
    var title: String? = nil
    var numbered = false
    var showsAlbum = true

    @Environment(PlayerModel.self) private var player

    var body: some View {
        LazyVStack(spacing: 2) {
            ForEach(Array(songs.enumerated()), id: \.element.id) { offset, song in
                SongRow(song: song, number: numbered ? offset + 1 : nil, showsAlbum: showsAlbum) {
                    player.play(songs, startAt: offset, title: title)
                }
            }
        }
        .padding(.horizontal, Theme.gutter - 10)
    }
}
