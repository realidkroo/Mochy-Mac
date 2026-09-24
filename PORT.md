# Mochy for Mac

A native SwiftUI port of the Android app in `~/Project/mochy`, built from the concept frames: a slim sidebar with the traffic lights on a pill, the recap hero on Home, the floating player bar, the lyrics column that slides in from the right, and the full player with the cover deck and the lyrics stage.

It shares its YouTube layer with `~/Project/mochy-ios` (copied, not linked) and only uses Apple's frameworks: SwiftUI, AVFoundation, SwiftData, MediaPlayer and Metal.

## Build

```sh
./scripts/build-app.sh          # Release, writes build/Mochy.app (x86_64)
./scripts/build-app.sh Debug
```

The deployment target is macOS 15, since this Mac (Intel, 2017) stops at 15.7. Liquid Glass is used behind `#available(macOS 26, *)`; on 15 the bars use a tinted material. The app icon is a plain `AppIcon.icns` in `Mochy/Resources`, made from `AppIcon-1024.png` with `iconutil`, so there's no asset catalog.

The library lives in `~/Library/Application Support/Mochy/Library.store`, not SwiftData's shared `default.store`.

## Layout

| Folder | What's in it |
|---|---|
| `YouTube/` | InnerTube client, renderer parsing, pages, stream resolver (from the iOS port) |
| `Playback/` | `PlayerModel` (AVPlayer, queue, radio, shuffle, saved session), media keys and Now Playing |
| `Library/` | SwiftData models, likes, history, local playlists, the month recap |
| `Lyrics/` | the lyrics parser, the source grading (`LyricsService`) and every source under `Providers/` |
| `Shaders/` | Metal versions of the Android AGSL: lyric rise and bloom, the ambient backdrop, the cover warp, the one-pass progressive blur |
| `UI/` | shell (window chrome, sidebar, root), home, search, library, album / artist / playlist pages, player, lyrics, settings |

## Lyrics sources

All twelve of the Android registry, asked at once and graded the same way (script first, then word > line > plain, then duet tags, then your order): Apple Music (BetterLyrics TTML), YouLyPlus, PaxSenix, SimpMusic, LrcLib, Deezer, YouTube Subtitle, YouTube Music, NetEase, QQ Music, KuGou, YouTube Auto Captions.

Checked live on 2026-11-06:

- PaxSenix answers every request with a Cloudflare challenge page from this network, so it finds nothing. It's left in, the same as Android sends it.
- YouTube's `get_transcript` refuses guest requests ("Precondition check failed"), even with the panel's own params. YouTube Subtitle now reads the label's uploaded caption track first, in the language the auto captions say is sung, and only tries the transcript after.
- YouLyPlus's first mirror (prjktla) is down with a Cloudflare 1033; binimum works. Its cache only matches queries encoded like Ktor encodes them, commas as `%2C`.

## Checking the UI without screen recording permission

Debug builds run a scripted tour when `MOCHY_TOUR_DIR` is set: it plays a song muted, opens the lyrics panel and the player, and saves a PNG of the window at each stop (`DebugTour.swift`). The tour keeps its library in `Mochy-tour`, and running it from a copy with another bundle id keeps its settings apart too.

## Still to port

1. Player styles, canvas and video backgrounds.
2. Translation and romanisation of lyrics, lyrics offset and auto sync.
3. Downloads, the equalizer and crossfade.
4. YouTube account login and library sync.
5. Importers, Last.fm, Discord presence, code modules.
