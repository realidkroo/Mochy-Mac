import AppKit
import SwiftData
import SwiftUI

@main
struct MochyApp: App {
    @State private var player = PlayerModel()
    @State private var library = Library()
    @State private var router = Router()
    @State private var window = WindowState()
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup("Mochy", id: "main") {
            RootView()
                .environment(player)
                .environment(library)
                .environment(router)
                .environment(window)
                .modelContainer(library.container)
                .background(WindowChrome(state: window))
                .frame(minWidth: 640, minHeight: 540)
                .task {
                    player.library = library
                    appDelegate.player = player
                    appDelegate.router = router
                    KeyboardShortcuts.install(player: player, router: router)
                    #if DEBUG
                    DebugTour.runIfAsked(player: player, router: router)
                    #endif
                    // the guest id is needed before the first play, fetching it now saves that wait later
                    await InnerTube.shared.ensureVisitorData()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 800)
        .windowResizability(.contentMinSize)
        .commands { MochyCommands(player: player, router: router) }

        Settings {
            SettingsView()
                .environment(player)
                .environment(library)
                .preferredColorScheme(.dark)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var player: PlayerModel?
    var router: Router?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        player?.saveSession()
    }

    // the dock menu, for playing and skipping without opening the window
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let player, player.current != nil else { return nil }
        let menu = NSMenu()
        for (title, action) in [
            (player.isPlaying ? String(localized: "Pause") : String(localized: "Play"), #selector(dockPlayPause)),
            (String(localized: "Next"), #selector(dockNext)),
            (String(localized: "Previous"), #selector(dockPrevious)),
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    @objc private func dockPlayPause() { player?.togglePlayPause() }
    @objc private func dockNext() { player?.skipNext() }
    @objc private func dockPrevious() { player?.skipPrevious() }
}

// space plays and pauses unless you're typing, the menu can't do that on its own without eating spaces in the search box
enum KeyboardShortcuts {
    private static var monitor: Any?

    static func install(player: PlayerModel, router: Router) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let typing = NSApp.keyWindow?.firstResponder is NSText
            let plain = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function]).isEmpty
            guard plain, !typing else { return event }
            switch event.keyCode {
            case 49:
                player.togglePlayPause()
                return nil
            case 53 where router.playerOpen:
                router.togglePlayer()
                return nil
            default:
                return event
            }
        }
    }
}

struct MochyCommands: Commands {
    let player: PlayerModel
    let router: Router

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Playlist…") { router.newPlaylistPrompt = true }
                .keyboardShortcut("n", modifiers: .command)
        }
        CommandMenu("Playback") {
            Button(player.isPlaying ? "Pause" : "Play") { player.togglePlayPause() }
            Button("Next") { player.skipNext() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("Previous") { player.skipPrevious() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Divider()
            Button("Skip Ahead 10 Seconds") { player.seek(by: 10) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Button("Skip Back 10 Seconds") { player.seek(by: -10) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Divider()
            Button("Volume Up") { player.volume = min(1, player.volume + 0.1) }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Volume Down") { player.volume = max(0, player.volume - 0.1) }
                .keyboardShortcut(.downArrow, modifiers: .command)
            Divider()
            Button(player.isShuffled ? "Turn Shuffle Off" : "Shuffle") { player.toggleShuffle() }
                .keyboardShortcut("s", modifiers: [.command, .option])
            Button("Repeat: \(repeatLabel)") { player.cycleRepeat() }
                .keyboardShortcut("r", modifiers: .command)
        }
        CommandGroup(after: .sidebar) {
            Button(router.lyricsOpen ? "Hide Lyrics" : "Show Lyrics") { router.toggleLyrics() }
                .keyboardShortcut("l", modifiers: .command)
            Button(router.playerOpen ? "Close Player" : "Open Player") { router.togglePlayer() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Divider()
            Button("Home") { router.playerOpen = false; router.select(.home) }
                .keyboardShortcut("1", modifiers: .command)
            Button("Search") { router.focusSearch() }
                .keyboardShortcut("f", modifiers: .command)
            Button("Library") { router.playerOpen = false; router.select(.library) }
                .keyboardShortcut("3", modifiers: .command)
            Button("Back") { router.pop() }
                .keyboardShortcut("[", modifiers: .command)
        }
    }

    private var repeatLabel: String {
        switch player.repeatMode {
        case .off: String(localized: "Off")
        case .all: String(localized: "All")
        case .one: String(localized: "One")
        }
    }
}
