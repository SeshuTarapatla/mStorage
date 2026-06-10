# mStorage

A Flutter Windows desktop app that hides full-size movies inside ordinary-looking short MP4 clips — a steganographic storage tool for large video files.

The encoded file plays normally in any media player as a 5-second clip (the "mask"), but carries the real movie as an appended binary payload that ordinary players ignore. The companion decoder recovers the original files instantly.

> Native Windows GUI rewrite of the original Python CLI toolset.

---

## How it works

1. **Encode** — takes your movie, a poster image, and an optional subtitle file. Compresses them into an encrypted archive, generates a 5-second mask video from the poster (with spoofed `creation_time` metadata so it sorts correctly in galleries), then concatenates the two into a single `.mp4`.
2. **Decode** — drops the encoded `.mp4`, strips the mask header, and extracts the original archive back into individual files.
3. **Play** — libmpv-powered player with optional Syncplay integration for synchronized watch-together sessions.

The resulting file is a valid MP4: it plays as a short clip in any media player, shows the poster as thumbnail, and passes as a normal gallery item on platforms that inspect only the playable video portion.

---

## Features

### Encode
- Drop video, poster image (auto-detected from same folder), and subtitle file
- Auto-fills title from filename; configurable date/time metadata for the mask clip
- Poster orientation detection — portrait → 1080×1920, landscape → 1920×1080
- File size labels and poster thumbnail preview in drop zones
- Progress pipeline with per-step indicators (mask generation → compression → combine)
- Show output in Explorer when done

### Decode
- Drop any encoded MP4 to extract the hidden archive
- Cancel mid-run
- Extracted files list with file sizes, open-in-Explorer per file
- Play button in the completion banner — jumps directly to the Player with the video loaded

### Player
- libmpv-powered playback with drag-and-drop
- Space bar to play/pause
- Resume last video button
- Syncplay integration — auto-detects installation, launches with configured server/room/port
- Stop Syncplay kills the entire process tree (including the VLC child process)
- Collapsible Syncplay console log

### Catalog
- Paste a Google Sheets URL to load a browsable video catalog
- Masonry grid of cards with poster thumbnails, IMDB ratings, genres, and release dates
- Expand any card for a full detail view with a slideshow, plot, and tags
- Sort by title, date, or rating; filter by language, genre, year, or downloaded status
- Open any entry in an embedded WebView and download directly from the page
- Re-download protection — prompts before overwriting an existing file
- Downloaded indicator (green tick badge) on cards already in your download history
- Download history panel with file size, open-in-Explorer, play, and decode shortcuts
- Queue-based downloader with progress bar and speed readout

### Settings
- Archive encryption password
- Custom encode/decode output directories
- Aspect ratio preservation toggle and mask duration
- Startup page picker with drag-to-reorder sidebar pages
- Syncplay username, room, port
- Danger Zone — reset all settings to defaults

### Shell
- Animated pulsing dot on sidebar while encode or decode is running
- Per-tab accent colours with smooth transitions
- Custom frameless title bar with drag region
- Update notifier — prompts on every launch when a newer release is available

---

## Installation

Download `mStorage_Setup.exe` from the [latest release](../../releases/latest), run it, accept the UAC prompt, and launch from the Start Menu or desktop shortcut. Full uninstaller is registered in **Apps & features**.

**Requirements:** Windows 10 64-bit or later.

---

## Building from source

### Prerequisites
- [Flutter 3.41+](https://docs.flutter.dev/get-started/install/windows/desktop)
- [Inno Setup 6](https://jrsoftware.org/isinfo.php) (only needed to build the installer)

### Steps

```powershell
# 1. Get dependencies
flutter pub get

# 2. (Optional) Regenerate the app icon
flutter test test/generate_icon_test.dart

# 3. Build the Windows executable
flutter build windows --release

# 4. Build the installer (requires iscc in PATH)
iscc installer.iss
# Output: installer\mStorage_Setup.exe
```

---

## Bundled binaries

| Binary | Purpose |
|--------|---------|
| `assets/bin/ffmpeg.exe` | Mask video generation |
| `assets/bin/7za.exe` + DLLs | Archive compression and extraction |

These are extracted to a temp directory at runtime and cleaned up on exit.

---

## License

MIT
