import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            PlaybackSettings()
                .tabItem { Label("Playback", systemImage: "play.circle") }
            LyricsSettingsView()
                .tabItem { Label("Lyrics", systemImage: "quote.bubble") }
            AppearanceSettings()
                .tabItem { Label("Look", systemImage: "sparkles") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 520)
    }
}

private struct PlaybackSettings: View {
    @AppStorage(AppSettings.highQualityAudioKey) private var highQuality = true
    @AppStorage(AppSettings.normalizeVolumeKey) private var normalize = true
    @AppStorage(AppSettings.hideExplicitKey) private var hideExplicit = false

    var body: some View {
        Form {
            Section {
                Toggle("Best audio quality", isOn: $highQuality)
                Text("Streams the highest bitrate YouTube offers. Turn it off to save data.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Even out loudness", isOn: $normalize)
                Text("Loud songs are turned down a little so a mix doesn't jump in volume.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Hide explicit songs on Home", isOn: $hideExplicit)
            }
        }
        .formStyle(.grouped)
    }
}

// the lyrics sources: switch them on or off and drag them into the order you trust
private struct LyricsSettingsView: View {
    @State private var order = LyricsSettings.order
    @State private var disabled = LyricsSettings.disabled
    @AppStorage(AppSettings.lyricsSizeKey) private var sizeScale = 1.0

    var body: some View {
        Form {
            Section {
                List {
                    ForEach(order) { provider in
                        HStack(spacing: 10) {
                            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(provider.displayName)
                                Text(provider.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { !disabled.contains(provider) },
                                set: { enabled in
                                    LyricsSettings.setEnabled(provider, enabled)
                                    disabled = LyricsSettings.disabled
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }
                        .padding(.vertical, 2)
                    }
                    .onMove { source, destination in
                        order.move(fromOffsets: source, toOffset: destination)
                        LyricsSettings.save(order: order)
                    }
                }
                .frame(minHeight: 300)
            } header: {
                Text("Sources")
            } footer: {
                Text("Every source is asked at once. Word-by-word lyrics in the song's own language win, and your order breaks ties.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Slider(value: $sizeScale, in: 0.8...1.3, step: 0.05) {
                    Text("Text size")
                }
                Button("Restore the default order") {
                    order = LyricsProvider.defaultOrder
                    LyricsSettings.save(order: order)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppearanceSettings: View {
    @AppStorage(AppSettings.lyricsBlurKey) private var blur = true
    @AppStorage(AppSettings.lyricsGlowKey) private var glow = true
    @AppStorage(AppSettings.animatedBackgroundsKey) private var animated = true

    var body: some View {
        Form {
            Section {
                Toggle("Blur the lines that aren't being sung", isOn: $blur)
                Toggle("Glow on the words as they're sung", isOn: $glow)
                Toggle("Moving backgrounds", isOn: $animated)
                Text("The player's colours and the home cover drift slowly. Turn it off to keep everything still.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 14) {
            IconShape(icon: .mochy)
                .fill(.white)
                .frame(width: 64, height: 64)
            Text("Mochy for Mac").font(.title2.bold())
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1")")
                .foregroundStyle(.secondary)
            Text("Music from YouTube Music, lyrics from twelve sources, made to feel good to listen with.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 340)
            Link("Mochy on GitHub", destination: URL(string: "https://github.com/realidkroo/Mochy-Music")!)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
