import Foundation

@Observable
final class HomeModel {
    private(set) var page: HomePage?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private var loadingMore = false

    var sections: [FeedSection] {
        guard let page else { return [] }
        guard AppSettings.hideExplicit else { return page.sections }
        return page.sections.compactMap { section in
            let items = section.items.filter { $0.song?.explicit != true }
            guard !items.isEmpty else { return nil }
            return FeedSection(title: section.title, label: section.label, thumbnail: section.thumbnail, moreBrowseId: section.moreBrowseId, moreParams: section.moreParams, items: items)
        }
    }

    // the hero's fallback when there's no listening yet: the first big picture in the feed
    var heroItem: (item: YTItem, label: String)? {
        for section in sections {
            if let item = section.items.first(where: { $0.song == nil && $0.thumbnail != nil }) ?? section.items.first {
                return (item, section.title)
            }
        }
        return nil
    }

    func load(force: Bool = false) async {
        guard force || page == nil, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            page = try await InnerTube.shared.home()
        } catch {
            errorMessage = String(localized: "Couldn't load your home feed. Check your connection and try again.")
        }
    }

    func loadMore() async {
        guard !loadingMore, let token = page?.continuation else { return }
        loadingMore = true
        defer { loadingMore = false }
        guard let more = try? await InnerTube.shared.homeContinuation(token) else { return }
        let known = Set(page?.sections.map(\.id) ?? [])
        page?.sections.append(contentsOf: more.sections.filter { !known.contains($0.id) })
        page?.continuation = more.continuation
    }
}
