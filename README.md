# AntHill

A native macOS app that puts my scripts and automations behind simple pages,
one module per sidebar row. Built in SwiftUI as a Swift package, with no Xcode
project. Made for one user on one Mac.

## Modules

| Module | What it does |
| --- | --- |
| **YT-Music** | Paste a YouTube link and press Return. `yt-dlp` downloads the audio as m4a with cover art and tags. Pause, resume, or remove items in the queue. The **Library** tab asks a local model to correct names, artists, and albums in Music.app; nothing changes until you apply the proposed changes. |
| **eCommerce Security Check** | Type a shop address and read a report before you pay: the CERT Polska warning list, domain age, the web archive, red flags on the pages, and the company (NIP, KRS) in the VAT white list and KRS. |
| **Network Monitor** | Pick an app and see its network connections, read with `lsof` every 2 seconds. |
| **Filesfer** | Saved jobs that copy, move, or zip files to another folder with `rsync`. Run one job, run all, or run them on a schedule. |

The menu bar menu has quick actions for each module. Every action has a menu
item and a keyboard shortcut.

## Requirements

- macOS 26 or later.
- Swift 6.2 (Xcode or the Command Line Tools).
- For YT-Music: `brew install yt-dlp ffmpeg`.
- For the YT-Music Library tab: a [llama.cpp](https://github.com/ggml-org/llama.cpp)
  server (`llama-server`), by default at `http://127.0.0.1:8080`. Set the address
  and model in Settings > Models.

The app is not sandboxed, so it can run `yt-dlp`, `lsof`, and `rsync`.

## Install

Download the zip from the latest [release](https://github.com/sebkrupa/AntHill/releases),
or build from source:

```sh
./build.sh          # release build, signs, installs /Applications/AntHill.app
./build.sh --open   # also quits the running copy and opens the new one
./build.sh --debug  # debug build
```

`build.sh` signs with your Apple Development certificate when you have one,
otherwise ad hoc. Build products go to `~/Library/Developer/AntHill`, outside
the repo.

AntHill checks GitHub for a newer release at launch and once a day, and offers
to install it.

## Data

- No database. The YT-Music history (every download and its log) is kept in
  `~/Library/Application Support/AntHill/history.json` until you remove it.
- Settings are in UserDefaults (`com.sebkrupa.anthill`).

## Develop

```sh
swift test --scratch-path ~/Library/Developer/AntHill/test-build   # unit tests
tools/selftest.sh                                                   # the app's real functions on a /tmp store
tools/snap.sh                                                       # light and dark snapshots in /tmp/AntHill-shots
tools/grid-lint.sh && swift tools/check-layout.swift /tmp/AntHill-shots/*-layout.json
```

Test runs never touch your real data: they need `APP_STORE` in `/tmp` and use
the `com.sebkrupa.anthill.test` defaults suite.

### Layout

- `Sources/AntHill/` the app. `App.swift` has the window, menus, and data location.
- `Sources/AntHillKit/` rules and data logic with no SwiftUI (parsers, command arguments). Tests in `Tests/AntHillKitTests/`.
- `Icon/AppIcon.icon` the app icon, an Icon Composer file. `tools/make_icon.sh` compiles it.
- `docs/` the brief, glossary, and user stories.
- `tools/` build, test, snapshot, and icon scripts.

### Add a module

1. Add a case to `Module` in `Models.swift` (title, SF Symbol).
2. Add its view to `ModuleView` in `ContentView.swift`.
3. Add its quick actions to `MenuBarContent.swift`.
4. Put pure logic in `Sources/AntHillKit/` with a test.

See [CLAUDE.md](CLAUDE.md) for the design rules.

## Release

Run **Actions > Release > Run workflow** on GitHub and type a version like
`1.2.0`. The workflow tests, builds, zips the app, and publishes the release.
Nothing publishes on push.

## License

[Apache 2.0](LICENSE)
