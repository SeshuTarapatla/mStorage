# mStorage — Legacy Project Specification

> **Status:** Legacy / archived. This document is a complete, behavior-faithful
> description of the original Python implementation, written to be fed as
> context into a fresh project (a native **Windows app in Flutter**) that will
> re-implement and modernize this functionality.
>
> Read this top-to-bottom. It covers *what the project does*, *exactly how it
> does it* (down to byte layout and command-line flags), its *edge cases and
> bugs*, and a final section of *implications for the Flutter rewrite*.

---

## 1. What mStorage is (the one-paragraph version)

mStorage is a Windows command-line toolset that **hides a full-size movie file
inside what appears to be an ordinary, tiny MP4 video clip**. It compresses the
real movie (optionally with a subtitle file and a poster image) into a RAR
archive, generates a harmless-looking 5-second "mask" video from a poster image,
and then **concatenates the two into a single `.mp4` file**. The resulting file:

- **Plays** in any normal media player as a 5-second clip (the mask).
- **Carries** the entire real movie as an appended binary payload that ordinary
  players ignore.
- Can be **decoded** back into the original movie + extras by the companion tool.

It also ships a small launcher that plays the recovered video through
**Syncplay** for synchronized watch-together sessions.

### 1.1 The intent (why disguise the movie)

This is the project's actual purpose, stated plainly so the rewrite preserves
the design goals:

- The tool is designed to **store large movies on services that only accept
  short/innocuous media** — e.g., cloud photo/video galleries — by making each
  movie masquerade as a brief, legitimate-looking video clip.
- The **poster image becomes the visible thumbnail / first frame**, so the
  disguised file looks like a real gallery item.
- The **`creation_time` metadata is deliberately spoofed** (user-supplied date
  and time) so the fake clip sorts/appears correctly in a chronological gallery
  rather than showing the encode time.
- The mask is intentionally **short (5 seconds) and standard (1920×1080,
  H.264, yuv420p)** so it passes as a normal clip and stays small on its own;
  the real weight comes from the hidden archive bytes.

In short: **mStorage = "media storage" by steganographic appending** — abuse an
MP4 container's tolerance for trailing bytes to smuggle an archive past systems
that inspect only the playable video.

---

## 2. Repository layout

```
legacy-mStorage/
├── encoder.py          # Hide a movie inside a mask MP4
├── decoder.py          # Recover the movie from a mask MP4
├── player.py           # Launch recovered video via Syncplay
├── build.py            # Compile the three scripts to standalone .exe (Nuitka)
├── bin/
│   └── binaries.json   # Declares required external binaries (not committed)
├── README.md           # One-line description
└── .gitignore          # Standard Python gitignore (Nuitka artifacts ignored)
```

**Important:** the `bin/` directory is expected to contain external binaries at
runtime that are **not in the repo**:

- `bin\ffmpeg.exe` — used by the encoder to build the mask video.
- `bin\rar.exe` — the **WinRAR** CLI, used to compress (encoder) and extract
  (decoder) the archive.

`bin/binaries.json` is purely a manifest of what those binaries are; the code
does **not** read it. It exists as documentation / a placeholder:

```json
{
  "required-binaries": {
    "ffmpeg": "ffmpeg.exe",
    "rar": "rar.exe"
  }
}
```

---

## 3. The core file format (the most important part to replicate)

The encoded output is a single file named `<title>.mp4` with this exact byte
layout:

```
┌─────────────────────────────────────────────┐
│  [ bytes of mask.mp4 ]                        │  ← a real, playable H.264 MP4
├─────────────────────────────────────────────┤
│  0x0A  b r e a k p o i n t  0x0A              │  ← literal separator: "\nbreakpoint\n"
├─────────────────────────────────────────────┤
│  [ bytes of <title>.zip (a RAR archive) ]     │  ← the hidden payload
└─────────────────────────────────────────────┘
```

Key facts:

- The separator token is the literal byte sequence **`\nbreakpoint\n`**
  (newline, the ASCII word `breakpoint`, newline). In Python: `b'\nbreakpoint\n'`.
