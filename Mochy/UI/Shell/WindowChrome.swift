import AppKit
import SwiftUI

// where the red, yellow and green buttons go: centred on the pill in the top left, the pill follows wherever they really land
enum TrafficLights {
    static let firstX: CGFloat = 14
    static let spacing: CGFloat = 20
    static let centerY: CGFloat = 20
    static let pillPadding = CGSize(width: 7, height: 6)
    // room the pill takes at the top of a page when the sidebar is hidden
    static let clearance: CGFloat = 44
}

// what the window is doing that the layout cares about
@Observable
final class WindowState {
    var isFullScreen = false
    var isVisible = true
    // the three buttons' frame, top-left based, so the pill can sit exactly behind them
    var lightsFrame: CGRect?
}

// reaches the nswindow behind the swiftui scene to hide its title bar and move the traffic lights onto their pill
struct WindowChrome: NSViewRepresentable {
    let state: WindowState

    func makeNSView(context: Context) -> ChromeView {
        let view = ChromeView()
        view.state = state
        return view
    }

    func updateNSView(_ nsView: ChromeView, context: Context) {}

    final class ChromeView: NSView {
        var state: WindowState?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = false
            window.backgroundColor = .black
            window.appearance = NSAppearance(named: .darkAqua)
            window.minSize = NSSize(width: 640, height: 540)
            window.setFrameAutosaveName("MochyMainWindow")
            placeButtons()

            // appkit lays its title bar out again on these, which puts the buttons back where it likes them
            let names: [Notification.Name] = [
                NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
                NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                NSWindow.didExitFullScreenNotification, NSWindow.didEnterFullScreenNotification,
                NSWindow.willEnterFullScreenNotification, NSWindow.willExitFullScreenNotification,
                NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                NSWindow.didDeminiaturizeNotification,
            ]
            for name in names {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                    let name = note.name
                    MainActor.assumeIsolated { self?.windowChanged(name) }
                })
            }
        }

        private func windowChanged(_ name: Notification.Name) {
            guard let window else { return }
            switch name {
            case NSWindow.willEnterFullScreenNotification: state?.isFullScreen = true
            case NSWindow.willExitFullScreenNotification: state?.isFullScreen = false
            case NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification:
                // nothing animates while nobody can see the window
                state?.isVisible = window.occlusionState.contains(.visible) && !window.isMiniaturized
            default: break
            }
            placeButtons()
            DispatchQueue.main.async { [weak self] in self?.placeButtons() }
        }

        private var isPlacing = false

        // moves the buttons inside appkit's own title bar, then reports where they ended up
        private func placeButtons() {
            guard !isPlacing, let window, !window.styleMask.contains(.fullScreen),
                  let close = window.standardWindowButton(.closeButton),
                  let titlebar = close.superview
            else { return }
            isPlacing = true
            defer { isPlacing = false }
            let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0) }
            let height = titlebar.bounds.height
            for (index, button) in buttons.enumerated() {
                if !button.postsFrameChangedNotifications { watch(button) }
                let size = button.frame.size
                let centre = min(TrafficLights.centerY, height - size.height / 2)
                let y = titlebar.isFlipped ? centre - size.height / 2 : height - centre - size.height / 2
                let origin = NSPoint(x: TrafficLights.firstX + CGFloat(index) * TrafficLights.spacing, y: y)
                if button.frame.origin != origin { button.setFrameOrigin(origin) }
            }
            let union = buttons.map { $0.convert($0.bounds, to: nil) }.reduce(CGRect.null) { $0.union($1) }
            guard !union.isNull else { return }
            let topLeft = CGRect(x: union.minX, y: window.frame.height - union.maxY, width: union.width, height: union.height)
            if state?.lightsFrame != topLeft { state?.lightsFrame = topLeft }
        }

        // appkit lays the title bar out again whenever it likes, so every move of a button puts it back
        private func watch(_ button: NSButton) {
            button.postsFrameChangedNotifications = true
            observers.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: button, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.placeButtons() }
            })
        }
    }
}

// the dark pill the traffic lights rest on, like the concept's top-left corner
struct TrafficLightPill: View {
    @Environment(WindowState.self) private var window

    var body: some View {
        if let lights = window.lightsFrame {
            let pill = lights.insetBy(dx: -TrafficLights.pillPadding.width, dy: -TrafficLights.pillPadding.height)
            Capsule()
                .fill(Color(white: 0.16))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5))
                .frame(width: pill.width, height: pill.height)
                .offset(x: pill.minX, y: pill.minY)
                .allowsHitTesting(false)
        }
    }
}
