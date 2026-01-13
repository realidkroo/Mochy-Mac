import SwiftUI

// the dark frosted pill every floating bar sits on: liquid glass on macos 26, a tinted material before it
struct GlassBackground<S: InsettableShape>: ViewModifier {
    let shape: S
    var tint: Double = 0.55

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.tint(.black.opacity(tint * 0.6)), in: shape)
        } else {
            content
                .background(Color(white: 0.09).opacity(tint), in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.09), lineWidth: 0.75))
                .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        }
    }
}

extension View {
    func glassPill(tint: Double = 0.55) -> some View {
        modifier(GlassBackground(shape: Capsule(), tint: tint))
    }

    func glassCard(cornerRadius: CGFloat, tint: Double = 0.55) -> some View {
        modifier(GlassBackground(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), tint: tint))
    }
}

// a round icon button with a soft hover light, used across the bars and the player
struct BarButton: View {
    let systemImage: String
    var size: CGFloat = 30
    var iconSize: CGFloat = 13
    var isActive = false
    var help: LocalizedStringKey? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.82))
                .frame(width: size, height: size)
                .background(Circle().fill(isActive ? Theme.selected : (isHovered ? Theme.hover : .clear)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help.map { Text($0) } ?? Text(""))
    }
}

// the press feel for big tappable things: a slight shrink while held
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// a capsule with a word or two, like the hero's "view" button and the search filters
struct CapsuleButton: View {
    let label: Text
    var systemImage: String?
    var isSelected: Bool
    var prominent: Bool
    let action: () -> Void

    @State private var isHovered = false

    init(title: LocalizedStringKey, systemImage: String? = nil, isSelected: Bool = false, prominent: Bool = false, action: @escaping () -> Void) {
        self.init(label: Text(title), systemImage: systemImage, isSelected: isSelected, prominent: prominent, action: action)
    }

    // for words people typed themselves, which must never be looked up as a translation
    init(verbatim: String, systemImage: String? = nil, isSelected: Bool = false, prominent: Bool = false, action: @escaping () -> Void) {
        self.init(label: Text(verbatim: verbatim), systemImage: systemImage, isSelected: isSelected, prominent: prominent, action: action)
    }

    private init(label: Text, systemImage: String?, isSelected: Bool, prominent: Bool, action: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.prominent = prominent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                label
                if let systemImage { Image(systemName: systemImage).font(.system(size: 10, weight: .bold)) }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isSelected || prominent ? Color.black : Color.white)
            .padding(.horizontal, 13)
            .frame(height: 28)
            .background(Capsule().fill(isSelected || prominent ? Color.white.opacity(isHovered ? 0.85 : 0.95) : Color.white.opacity(isHovered ? 0.22 : 0.14)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .onHover { isHovered = $0 }
    }
}

// "Recently Played ›", a section title that opens the full list when it has one
struct SectionHeader: View {
    let title: String
    var action: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                        .offset(x: isHovered ? 2 : 0)
                }
            }
            .foregroundStyle(.white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

// a page's big title, left aligned like the concept's pages
struct PageTitle: View {
    let title: LocalizedStringKey
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.5)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// what a page shows while it's loading or when it couldn't
struct LoadState: View {
    let errorMessage: String?
    let retry: () -> Void

    var body: some View {
        if let errorMessage {
            ContentUnavailableView {
                Label("Couldn't load this", systemImage: "wifi.exclamationmark")
            } description: {
                Text(errorMessage)
            } actions: {
                CapsuleButton(title: "Try again", prominent: true, action: retry)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// a floating back button for pushed pages
struct BackButton: View {
    @Environment(Router.self) private var router

    var body: some View {
        BarButton(systemImage: "chevron.left", size: 32, iconSize: 13, help: "Back") { router.pop() }
            .glassPill(tint: 0.4)
            .keyboardShortcut("[", modifiers: .command)
    }
}

// little equaliser bars on the song that's playing
struct PlayingBars: View {
    let isPlaying: Bool
    var color: Color = .white

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { bar in
                    Capsule().fill(color).frame(width: 2.5, height: 4 + 9 * phase(bar, t))
                }
            }
            .frame(width: 14, height: 13, alignment: .bottom)
        }
    }

    private func phase(_ bar: Int, _ time: Double) -> CGFloat {
        guard isPlaying else { return 0.3 }
        let index = Double(bar)
        let wave = sin(time * (5.2 + index * 1.7) + index * 1.3)
        return CGFloat((wave + 1) / 2)
    }
}