- The first region is a complete, valid MP4 — that's why standard players play
  it and stop at the end of the moov/mdat without choking on the trailing bytes.
- The second region is a **RAR archive** even though the intermediate file and
  variable are called `.zip`. It is produced by `rar.exe` (WinRAR), so the
  payload is **RAR format**, not PKZIP. The `.zip` naming is a misnomer carried
  throughout the code.
- There is **no length header, no checksum, no magic of its own** — recovery
  relies entirely on locating the `\nbreakpoint\n` separator.

---

## 4. `encoder.py` — encoding pipeline in depth

Class `Encode`. On construction it runs the full pipeline in order:
`get_input()` → `generate_mask_video()` → `generate_zip_file()` →
`generate_output_video()` → `clear_cache()`.

### 4.1 Constants set in `__init__`

| Field | Value | Meaning |
|---|---|---|
| `self.rar` | `bin\rar.exe` | WinRAR CLI path |
| `self.ffmpeg` | `bin\ffmpeg.exe` | ffmpeg path |
| `self.zip` | `cache\<title>.zip` | intermediate RAR archive |
| `self.mask` | `cache\mask.mp4` | intermediate mask video |
| `self.password` | `''` (empty) | RAR password — **hardcoded empty**, with a `#Sample password` comment indicating it's meant to be set |

### 4.2 `get_input()` — interactive prompts

Reads, via `input()`:

1. **Video file** (drag-and-drop; surrounding `"` quotes are stripped). Required.
2. **Title** — defaults to the video's base filename (no extension) if blank.
3. **Date** `YYYY-MM-DD` — defaults to **today** (`datetime.now()`) if blank.
4. **Time** `HH:MM:SS` — defaults to **`07:00:00`** if blank.
5. **Poster** — image path (quotes stripped). Optional *in intent*, but see the
   bug in §4.6.
6. **SRT file** — subtitle path (quotes stripped). Optional.

### 4.3 `generate_mask_video()` — build the disguise clip

- Creates the `cache\` directory (`makedirs('cache', exist_ok=True)`).
- If no poster was given, it calls `generate_mask_frame()` and *intends* to use
  `cache\frame.jpg`. **`generate_mask_frame()` is an empty stub (`pass`)** — see
  §4.6.
- Runs ffmpeg to make a 5-second video from the poster image:

```
bin\ffmpeg.exe -y -loop 1 -i "<poster>" -c:v libx264 -t 5 \
  -pix_fmt yuv420p -vf "scale=1920:1080" \
  -metadata creation_time="<date>T<time>" cache\mask.mp4
```

  - `-loop 1` + `-t 5`: loop the single still image for 5 seconds.
  - `-c:v libx264 -pix_fmt yuv420p`: broadly compatible H.264.
  - `-vf scale=1920:1080`: force 1080p (aspect ratio not preserved — a plain
    stretch/squash to exactly 1920×1080).
  - `-metadata creation_time="<date>T<time>"`: **spoofed capture timestamp**
    (e.g. `2026-06-04T07:00:00`).
  - Run via `subprocess.run(cmd, shell=True, capture_output=True)` — output is
    swallowed; failures are not checked.

### 4.4 `generate_zip_file()` — compress the real payload

Builds a RAR archive of the movie (+ optional extras):

```
bin\rar.exe a -p<password> -ep1 "cache\<title>.zip" "<video>" ["<srt>"] ["<poster>"]
```

- `a` — add to archive.
- `-p<password>` — set password (with empty `self.password`, this is `-p`, i.e.
  effectively no real password).
- `-ep1` — exclude the base folder from stored paths (store file names only,
  not full directory structure).
- The SRT and poster are appended to the command **only if** they were provided.
- Executed via `os.system(cmd)` (so WinRAR's own console output is shown).

### 4.5 `generate_output_video()` — concatenate mask + separator + archive

```python
with open(self.mask, 'rb') as f:        # read whole mask into memory
    mask_data = f.read()
with open(self.title + '.mp4', 'wb') as out:
    with open(self.zip, 'rb') as z:
        out.write(mask_data)
        out.write(b'\nbreakpoint\n')
        # stream the archive in 1 MB chunks
        while chunk := z.read(10**6):
            out.write(chunk)
