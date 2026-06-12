# mStorage — Improvement Report

A full-project audit focused on **performance, responsiveness, functionality, and UX depth**.
This complements `docs/ux-improvements.md` (the v1.1 animation-polish pass, now largely
implemented) — nothing here duplicates that document. Items reference actual code locations
so they can be picked up directly into a release plan (`QUERY.md` → `feat/vX.Y.Z`).

Priority: **P1** = correctness / clearly felt by the user · **P2** = solid improvement ·
**P3** = nice-to-have.
Effort: **S** (< ½ day) · **M** (½–1 day) · **L** (multi-day).

---

## 1. Performance & Responsiveness (highest impact)

### 1.1 Decode blocks the UI thread with synchronous file I/O  `P1 / M`
`FormatService.extractArchive` (`lib/core/services/format_service.dart`) scans the whole
encoded file with `readSync` in a loop **on the main isolate**. For a 4–8 GB movie this
freezes the entire window (no animations, no cancel button response) for the duration of
the breakpoint search + payload copy. The decode "Splitting" spinner is frozen exactly
when it matters most.

**Fix:** Run the entire scan/copy inside `Isolate.run(...)` (it's already a static method
with plain-path inputs — a 5-line change), or switch to async `openRead()` streaming.
While there:
- `Uint8List.fromList([...tail, ...chunk])` copies ~1 MB per iteration — search the chunk
  directly and only stitch the boundary region (`tail + first 12 bytes of chunk`).
- `_findSeparator` is a naive O(n·m) scan; fine once it's off the UI thread, but a
  first-byte `indexOf` skip makes it ~10× faster for free.

### 1.2 Encrypted encode can balloon memory to the size of the movie  `P1 / S`
`ArchiveService._createEncryptedZip` (`archive_service.dart:209-219`) pumps file chunks
into `process.stdin.add(chunk)` **without awaiting backpressure**. `IOSink.add` is
fire-and-forget — if 7za consumes stdin slower than the disk reads (always true while it
encrypts), the unwritten chunks accumulate in Dart heap. Encoding a 6 GB movie with a
password can climb to gigabytes of RAM.

**Fix:** `await process.stdin.flush()` periodically, or pipe via
`addStream` with a progress-counting `StreamTransformer`. Also throttle `onProgress`
here the same way the unencrypted path does (it currently fires per chunk → hundreds of
state updates/sec → needless rebuilds).

### 1.3 Pure-Dart CRC32 ZIP writer should run in an isolate  `P1 / S`
The unencrypted path (`createZip`) computes CRC-32 byte-by-byte in Dart on the main
isolate. It yields between chunks (so no hard freeze), but a multi-GB encode keeps the UI
janky and is CPU-bound single-threaded. Wrap the whole STORE-writer body in
`Isolate.run` and forward progress through a `ReceivePort` / `Stream`.

### 1.4 Encode + decode share (and delete) the same temp directory — race  `P1 / S`
Both `encode_notifier.dart` and `decode_notifier.dart` use
`%TEMP%/mstorage_cache` and **delete it recursively** when they finish. Running a decode
while an encode is in flight (both are allowed — separate tabs, both have running states)
will destroy the other job's intermediate files mid-run.

**Fix:** Create a unique subdirectory per job
(`mstorage_cache/<uuid>`), delete only that. Also wrap cleanup in try/catch — today a
locked file during `cacheDir.delete(recursive: true)` fails the whole encode *after* the
output was already written successfully.

### 1.5 Sync disk I/O inside `build()` — Downloads list & drop zones  `P1 / M`
- `_DownloadsListView` (`catalog_screen.dart`) calls `Directory(...).listSync()` and
  `File(...).existsSync()` **per row, per rebuild** — and it rebuilds every 300 ms while a
  download is active (progress ticks). With 50+ history records on a HDD this stutters.
- `FileDropZone._sizeLabel` calls `File(path).lengthSync()` on every rebuild of the
  encode screen.

**Fix:** Resolve file existence / decoded-path / size once when the data changes (a small
`FutureProvider.family` or a cached map keyed by `filePath` invalidated on
refresh/delete), not in `build`.

