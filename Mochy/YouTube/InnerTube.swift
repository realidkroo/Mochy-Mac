import Foundation

nonisolated enum InnerTubeError: LocalizedError {
    case badResponse(Int)
    case missing(String)
    case unplayable(String)

    var errorDescription: String? {
        switch self {
        case .badResponse(let code): "YouTube answered with an error (\(code))."
        case .missing(let what): "YouTube's answer was missing the \(what)."
        case .unplayable(let reason): reason
        }
    }
}

// talks to youtube music's private api, runs off the main thread so big answers never stall a frame
actor InnerTube {
    static let shared = InnerTube()

    private static let apiURL = URL(string: "https://music.youtube.com/youtubei/v1/")!
    private static let visitorKey = "innertube.visitorData"

    private let session: URLSession
    private(set) var visitorData: String? = UserDefaults.standard.string(forKey: InnerTube.visitorKey)
    private var visitorTask: Task<String?, Never>?

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = ["Accept-Language": "en-US,en;q=0.9"]
        session = URLSession(configuration: config)
    }

    func post(_ endpoint: String, client: YouTubeClient = .webRemix, body: [String: Any], query: [URLQueryItem] = []) async throws -> JSON {
        var components = URLComponents(url: Self.apiURL.appending(path: endpoint), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "prettyPrint", value: "false")] + query

        var payload = body
        payload["context"] = client.context(locale: .current, visitorData: visitorData)

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("1", forHTTPHeaderField: "X-Goog-Api-Format-Version")
        request.setValue(client.id, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(client.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "X-Origin")
        request.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
        if let visitorData { request.setValue(visitorData, forHTTPHeaderField: "X-Goog-Visitor-Id") }

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw InnerTubeError.badResponse(http.statusCode)
        }
        return try JSON(data: data)
    }

    // a guest id youtube hands every visitor, the visionos client won't play anything without one
    @discardableResult
    func ensureVisitorData() async -> String? {
        if let visitorData { return visitorData }
        if let visitorTask { return await visitorTask.value }
        let task = Task { await fetchVisitorData() }
        visitorTask = task
        let value = await task.value
        visitorTask = nil
        if let value {
            visitorData = value
            UserDefaults.standard.set(value, forKey: Self.visitorKey)
        }
        return value
    }

    // drops the guest id so the next request gets a fresh one, for when youtube starts treating us like a bot
    func resetVisitorData() {
        visitorData = nil
        UserDefaults.standard.removeObject(forKey: Self.visitorKey)
    }

    private func fetchVisitorData() async -> String? {
        var request = URLRequest(url: URL(string: "https://music.youtube.com/sw.js_data")!)
        request.setValue(YouTubeClient.webUserAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await session.data(for: request),
              let text = String(data: data, encoding: .utf8), text.count > 5,
              let json = try? JSON(data: Data(text.dropFirst(5).utf8))
        else { return nil }
        // the id sits somewhere in the third list, it's the string that starts with Cgt or Cgs
        return json[0][2].array.compactMap(\.string).first { $0.hasPrefix("Cgt") || $0.hasPrefix("Cgs") }
    }
}
