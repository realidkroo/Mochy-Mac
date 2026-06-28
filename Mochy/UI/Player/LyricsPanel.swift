import SwiftUI

// the lyrics column that slides in from the right while you browse, the concept's second window
struct LyricsPanel: View {
    @Environment(PlayerModel.self) private var player
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Lyrics")
                    .font(.system(size: 20, weight: .bold))
                    .tracking(-0.3)
                Spacer()
                if player.current != nil { LyricsSourceMenu() }
                BarButton(systemImage: "arrow.up.left.and.arrow.down.right", size: 26, iconSize: 10, help: "Open in the player") {
                    router.togglePlayer()
                }
                BarButton(systemImage: "xmark", size: 26, iconSize: 10, help: "Hide lyrics") { router.toggleLyrics() }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 6)

            if let song = player.current {
                HStack(spacing: 8) {
                    Text(song.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(song.artistNames).font(.system(size: 12)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
            }

            LyricsView(style: .panel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
        .background(Theme.panel)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.hairline).frame(width: 1) }
    }
}