### 1.6 Hidden tabs keep doing layout work and running animations  `P2 / S`
`AppShell` keeps all six screens mounted via `Opacity(opacity: 0)`
(`app_shell.dart:237-244`). `Opacity(0)` skips painting but **not layout**, and repeating
`flutter_animate` loops (catalog empty-state pulse, sidebar running-dot) keep ticking in
invisible tabs. The catalog grid (potentially hundreds of cards) re-layouts on every
window resize even while you're on the Encode tab.

**Fix:** Replace the invisible branch with `Offstage(offstage: true, child: TickerMode(enabled: false, ...))`.
Same state-preservation guarantee, zero layout/ticker cost. (Note: if background video
playback while on other tabs is *intended* for the Player tab, keep Player on the
`Offstage`-only path — `TickerMode` off would freeze its controls but not the audio.)

### 1.7 Catalog first load waits on IMDB before showing anything  `P1 / M`
`CatalogNotifier._buildEntries` awaits `ImdbService().resolve(imdbIds)` **before**
emitting `CatalogLoaded`. On a fresh install (cold IMDB cache) with a 100-row sheet
that's 20 sequential batch requests (batches of 5, awaited in a serial loop) — easily
10–20 s of spinner for data the user doesn't need to start browsing.

**Fix (two parts):**
1. Emit `CatalogLoaded(rawEntries)` immediately after CSV parse, then merge IMDB data
   into state as batches resolve (the UI already handles missing ratings gracefully).
2. Fetch batches concurrently with a small cap: `Future.wait` over 3–4 batches at a time
   instead of strictly serial.

### 1.8 Downscale decoded poster images for grid cards  `P2 / S`
Catalog cards are ≤ 200 px wide but `CachedNetworkImage` decodes posters at full
resolution (IMDB originals can be 2000+ px). Set `memCacheWidth: 400` (2× for DPR) on the
grid/list thumbnails — typically cuts image memory by 10–20× and noticeably speeds up
first-scroll of a large catalog.

### 1.9 No timeout on catalog CSV fetch  `P2 / S`
`http.get(csvUrl)` in `catalog_notifier.dart` has no `.timeout(...)`. A hung connection
leaves the catalog on the loading spinner forever with no retry path. Add a 15 s timeout
+ map it to the friendly error state (the IMDB service already does this correctly).

### 1.10 Debounce catalog search  `P3 / S`
Every keystroke refilters + re-sorts the full list and rebuilds the masonry grid
(`onSearch: (v) => setState(...)`). Fine at 100 entries; visible at 500+. A 150–200 ms
debounce (or at least moving filter+sort out of `_Body.build` into a memoized provider
keyed by query/filter inputs) keeps typing smooth and removes redundant work.

---

## 2. Functional gaps — Encode / Decode

### 2.1 Encode cannot be cancelled  `P1 / M`
Decode has a cancel button and kills the 7za process; **encode has nothing**. A wrong
file selection at the start of a 10-minute encode means waiting it out or killing the
app. Keep handles to the ffmpeg process and zip job, add a `cancel()` to
`EncodeNotifier` mirroring `DecodeNotifier.cancel()`, and surface the same "Cancel"
header button the Decode screen already has.

### 2.2 Encode silently overwrites existing output  `P1 / S`
`FormatService.combine` opens `<outputDir>/<title>.mp4` with `openWrite()` — an existing
encode with the same title is destroyed without warning. Check existence in `_runEncode`
and show the same "already exists — overwrite?" dialog pattern used by catalog downloads.

### 2.3 Date/Time fields are unvalidated free text  `P2 / S`
`_dateCtrl` / `_timeCtrl` feed straight into ffmpeg's `creation_time` metadata. A typo
("2025-13-1") produces a malformed timestamp with zero feedback. Either add inline
validation (regex + red border) or replace with `showDatePicker` / `showTimePicker`
field taps — pickers are the better UX and remove the failure mode entirely.