```

- Output file is `<title>.mp4` in the **current working directory**.
- Mask is read fully into RAM; archive is streamed in 1 MB chunks.
- This is the exact moment the format from §3 is produced.

### 4.6 Known bugs / incomplete behavior in the encoder

- **Empty-poster path is broken.** If the user leaves the poster blank,
  `generate_mask_video()` calls `generate_mask_frame()` which is just `pass`,
  then points ffmpeg at `cache\frame.jpg` which was never created → ffmpeg
  fails, mask video is empty/missing, encode is corrupt. **In practice a poster
  image is required.** The original intent was presumably to auto-extract a
  frame from the source video as the poster when none is supplied — that feature
  was never implemented.
- **No error handling.** ffmpeg and rar failures are not detected; the script
  proceeds regardless.
- **Password is hardcoded empty**, so archives are effectively unencrypted
  despite the `-p` flag.
- **`creation_time` format** is `"<date>T<time>"` with no timezone; ffmpeg may
  interpret/normalize this. Worth verifying against the target gallery service.

### 4.7 Entry point

```python
if __name__ == '__main__':
    system('cls')      # clear console
    mov = Encode()     # run whole pipeline
    system('pause')    # "Press any key to continue"
```

---

## 5. `decoder.py` — decoding pipeline in depth

Class `Decode`. Pipeline: `get_input()` → `extract_zip()` →
`extract_video()` → `clear_cache()`.

### 5.1 `get_input()`

- Prompts for the encoded video file (quotes stripped).
- `self.title` = the file's base name without extension.

### 5.2 Constants

| Field | Value |
|---|---|
| `self.rar` | `bin\rar.exe` |
| `self.zip` | `cache\<title>.zip` |
| `self.password` | `''` (must match whatever the encoder used) |

### 5.3 `extract_zip()` — recover the archive payload

```python
makedirs('cache', exist_ok=True)
with open(self.video, 'rb') as f:
    with open(self.zip, 'wb') as z:
        # first 1 MB chunk, split on the separator, keep everything AFTER it
        chunk = f.read(10**6).split(b'\nbreakpoint\n')[-1]
        z.write(chunk)
        while chunk := f.read(10**6):   # stream the rest verbatim
            z.write(chunk)
