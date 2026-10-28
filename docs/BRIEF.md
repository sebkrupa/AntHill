# AntHill

A small Mac app that puts my scripts and automations behind simple pages, one module per page, for one user: me.

Bundle id: `com.sebkrupa.anthill`.

## Replaces
Running shell scripts from Terminal and the Alfred workflows in the Scripts repo (`SoftwareAndSupplement/Alfred/workflow/yt-download`, `ytm <link>`).

## Main jobs
1. Pick a module from the left sidebar. The sidebar can be shown or hidden (toggle).
2. YT-Music: paste a YouTube link, press Enter. The item goes into the queue list below the field.
3. YT-Music: watch each item's name and status. Pause, resume, or remove an item. Double-click a finished item to show the file in Finder.
4. YT-Music: "Clear finished" button above the list removes done items from the list (files stay on disk).
5. Settings: one download folder for all items. Change it with a folder picker.

## Data
- Module: id, name, SF Symbol, view. Modules are code, registered in one list, so a new module is one new file plus one line.
- DownloadItem: id, url, title, status (queued / downloading % / paused / done / failed + message), file path.
- Setting: download folder (`@AppStorage`). Default: the folder from `music.sh` `DEST=`.

## Shape
Sidebar window (`NavigationSplitView`), macOS 26 or later.
Local data. Needs the internet only to download. No accounts.
The queue lives in memory for version one (decided by the agent).

## How YT-Music works
Same as `music.sh`: runs `yt-dlp` (Homebrew path `/opt/homebrew/bin`) with
`--extract-audio --audio-format m4a --audio-quality 0 --embed-thumbnail --embed-metadata`,
the same `--parse-metadata` rules (artist and title from "Artist - Title"),
and a temp folder so only the finished file lands in the download folder.
Progress comes from `--progress-template` / `--print` lines, like `notify.sh`.
Pause = stop the process (SIGSTOP); resume = continue it (SIGCONT) (decided by the agent).
Downloads run one at a time, in order (decided by the agent).

## System hooks
Finder reveal (`NSWorkspace.activateFileViewerSelecting`). Folder picker (`NSOpenPanel`).

## Reference
none

## Look
Native Mac app with the system accent color (decided by the agent).

## Gotchas
- The default folder "Automatically Add to Music" is emptied by Music.app. After that, the file is gone from that path. Double-click then opens the folder instead.
- `yt-dlp` and `ffmpeg` must be installed (`brew install yt-dlp ffmpeg`). Show a clear error if not.
- The app must not be sandboxed, or it cannot run `yt-dlp`.

## Not in version one
- Video download (`download.sh`) and other modules.
- Saving the queue between app launches.
- Parallel downloads, per-item folders, format choice in the UI.
