# AntHill stories

## M1 Core loop: download music from a link

### S-001 Open a module from the sidebar
As the user, I click "YT-Music" in the sidebar and its page shows on the right.
Screens: 01-yt-music.png
Acceptance:
- [snap] The sidebar lists "YT-Music" with a music-note symbol, selected on first launch.
- [unit] The module list comes from one registry array; adding a module is one entry.
UX:
- Sidebar title: "Modules". Row: symbol + module name.
- Selection is remembered between launches.
Status: done

### S-002 Show and hide the sidebar
As the user, I press the sidebar button in the toolbar (or Control-Command-S) to hide or show the sidebar.
Screens: 01-yt-music.png, 02-sidebar-hidden.png
Depends: S-001
Acceptance:
- [snap] With the sidebar hidden, the module page fills the window.
- [manual] The toolbar button and View > Hide Sidebar both toggle it.
UX:
- Standard `NavigationSplitView` toggle; no custom control.
Status: done

### S-003 Add a link and press Return
As the user, I paste a YouTube link into the field at the top and press Return. A new item appears in the queue and starts downloading.
Screens: 01-yt-music.png
Depends: S-001
Acceptance:
- [snap] The field shows placeholder "Paste a YouTube link and press Return".
- [unit] Empty text or text that is not an http(s) URL adds nothing.
- [self] After Return the field is empty and keeps focus.
UX:
- A not-valid link: the field shakes lightly and stays filled. No alert.
Status: done

### S-004 See name and status of each item
As the user, I see each queued item with its name and its status.
Screens: 01-yt-music.png
Depends: S-003
Acceptance:
- [snap] A row shows the title (the link until the title is known) and a status: Waiting, Downloading 42%, Paused, Done, Failed.
- [unit] The parser reads `sd:title`, `sd:pct`, and `sd:file` lines from yt-dlp output.
- [snap] A failed row shows the last yt-dlp `ERROR` line in red, one line.
UX:
- Downloading shows a thin progress bar under the title.
Status: done

### S-005 Pause and resume an item
As the user, I click the pause button on a downloading row. The download stops. I click it again and it goes on.
Screens: 01-yt-music.png
Depends: S-004
Acceptance:
- [manual] The yt-dlp process stops (SIGSTOP) and continues (SIGCONT) from the same point.
- [snap] A paused row shows "Paused" and a play button.
UX:
- Pause/play button only on Waiting, Downloading, and Paused rows.
Status: done

### S-006 Remove an item
As the user, I click the remove button (or press Delete on a selected row) and the item leaves the list.
Screens: 01-yt-music.png
Depends: S-004
Acceptance:
- [unit] Removing a running item stops its process.
- [manual] A finished file stays on disk.
UX:
- No confirm dialog: the file is not deleted.
Status: done

### S-007 Clear finished items
As the user, I click "Clear Finished" above the list and every Done item leaves the list.
Screens: 01-yt-music.png
Depends: S-004
Acceptance:
- [unit] Only Done items go; Failed, Waiting, Downloading, Paused stay.
- [snap] The button is disabled when no item is Done.
Status: done

### S-008 Show a finished file in Finder
As the user, I double-click a Done item. Finder opens with the file selected.
Screens: 01-yt-music.png
Depends: S-004
Acceptance:
- [manual] Finder opens with the file selected.
- [manual] If the file is gone (Music.app took it), Finder opens the download folder.
Status: done

### S-009 Change the download folder
As the user, I click the folder path above the list (or open Settings) and pick a new folder. All next downloads go there.
Screens: 01-yt-music.png, 03-settings.png
Depends: S-003
Acceptance:
- [snap] The current folder shows as a path above the list.
- [unit] The folder is saved and is the same after a restart.
- [snap] Default is "~/Music/Music/Media.localized/Automatically Add to Music.localized".
UX:
- Button "Change…" opens a folder picker (`NSOpenPanel`, folders only).
Status: done

### S-010 Clear message when yt-dlp is missing
As the user, I add a link without yt-dlp installed and see how to fix it.
Screens: 01-yt-music.png
Depends: S-004
Acceptance:
- [snap] The row is Failed: "yt-dlp not found. Install: brew install yt-dlp ffmpeg".
Status: done

## M2 Filesfer: copy, move, or zip files

### S-020 Save a transfer job
As the user, I pick FROM (a file or folder), WHERE, Copy / Cut / Zip and Copy, and what happens when a file exists.
Acceptance:
- [selftest] Jobs and their last result survive a restart.
- [unit] Save is refused when WHERE is inside FROM, FROM and WHERE are the same, FROM is already in WHERE, or the regex is not valid.
Status: done

### S-021 Take only some files
As the user, I take the whole folder, or files by regex, file names, or extensions, from every subfolder.
Acceptance:
- [unit] Filters ignore case, keep the subfolder structure, and never match hidden files. Whole Folder skips .DS_Store and other clutter.
- [snap] Each row shows how many files match and their size.
Status: done

### S-022 Run one job or all, and see progress
Acceptance:
- [selftest] Copy, Keep Both ("a 2.txt"), Overwrite, Cut (empty folders removed), and Zip and Copy work with real rsync.
- [snap] A running row shows a progress bar, percent, and time left (Homebrew rsync).
Status: done

### S-023 Run jobs on a schedule
Acceptance:
- [selftest] Missed runs run once. A job whose drive is away shows "Waiting for <drive>" and runs when it connects.
- A failed scheduled run sends a notification.
Status: done

## Later
- Video download module (`download.sh`).
- Keep the queue between launches.
- Parallel downloads.
- Format choice (m4a / mp3).

## Dropped
- Accounts, sync, sharing: one user, one Mac.
- Per-item download folder: the user asked for one setting for all.