### 2.4 ffmpeg mask generation progress is indeterminate  `P2 / M`
Step 1 of the pipeline shows only a spinner. ffmpeg supports `-progress pipe:1`
(key=value lines incl. `out_time_ms`); with the known target duration you can show a
real percentage like the other two steps. Use `Process.start` instead of `Process.run`
in `FfmpegService.generateMaskVideo` — this is also a prerequisite for 2.1 (cancel).

### 2.5 Decode extraction progress  `P2 / M`
The "Unpacking" step is also indeterminate. 7za prints percentages with `-bsp1`
(`x archive -bsp1 ...` → stdout lines like ` 23%`). The process handle already exists in
`DecodeNotifier` — parse stdout and feed a progress value into the existing step UI.

### 2.6 Auto-delete of the source file after decode should be opt-in  `P1 / S`
`decode_screen.dart:97-109` permanently deletes the encoded source file the moment decode
succeeds — hardcoded, no setting, no undo. If extraction produced garbage (wrong password
edge cases, partial disk), the original is already gone. Add a Settings toggle
("Delete encoded file after successful decode", default **off** — or on, but visible),
and consider `Recycle Bin` semantics instead of hard delete.

### 2.7 Wrong-password failures surface as raw 7za stderr  `P2 / S`
Decoding with a wrong/missing password shows `Extraction failed: <7za dump>`. 7za's
output contains recognizable markers ("Wrong password", "ERROR: CRC Failed ... Wrong
password?"). Detect them and show a human message — "Incorrect password — check
Settings → Password" — with a button that jumps to Settings (the pattern already exists
in `PasswordWarningBanner`).

### 2.8 Free-disk-space preflight  `P3 / S`
Encode needs roughly 2× the movie size (zip in temp + final output); decode similar.
Running out of space mid-job currently dies with a raw filesystem exception. A cheap
preflight (`GetDiskFreeSpaceEx` via the already-imported `win32` package) with a clear
warning is much friendlier.

### 2.9 Batch encode queue  `P3 / L`
Encoding a season of files is currently fully manual, one at a time. The download side
already has a clean queue implementation (`DownloadNotifier`) — the same pattern applied
to encode (drop N videos → queued with shared settings, sidebar badge shows count) is
the single biggest workflow improvement for heavy users.

---

## 3. Player — biggest UX headroom in the app

### 3.1 Fixed 320 px video area; no fullscreen  `P1 / M`
For an app whose end goal is *watching movies*, the player renders in a fixed
320-px-tall box (`_VideoArea`, `player_screen.dart:428`) inside a scroll view, with no
way to enlarge it. media_kit ships fullscreen support
(`MaterialDesktopVideoControlsTheme`, `toggleFullscreen`).

**Fix:** Make the video area `Expanded` (fill available height, letterboxed), add a
fullscreen toggle button + `F` key + double-click-to-fullscreen, `Esc` to exit.

### 3.2 Resume playback position, not just last file  `P2 / M`
`lastVideoPath` is persisted but always restarts at 0:00. Persist
`player.state.position` (throttled, e.g. every 5 s + on close) keyed by file path, and
make "Resume" actually resume — with a small "start over" alternative.

### 3.3 Keyboard coverage  `P2 / S`
Only Space is handled. Standard desktop-player keys are cheap to add to the existing
`_handleKeyEvent`: `←/→` seek ±10 s, `↑/↓` volume, `M` mute, `F` fullscreen. Persist
volume in settings (it currently resets every session).

### 3.4 Auto-load sibling/extracted subtitles  `P2 / S`
Decode extracts `<title>.srt` next to the movie, but opening the file in the player
doesn't attach it (mpv only auto-loads exact-name matches in some configs). On
`_openVideo`, scan the file's directory for `srt/ass/vtt` and add via
`player.setSubtitleTrack(SubtitleTrack.uri(...))`, plus a small CC button to pick among
multiple.

### 3.5 Tab-switch playback is invisible  `P3 / S`
Because all tabs stay mounted, video/audio keeps playing when you switch tabs with no
indication or control. Either pause on tab-leave (setting), or reuse the sidebar
"running" pulse dot on the Player tab while `player.state.playing` — one `ref.watch`
in `_Sidebar`.

