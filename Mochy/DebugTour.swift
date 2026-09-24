#if DEBUG
import AppKit
import SwiftUI

// a scripted walk through the app that saves a picture of the window at each stop, only in debug builds and only when MOCHY_TOUR_DIR is set
enum DebugTour {
    private typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    static func runIfAsked(player: PlayerModel, router: Router) {
        guard let dir = ProcessInfo.processInfo.environment["MOCHY_TOUR_DIR"] else { return }
        let search = ProcessInfo.processInfo.environment["MOCHY_TOUR_SONG"] ?? "die with a smile lady gaga"
        Task {
            let volume = player.volume
            player.volume = 0
            try? await Task.sleep(for: .seconds(9))
            snap(dir, "1-home")
            if let summary = try? await InnerTube.shared.searchSummary(search),
               let song = summary.sections.first(where: { $0.isAllSongs })?.items.first?.song ?? summary.top?.song {
                player.play(song)
            }
            router.toggleLyrics()
            try? await Task.sleep(for: .seconds(14))
            player.seek(to: 40)
            try? await Task.sleep(for: .seconds(3))
            for frame in 0..<14 {
                snap(dir, "2-panel-\(String(format: "%02d", frame))")
                try? await Task.sleep(for: .milliseconds(110))
            }
            router.togglePlayer()
            try? await Task.sleep(for: .seconds(4))
            for frame in 0..<14 {
                snap(dir, "3-player-\(String(format: "%02d", frame))")
                try? await Task.sleep(for: .milliseconds(110))
            }
            router.queueOpen = true
            try? await Task.sleep(for: .seconds(1.5))
            snap(dir, "4-queue")
            router.queueOpen = false
            router.togglePlayer()
            router.toggleLyrics()
            router.focusSearch()
            try? await Task.sleep(for: .seconds(2))
            snap(dir, "5-search")
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 500 }) {
                window.setContentSize(NSSize(width: 760, height: 640))
            }
            router.select(.home)
            try? await Task.sleep(for: .seconds(2))
            snap(dir, "6-narrow")
            player.pause()
            player.volume = volume
            try? await Task.sleep(for: .seconds(1))
            NSApp.terminate(nil)
        }
    }

    private static func snap(_ dir: String, _ name: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 500 }),
              let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage")
        else { return }
        let capture = unsafeBitCast(symbol, to: Capture.self)
        guard let image = capture(.null, CGWindowListOption.optionIncludingWindow.rawValue, CGWindowID(window.windowNumber), CGWindowImageOption.boundsIgnoreFraming.rawValue)?.takeRetainedValue() else { return }
        let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        try? data?.write(to: URL(fileURLWithPath: dir).appending(path: "\(name).png"))
    }
}
#endif
