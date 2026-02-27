import SwiftUI

struct HomeView: View {
    @Environment(PlayerModel.self) private var player
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @State private var model = HomeModel()
    @State private var recent: [SongItem] = []
    @State private var recap: MonthRecap?

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 34) {
                HomeHero(recap: recap, fallback: model.heroItem)
                    .containerRelativeFrame(.vertical) { height, _ in min(max(height * 0.6, 380), 600) }

                if !recent.isEmpty {
                    Shelf(title: String(localized: "Recently Played"), items: recent.map(YTItem.song), cardSize: 132) {
                        router.push(.history)
                    }
                    // the row sits up in the hero's fade, like the concept
                    .padding(.top, -78)
                }

                ForEach(model.sections) { section in
                    if section.isAllSongs && section.items.count >= 8 {
                        QuickPicks(section: section)
                    } else {
                        Shelf(title: section.title, label: section.label, items: section.items, onMore: section.moreBrowseId == nil ? nil : {
                            router.push(.section(section))
                        })
                    }
                }

                if model.page == nil {
                    LoadState(errorMessage: model.errorMessage) { Task { await model.load(force: true) } }
                        .frame(height: 220)
                } else if model.page?.continuation != nil {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .task { await model.loadMore() }
                }
            }
            .padding(.bottom, Theme.bottomBarRoom)
        }
        .scrollIndicators(.never)
        .ignoresSafeArea()
        .task { await model.load() }
        .task(id: library.historyVersion) {
            recent = library.recentSongs(limit: 24)
            recap = library.recap()
        }
    }
}