---

## 4. Catalog & Downloads

### 4.1 Download queue robustness: one failure kills the whole queue  `P1 / M`
In `DownloadNotifier._processQueue`, any job exception does `_queue.clear()` and stops.
A transient network blip on file 1 of 5 cancels the other 4 silently. Per-job try/catch:
record the failure (title + reason), continue the queue, and show a summary
("3 done, 1 failed — Retry"). A retry button on `DownloadError` is the matching quick win.

### 4.2 Partial files left on disk after failure  `P1 / S`
Cancel deletes the partial file, but an *error* path does not — a failed 2 GB download
leaves a corrupt `.mp4` in the download dir that then shows up as playable/decodable.
Delete (or `.part`-suffix during transfer, rename on success — also fixes 4.3).

### 4.3 Filename collisions overwrite silently  `P2 / S`
The "already downloaded" check only consults *history*; a file present on disk but not
in history (or two catalog entries sharing a filename) is clobbered. Check
`File(...).existsSync()` at the sink-open site and de-dupe (`name (1).mp4`) or prompt.

### 4.4 Keyboard shortcuts exist but are undiscoverable  `P2 / S`
`D` toggles downloads, `F5` refreshes, `Esc`/`Backspace` navigate back, `←/→` browse the
expanded card — none of this is shown anywhere. Add a small `?`-key overlay (or a hint
row in the empty states / tooltip on the toggle buttons) listing them. Cheap, and these
shortcuts are genuinely good once known.

### 4.5 Sheet URL error feedback before the spinner  `P3 / S`
Pasting a non-Sheets URL gives the generic error state only after a load attempt.
Validate the `/spreadsheets/d/<id>` pattern in `onSubmitUrl` and shake/red-border the
field immediately.

### 4.6 Downloads view: sort + total size  `P3 / S`
History is fixed newest-first with no total. A header line ("23 files · 41.2 GB") and a
date/size/title sort toggle reuse the catalog's existing sort-bar patterns.

### 4.7 Open Downloads folder shortcut  `P3 / S`
A single "open downloads folder in Explorer" icon button next to the Downloads toggle
saves the most common round trip. (`Process.run('explorer.exe', [dir])` is already used
elsewhere.)

---

## 5. App shell & system integration

### 5.1 Remember window bounds  `P2 / S`
The app opens 1100×740 centered every launch. Persist size/position/maximized via
`window_manager` (`onWindowResized`/`onWindowMoved` → settings) and restore in `main()`.
Standard desktop expectation.

### 5.2 Title bar: double-click to maximize + correct restore icon  `P2 / S`
The custom title bar drags but doesn't toggle maximize on double-click (a hardwired
Windows habit), and the maximize button always shows `crop_square` even when maximized
(should swap to a "restore" glyph via `onWindowMaximize`/`onWindowUnmaximize` listeners).

### 5.3 Cross-tab completion notifications  `P2 / M`
Long operations finish invisibly if you're on another tab — encode done, download done,
decode done all render banners only inside their own screens (the sidebar dot just stops
pulsing). Add a lightweight in-app toast (top-right overlay, accent-colored per source
tab, click → jump to tab). Optionally a Windows tray/toast notification when the window
is minimized — `windows_notification` or `local_notifier` are small deps.

### 5.4 Single-instance guard  `P3 / S`
Two app instances can run simultaneously and fight over the temp cache dir, settings
file, and download history. `windows_single_instance` (or a named mutex via `win32`)
plus focusing the existing window is the standard fix.

### 5.5 File associations / "Open with" entry  `P3 / M`
Registering the app for `.mp4` "Open with" (via the Inno Setup script) and handling the
file-path command-line arg (`main(List<String> args)` → route to Decode or Player) makes
the encode/decode loop dramatically faster for daily use.

---

## 6. Security & robustness (worth knowing, even for a personal tool)

