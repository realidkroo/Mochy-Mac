import Foundation

// a playable link for one song, plus what the player shows about it
nonisolated struct StreamInfo: Sendable {
    let url: URL
    let headers: [String: String]
    let codec: String
    let sampleRate: Int?
    let bitrate: Int?
    let loudnessDb: Double?
    let expiresAt: Date
    let isHLS: Bool
    // youtube's own length for the stream, the m4a header sometimes claims twice the real length
    var approxDuration: TimeInterval? = nil

    // the little badge next to the title, like "AAC · 44.1 kHz"
    var formatLabel: String {
        guard let sampleRate else { return codec }
        return "\(codec) · \(String(format: "%.1f", Double(sampleRate) / 1000)) kHz"
    }
}

extension InnerTube {
    // avplayer can't play opus in webm, so only the aac streams count
    func stream(for videoId: String, preferHighQuality: Bool = true) async throws -> StreamInfo {
        await ensureVisitorData()
        var reasons: [String] = []

        for client in [YouTubeClient.visionOS, .iPadOS] {
            let response: JSON
            do {
                response = try await player(videoId: videoId, client: client)
            } catch {
                reasons.append("\(client.name): \(error.localizedDescription)")
                continue
            }
            let status = response["playabilityStatus"]["status"].string ?? "UNKNOWN"
            guard status == "OK" else {
                reasons.append("\(client.name): \(response["playabilityStatus"]["reason"].string ?? status)")
                continue
            }
            if let stream = pickStream(response, client: client, preferHighQuality: preferHighQuality) {
                return stream
            }
            reasons.append("\(client.name): no stream this phone can play")
        }

        // a stale guest id is the usual reason every client says no, so the next try starts fresh
        resetVisitorData()
        throw InnerTubeError.unplayable(reasons.first ?? "Couldn't play this song.")
    }

    private func player(videoId: String, client: YouTubeClient) async throws -> JSON {
        try await post("player", client: client, body: [
            "videoId": videoId,
            "contentCheckOk": true,
            "racyCheckOk": true,
        ])
    }

    private func pickStream(_ response: JSON, client: YouTubeClient, preferHighQuality: Bool) -> StreamInfo? {
        let streaming = response["streamingData"]
        let lifetime = streaming["expiresInSeconds"].int ?? 21_540
        let expiresAt = Date().addingTimeInterval(TimeInterval(lifetime - 60))
        let loudness = response["playerConfig"]["audioConfig"]["loudnessDb"].double

        let audio = streaming["adaptiveFormats"].array
            .filter { ($0["mimeType"].string ?? "").hasPrefix("audio/mp4") && $0["url"].string != nil }
            .sorted { ($0["bitrate"].int ?? 0) < ($1["bitrate"].int ?? 0) }
        if let format = preferHighQuality ? audio.last : audio.first,
           let link = format["url"].string, let url = URL(string: link) {
            return StreamInfo(
                url: url,
                headers: client.streamHeaders,
                codec: "AAC",
                sampleRate: format["audioSampleRate"].int,
                bitrate: format["bitrate"].int,
                loudnessDb: format["loudnessDb"].double ?? loudness,
                expiresAt: expiresAt,
                isHLS: false,
                approxDuration: format["approxDurationMs"].double.map { $0 / 1000 }
            )
        }

        if let link = streaming["hlsManifestUrl"].string, let url = URL(string: link) {
            return StreamInfo(url: url, headers: client.streamHeaders, codec: "HLS", sampleRate: nil, bitrate: nil, loudnessDb: loudness, expiresAt: expiresAt, isHLS: true)
        }
        return nil
    }
}
