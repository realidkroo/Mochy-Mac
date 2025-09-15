import AppKit
import ImageIO
import SwiftUI

// a decoded picture that can cross threads, core graphics images never change once made
nonisolated struct DecodedImage: @unchecked Sendable {
    let cgImage: CGImage
}

// downloads covers once, decodes them off the main thread at the size they're drawn, and keeps the recent ones in memory
nonisolated final class ImageLoader: @unchecked Sendable {
    static let shared = ImageLoader()

    private let memory = NSCache<NSString, CGImageBox>()
    private let session: URLSession

    private final class CGImageBox {
        let image: DecodedImage
        init(_ image: DecodedImage) { self.image = image }
    }

    private init() {
        memory.countLimit = 400
        memory.totalCostLimit = 192 * 1024 * 1024
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024, directory: nil)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }

    private func key(_ url: String, _ pixels: Int) -> NSString { "\(pixels)|\(url)" as NSString }

    // what's already in memory, so a cover scrolled back into view shows on its first frame with no fade
    func cached(_ url: String, pixels: Int) -> DecodedImage? {
        memory.object(forKey: key(url, pixels))?.image
    }

    func image(_ url: String, pixels: Int) async -> DecodedImage? {
        if let hit = cached(url, pixels: pixels) { return hit }
        guard let link = URL(string: url) else { return nil }
        guard let (data, _) = try? await session.data(from: link) else { return nil }
        let decoded = await Task.detached(priority: .userInitiated) { Self.decode(data, pixels: pixels) }.value
        if let decoded {
            memory.setObject(CGImageBox(decoded), forKey: key(url, pixels), cost: decoded.cgImage.bytesPerRow * decoded.cgImage.height)
        }
        return decoded
    }

    // a thumbnail decode straight to the drawn size, a full-size cover would cost ten times the memory
    private static func decode(_ data: Data, pixels: Int) -> DecodedImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(pixels, 16),
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return DecodedImage(cgImage: image)
    }
}

// a cover from the web that fades in once, and pops in instantly when it was already in memory
struct RemoteImage: View {
    let url: String?
    // the size in points it's drawn at, the loader asks for twice that for retina screens
    var size: CGFloat = 200
    var contentMode: ContentMode = .fill

    @State private var image: DecodedImage?
    @State private var loadedKey: String?

    private var pixels: Int { Int(size * 2) }
    private var resolvedURL: String? {
        guard let url, !url.isEmpty else { return nil }
        return url.resizedThumbnail(pixels)
    }

    var body: some View {
        let key = resolvedURL
        let shown = loadedKey == key ? image : key.flatMap { ImageLoader.shared.cached($0, pixels: pixels) }
        ZStack {
            Theme.placeholder
            if let shown {
                Image(decorative: shown.cgImage, scale: 2)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            }
        }
        .clipped()
        .task(id: key) {
            guard let key else { return }
            if ImageLoader.shared.cached(key, pixels: pixels) != nil {
                loadedKey = key
                image = ImageLoader.shared.cached(key, pixels: pixels)
                return
            }
            let loaded = await ImageLoader.shared.image(key, pixels: pixels)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                loadedKey = key
                image = loaded
            }
        }
    }
}