### 6.1 Password is passed on the 7za command line  `P2 / S`
`-p$password` (both in `ArchiveService` and `DecodeNotifier`) is visible to any process
listing tools while 7za runs. 7-Zip has no stdin-password mode, but you can avoid the
exposure for *decode* by extracting with `-p` via an environment-variable-free response…
in practice the pragmatic options are: accept it (single-user machine), or document it.
At minimum, stop **interpolating the password into the args list that gets logged in
error messages** — `Extraction failed: ${stderr}` currently never echoes it, but
`Exception('7za encryption failed ...')` paths should be audited to keep it that way.

### 6.2 Password stored in plaintext SharedPreferences  `P3 / S`
`shared_preferences` writes it to an unencrypted file under AppData. On Windows,
`flutter_secure_storage` (DPAPI-backed) is a drop-in for just the password key.

### 6.3 Updater: no integrity check on the downloaded installer  `P3 / S`
`update_service.dart` downloads over HTTPS from GitHub releases (good) but doesn't
verify size or hash before `Process.start`. Publishing a `.sha256` asset alongside the
installer and checking it is cheap insurance against truncated downloads (the current
failure mode would be a cryptic installer error).

---

## 7. Code health (keeps future releases fast)

| Item | Where | Why |
|---|---|---|
| Split the two 2,300-line screens | `catalog_screen.dart` (2,376), `admin_screen.dart` (2,361) | Each holds 15+ private widget classes; extraction into `widgets/` files (pattern already exists for `catalog_card.dart`) makes every future change cheaper. `P2/M` |
| Deduplicate the primary action button | `_EncodeButton`, `_DecodeButton`, `_VlcButton`, `_SyncplayButton` | Four near-identical hover/press/gradient implementations → one `PrimaryButton` in `shared_widgets.dart`. `P3/S` |
| Deduplicate the done-banner | `_DoneBanner` (encode), `_DecodeDoneBanner`, `_DoneDownload` | Same layout, three copies. `P3/S` |
| Duplicated `@override` | `decode_screen.dart:90-91` | Harmless but sloppy; lint should have caught it. `P3/S` |
| Markdown stylesheet copies | `app_shell.dart:_mdStyle` vs `settings_screen.dart:_showChangelog` | Same stylesheet built twice — move to `app_theme.dart`. `P3/S` |
| Raw `e.toString()` in user-facing errors | encode/decode notifiers | Map common cases (file gone, access denied, disk full) to friendly text; keep details behind a "copy details" action. `P2/S` |
| Tests | `test/` has only the icon generator + template widget test | The pure logic is very testable: `FormatService` separator scan (incl. boundary-straddling separators), `ArchiveService` ZIP writer (validate with `archive` package read-back), `UpdateService.isNewer`, catalog CSV parsing/filtering. These guard the *format compatibility promise* that the whole app rests on. `P1/M` |

---

## 8. Suggested release grouping

**v1.4 — "Fast & unbreakable" (perf + correctness core)**
- 1.1 decode off the UI thread · 1.2 stdin backpressure · 1.3 zip isolate
- 1.4 temp-dir race · 2.1 encode cancel · 2.2 overwrite guard · 2.6 auto-delete opt-in
- 4.1/4.2 download queue resilience + partial-file cleanup
- 7 tests for `FormatService`/`ArchiveService` (protects the legacy format promise)

**v1.5 — "Player that feels like a player"**
- 3.1 fullscreen + expanded video area · 3.2 resume position · 3.3 keyboard · 3.4 subtitles
- 5.1 window bounds · 5.2 title-bar double-click

**v1.6 — "Catalog at scale"**
- 1.7 progressive IMDB merge · 1.8 memCacheWidth · 1.5 async downloads-list checks
- 1.9 fetch timeout · 1.10 search debounce · 4.4 shortcut discoverability · 4.6 downloads sort

**v1.7 — "Workflow & integration"**
- 5.3 cross-tab toasts · 2.4/2.5 real progress for ffmpeg/7za · 2.3 date/time pickers
- 2.9 batch encode · 5.4 single instance · 5.5 file associations

---

*Generated 2026-06-12 from a full read of `lib/` at v1.3.0 (`160a361`).*