```

- Reads the **first 1 MB**, splits on `\nbreakpoint\n`, and writes only the part
  **after** the separator. Then copies the remainder of the file unchanged.
- **Critical assumption / limitation:** the `\nbreakpoint\n` separator **must
  occur within the first 1,000,000 bytes** of the file. The mask video (5s,
  1080p, single still image) is normally small enough that this holds, but it is
  a fragile assumption. If the mask video ever exceeds ~1 MB, decoding silently
  produces a corrupt archive (the split finds no separator, returns the whole
  first chunk as `[-1]`, i.e. raw mask bytes get written into the archive).

### 5.4 `extract_video()` — unpack the archive

```
bin\rar.exe x -y -p<password> "cache\<title>.zip" "<title>"
```

- `x` — extract with full paths.
- `-y` — assume Yes on all prompts.
- `-p<password>` — password (empty by default).
- Extracts into a new folder named `<title>` (created via `makedirs`).
- Run via `os.system`.

### 5.5 `clear_cache()`

Deletes the `cache\` directory (`shutil.rmtree('cache')`). Same helper exists in
the encoder. Note: if `cache\` doesn't exist this raises — but the pipeline
always creates it first.

### 5.6 Entry point

Identical pattern to the encoder: `cls` → `Decode()` → `pause`.

---

## 6. `player.py` — Syncplay launcher

Class `Player`. Pipeline: `check_syncplay_executable()` → `select_video()` →
`start_server()`.

### 6.1 `check_syncplay_executable()`

Looks for **`Syncplay\SyncplayConsole.exe`** under:

1. `%PROGRAMFILES%\Syncplay\SyncplayConsole.exe`
2. `%PROGRAMFILES(x86)%\Syncplay\SyncplayConsole.exe`

If neither exists, prints `Syncplay server executable not found`, pauses, exits.

### 6.2 `select_video()`

- Recursively walks the current directory tree (`os.walk('.')`).
- **Skips** the top dir `.` and `.\bin`.
- Collects files whose extension (lowercased, dot removed) is one of:
  **`mp4`, `mov`, `webp`, `mkv`**. *(Note `webp` is an image format — likely a
  typo/oversight; `webm` was probably intended.)*
- Behavior:
  - 0 videos → error + exit.
  - 1 video → auto-selected.
  - many → prints a numbered menu, asks the user to pick.
- **Selection bug:** out-of-range input is only guarded for `IndexError`. A
  selection of `0` maps to `vids[-1]` (Python negative index → last item) rather
  than being rejected, and non-numeric input raises an unhandled `ValueError`.

### 6.3 `start_server()`

```python
Popen([self.executable, self.video], shell=True)
sys.exit()
```

Launches the Syncplay console server with the chosen video and exits
immediately. This enables a **watch-together / synchronized playback** session.

### 6.4 Note on what gets played

The player points Syncplay at the **encoded `.mp4`** (the masked file), which
plays as the 5-second mask — it does **not** decode the hidden movie. So in the
legacy flow, `player.py` is for playing already-recovered/normal video files
that happen to be in the folder, not the disguised payload. (This coupling is
loose and worth clarifying in the rewrite — see §8.)

---

## 7. `build.py` — packaging

Class `Nuitka`, static `build(file)`:

```
python -m nuitka --onefile "<file>"
```

- Compiles each script to a single standalone `.exe` via **Nuitka** (`--onefile`).
- In a `finally` block, cleans up Nuitka's working dirs:
  `<name>.build`, `<name>.dist`, `<name>.onefile-build`.

Entry point builds all three:

```python
Nuitka.build('decoder.py')
Nuitka.build('encoder.py')
Nuitka.build('player.py')
```

This produces `decoder.exe`, `encoder.exe`, `player.exe`. Note Nuitka does
**not** bundle `bin\ffmpeg.exe` / `bin\rar.exe` / Syncplay — those remain
external runtime dependencies that must ship alongside.

---

## 8. External dependencies summary

| Dependency | Used by | Purpose | Bundled? |
|---|---|---|---|
| `ffmpeg.exe` | encoder | Build the H.264 mask video from poster | No (expected in `bin\`) |
| `rar.exe` (WinRAR CLI) | encoder, decoder | Create / extract the RAR payload | No (expected in `bin\`) |
| Syncplay (`SyncplayConsole.exe`) | player | Synchronized playback server | No (expected installed in Program Files) |
| Python 3.8+ | all | Runtime (uses `:=` walrus; f-strings) | N/A |
| Nuitka | build | Compile to `.exe` | dev-only |

Standard-library-only otherwise: `os`, `sys`, `subprocess`, `shutil`,
`datetime`. No third-party pip packages.

---

## 9. End-to-end worked example

**Encoding:**

1. Run `encoder.exe`. Drag in `Inception.mkv`.
2. Title `Inception`, date `2010-07-16`, time `07:00:00`, poster
   `inception.jpg`, srt `inception.srt`.
3. ffmpeg builds `cache\mask.mp4` (5s, 1080p, fake creation_time
   `2010-07-16T07:00:00`).
4. WinRAR packs `Inception.mkv` + `inception.srt` + `inception.jpg` into
   `cache\Inception.zip` (RAR format).
5. Output `Inception.mp4` = `mask.mp4` + `\nbreakpoint\n` + `Inception.zip`.
6. `cache\` deleted. `Inception.mp4` looks like a 5s clip of the poster but is
   movie-sized; uploads to a gallery as a normal-looking video.

**Decoding:**

1. Run `decoder.exe`. Drag in `Inception.mp4`.
2. Splits off the archive after `\nbreakpoint\n` → `cache\Inception.zip`.
3. WinRAR extracts into `.\Inception\` (the mkv, srt, jpg).
4. `cache\` deleted.

---

## 10. Implications & recommendations for the Flutter (Windows) rewrite

This section translates the legacy behavior into guidance for the new project.

### 10.1 What MUST be preserved (format compatibility)

If the new app needs to **decode files produced by the legacy tool** (and/or
produce files the legacy tool can decode), it must honor the exact format in
§3:

- Separator is the literal `\nbreakpoint\n` (`0x0A 'breakpoint' 0x0A`).
- Layout: `[mask mp4][separator][RAR archive]`, no length header.
- Payload is **RAR**, not ZIP — extraction needs a RAR-capable library/binary.

If backward compatibility is **not** required, strongly consider a more robust
container (see §10.3).

### 10.2 Bugs to fix in the rewrite

- **Auto-poster when none supplied:** implement the never-finished
  `generate_mask_frame()` — extract a representative frame from the source video
  (e.g. ffmpeg `-ss` thumbnail) and use it as the mask/poster.
- **Breakpoint search limited to first 1 MB:** scan the whole header region (or,
  better, store the payload offset/length explicitly) so larger masks decode
  correctly.
- **No error handling:** check ffmpeg/rar exit codes and surface failures in the
  UI.
- **Hardcoded empty password:** expose real, optional encryption (and remember
  encoder/decoder passwords must match).
- **Player extension list:** `webp` is almost certainly a typo for `webm`;
  validate the intended set.
- **Player selection validation:** reject `0`, out-of-range, and non-numeric
  input (the `IndexError`-only guard and negative-index quirk are unsafe).
- **Aspect ratio:** `scale=1920:1080` stretches; consider
  `scale=...:force_original_aspect_ratio` + pad to avoid distorting posters.

### 10.3 Modernization opportunities

- **Replace shelling out to WinRAR** with a bundled archiver. WinRAR/`rar.exe`
  is proprietary and not redistributable; prefer ZIP (with AES) or 7z via a
  library, unless legacy-RAR compatibility is mandatory.
- **Bundle ffmpeg** (FFmpegKit / a vendored binary) or replace the mask-video
  generation with native encoding so the app is self-contained.
- **Add an explicit, self-describing trailer** (magic bytes + version + payload
  length + checksum + original-filename metadata) instead of the fragile
  `\nbreakpoint\n` sniff. Keep an optional "legacy mode" reader for old files.
- **GUI workflow** to replace the three separate console scripts: one app with
  Encode / Decode / Play tabs, drag-and-drop, progress bars, and validation that
  the §4.6 bugs made impossible in the CLI.
- **Decouple the player:** in the legacy tool, `player.py` plays whatever video
  is in the folder via Syncplay and is essentially independent of the
  encode/decode format. Decide whether the new app should (a) decode then play,
  (b) keep Syncplay integration, or (c) drop it. The Syncplay dependency is an
  external install — consider whether watch-together is still in scope.

### 10.4 Platform notes

- Everything is **Windows-only** today: backslash paths, `cls`/`pause`,
  `%PROGRAMFILES(x86)%`, `.exe` binaries. The Flutter target is Windows, so this
  is fine, but keep path handling and binary discovery abstracted in case of
  later cross-platform needs.

---

## 11. Quick reference cheat-sheet

| Thing | Value |
|---|---|
| Output format | `[mask.mp4]` + `\nbreakpoint\n` + `[RAR archive]` |
| Separator bytes | `0x0A 62 72 65 61 6B 70 6F 69 6E 74 0x0A` |
| Mask video | ffmpeg, H.264, yuv420p, 1920×1080, 5 s, looped still image |
| Spoofed metadata | `creation_time="<YYYY-MM-DD>T<HH:MM:SS>"` |
| Default date/time | today / `07:00:00` |
| Archive tool | `bin\rar.exe` (WinRAR), RAR format, `-ep1`, optional `-p<pw>` |
| Chunk size | 1,000,000 bytes (`10**6`) |
| Decoder breakpoint window | first 1 MB only |
| Player backend | Syncplay `SyncplayConsole.exe` (Program Files) |
| Player formats | `mp4`, `mov`, `webp`(sic), `mkv` |
| Build | `python -m nuitka --onefile <script>` |
| External deps | ffmpeg.exe, rar.exe, Syncplay (none bundled) |
```
