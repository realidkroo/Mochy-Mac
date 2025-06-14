import Foundation

// youtube music's own plain lyrics, found through the song's watch page when the player didn't hand us the id
nonisolated enum YouTubeMusicLyrics {
    static func lyrics(_ query: LyricsQuery) async throws -> String? {
        var browseId = query.lyricsBrowseId
        if browseId == nil {
            browseId = try await InnerTube.shared.next(WatchEndpoint(videoId: query.videoId)).lyricsBrowseId
        }
        guard let browseId else { return nil }
        return try await InnerTube.shared.lyrics(browseId: browseId)?.nilIfBlank
    }
}

extension InnerTube {
    // the transcript panel of the video, line-timed, asked as the plain youtube website
    func transcript(videoId: String) async throws -> String? {
        let params = Data("\n\u{0B}\(videoId)".utf8).base64EncodedString()
        let response = try await post("get_transcript", client: .web, body: ["params": params])
        let groups = response["actions"][0]["updateEngagementPanelAction"]["content"]["transcriptRenderer"]["body"]["transcriptBodyRenderer"]["cueGroups"].array
        let lines = groups.compactMap { group -> String? in
            let cue = group["transcriptCueGroupRenderer"]["cues"][0]["transcriptCueRenderer"]
            guard let ms = cue["startOffsetMs"].int, let text = cue["cue"]["simpleText"].string else { return nil }
            let clean = text.trimmingCharacters(in: CharacterSet(charactersIn: "♪ "))
            return clean.isEmpty ? nil : TimedLine.stamp(ms) + clean
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    // the subtitles the label uploaded with the video, and the transcript panel when youtube lets guests read it
    func subtitleLyrics(videoId: String) async throws -> String? {
        if let uploaded = try await captionLyrics(videoId: videoId, uploadedOnly: true) { return uploaded }
        return try? await transcript(videoId: videoId)
    }

    // the video's captions as line-timed lyrics, an uploaded track in the auto captions' language beats the auto ones
    func captionLyrics(videoId: String, uploadedOnly: Bool = false) async throws -> String? {
        await ensureVisitorData()
        for client in [YouTubeClient.visionOS, .iPadOS, .webRemix] {
            guard let response = try? await post("player", client: client, body: ["videoId": videoId, "contentCheckOk": true, "racyCheckOk": true]) else { continue }
            let tracks = response["captions"]["playerCaptionsTracklistRenderer"]["captionTracks"].array
            // the auto captions are the only track that says what language is actually sung, an uploaded track can be a translation
            guard let auto = tracks.first(where: { $0["kind"].string == "asr" }) else { continue }
            let language = auto["languageCode"].string?.split(separator: "-").first
            let uploaded = tracks.first { $0["kind"].string != "asr" && $0["languageCode"].string?.split(separator: "-").first == language }
            guard let track = uploadedOnly ? uploaded : (uploaded ?? auto) else { return nil }
            guard let base = track["baseUrl"].string, var components = URLComponents(string: base) else { continue }
            components.queryItems = (components.queryItems ?? []).filter { $0.name != "fmt" } + [URLQueryItem(name: "fmt", value: "json3")]
            guard let url = components.url else { continue }
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")
            guard let (data, _) = try? await URLSession.shared.data(for: request), let json = try? JSON(data: data) else { continue }
            if let lrc = Self.timedTextToLRC(json), !lrc.isEmpty { return lrc }
        }
        return nil
    }

    // json3 timed text into lrc, sound labels like "[music]" and note signs aren't words and go
    nonisolated private static func timedTextToLRC(_ json: JSON) -> String? {
        var lines: [String] = []
        var previous: String?
        for event in json["events"].array {
            guard let start = event["tStartMs"].int else { continue }
            let text = event["segs"].array.compactMap { $0["utf8"].string }.joined()
                .replacingOccurrences(of: "\\[[^\\]]*\\]", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "♪", with: " ")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            // a rolling caption repeats its line as the next one scrolls in
            guard !text.isEmpty, text != previous else { continue }
            previous = text
            lines.append(TimedLine.stamp(start) + text)
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}
