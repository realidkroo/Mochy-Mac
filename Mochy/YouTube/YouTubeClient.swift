import Foundation

// who we pretend to be when asking youtube, each client gets different answers and different stream rules
nonisolated struct YouTubeClient: Sendable {
    let name: String
    let version: String
    let id: String
    let userAgent: String
    var osName: String? = nil
    var osVersion: String? = nil
    var deviceMake: String? = nil
    var deviceModel: String? = nil

    static let webUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0"

    // the music website, it gives the richest browse pages
    static let webRemix = YouTubeClient(
        name: "WEB_REMIX",
        version: "1.20260707.12.00",
        id: "67",
        userAgent: webUserAgent
    )

    // the plain youtube website, the only one whose transcript panel answers
    static let web = YouTubeClient(
        name: "WEB",
        version: "2.20260708.00.00",
        id: "1",
        userAgent: webUserAgent
    )

    // the only client measured to hand out whole songs without a po token, as long as we send a visitor id
    static let visionOS = YouTubeClient(
        name: "VISIONOS",
        version: "0.1",
        id: "101",
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
        osName: "visionOS",
        osVersion: "1.3.21O771",
        deviceMake: "Apple",
        deviceModel: "RealityDevice14,1"
    )

    // the ipad app, its hls manifests are a last resort when visionos says no
    static let iPadOS = YouTubeClient(
        name: "IOS",
        version: "21.03.3",
        id: "5",
        userAgent: "com.google.ios.youtube/21.03.3 (iPad7,6; U; CPU iPadOS 17_7_10 like Mac OS X; en-US)",
        osName: "iPadOS",
        osVersion: "17.7.10.21H450",
        deviceMake: "Apple",
        deviceModel: "iPad7,6"
    )

    func context(locale: Locale, visitorData: String?) -> [String: Any] {
        var client: [String: Any] = [
            "clientName": name,
            "clientVersion": version,
            "gl": locale.region?.identifier ?? "US",
            "hl": locale.language.languageCode?.identifier ?? "en",
        ]
        client["osName"] = osName
        client["osVersion"] = osVersion
        client["deviceMake"] = deviceMake
        client["deviceModel"] = deviceModel
        client["visitorData"] = visitorData
        return ["client": client]
    }

    // googlevideo checks these against the client named in the stream link, so a stream needs its own client's headers
    var streamHeaders: [String: String] {
        [
            "User-Agent": userAgent,
            "Referer": name == "WEB_REMIX" ? "https://music.youtube.com/" : "https://www.youtube.com/",
            "Origin": name == "WEB_REMIX" ? "https://music.youtube.com" : "https://www.youtube.com",
        ]
    }
}
