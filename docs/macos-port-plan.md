# macOS Port Plan for mStorage

## Context
mStorage is a Flutter desktop app targeting Windows 10+ exclusively. It uses Win32 APIs, Windows-only binary assets (ffmpeg.exe, 7za.exe), and hardcoded Windows paths throughout. This plan covers every change needed to make it build and run on macOS, organized by difficulty and sequenced so the easy wins don't get blocked by the hard parts.

---

## What You Need (Since You Don't Have a Mac)

| Tool | Purpose | How to Get |
|---|---|---|
| **GitHub Actions `macos-latest` runner** | Build & test on real macOS | Free with GitHub — just add a workflow file |
| **Apple Developer Account ($99/year)** | Code-sign for Gatekeeper-free distribution | Optional for v1 — users can right-click → Open |
| **`create-dmg`** | Build the DMG installer | Installed via `brew` in CI |
| **macOS ffmpeg binary** | Replace ffmpeg.exe | Downloaded from evermeet.cx in CI |
| **macOS 7-zip binary (`7zzs`)** | Replace 7za.exe | Downloaded from 7-zip.org in CI |

You don't need a physical Mac for any of this — GitHub Actions does all macOS builds. For smoke testing, anyone with a Mac can download the CI artifact.

---

## Change 1: GitHub Actions CI Workflow (new file)

Create `.github/workflows/build_macos.yml`:

```yaml
name: Build macOS
on:
  workflow_dispatch:
  push:
    tags: ['v*']

jobs:
  build-macos:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable

      # Generate the macos/ runner directory
      - run: flutter create --platforms=macos .

      # Download macOS binaries (never commit these to git)
      - run: |
          curl -L "https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip" -o ffmpeg.zip
          unzip -o ffmpeg.zip -d /tmp/ffmpeg && cp /tmp/ffmpeg/ffmpeg assets/bin/ffmpeg
          chmod +x assets/bin/ffmpeg

      - run: |
          curl -L "https://www.7-zip.org/a/7z2409-mac.tar.xz" -o 7z.tar.xz
          tar -xf 7z.tar.xz && cp 7zzs assets/bin/7zzs
          chmod +x assets/bin/7zzs

      - run: flutter pub get
      - run: flutter build macos --release

      - name: Package DMG
        run: |
          brew install create-dmg
          create-dmg \
            --volname "mStorage" \
            --window-size 800 400 \
            --icon-size 100 \
            --icon "mStorage.app" 200 190 \
            --app-drop-link 600 185 \
            "installer/mStorage_macOS_v$(grep version pubspec.yaml | head -1 | cut -d' ' -f2).dmg" \
            "build/macos/Build/Products/Release/mStorage.app"

      - uses: actions/upload-artifact@v4
        with:
          name: mStorage-macOS
          path: installer/*.dmg
```

---

## Change 2: pubspec.yaml — Add macOS media kit library

File: `/home/user/mStorage/pubspec.yaml` line 23

```yaml
# Add alongside the existing Windows line:
media_kit_libs_macos_video: ^1.0.9
```

The `win32` and `ffi` packages stay — they compile fine on macOS as long as the imports are isolated (see Change 3).

---

## Change 3: Fix `key_injector.dart` — Isolate Win32 Imports

**This is the one change that blocks macOS compilation.** The top-level `import 'package:win32/win32.dart'` fails to compile on macOS.

Split into 3 files:

**`lib/core/util/key_injector.dart`** — replace entire file with conditional export:
```dart
export 'key_injector_stub.dart'
    if (dart.library.io) 'key_injector_impl.dart';
```

**`lib/core/util/key_injector_stub.dart`** — no-op stub:
```dart
class KeyInjector {
  static void sendShiftD() {}
}
```

**`lib/core/util/key_injector_impl.dart`** — move all existing Win32 code here, add macOS CGEvent branch:
```dart
import 'dart:ffi';
import 'dart:io' show Platform;
import 'package:ffi/ffi.dart';
// win32 import only used in Windows branch — guarded at runtime
import 'package:win32/win32.dart';

class KeyInjector {
  static void sendShiftD() {
    if (Platform.isWindows) { /* existing Win32 code unchanged */ }
    // macOS: silently no-op for v1 (CGEvent can be added later)
    // if (Platform.isMacOS) { _sendShiftDMacOS(); }
  }
}
```

> The macOS CGEvent FFI implementation (CoreGraphics `CGEventCreateKeyboardEvent` + `CGEventPost`) can be added in a follow-up. The `if (!Platform.isWindows) return;` guard in the current code means the feature just silently does nothing on macOS — acceptable for v1.

---

## Change 4: Fix Binary Path Resolution

**`lib/core/services/ffmpeg_service.dart`** — lines 12, 15:
```dart
// Replace hardcoded 'ffmpeg.exe' with:
final binaryName = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
final dest = p.join(dir.path, 'bin', binaryName);
if (!File(dest).existsSync()) {
  await Directory(p.dirname(dest)).create(recursive: true);
  final data = await rootBundle.load('assets/bin/$binaryName');
  await File(dest).writeAsBytes(data.buffer.asUint8List());
  if (!Platform.isWindows) await Process.run('chmod', ['+x', dest]);
}
```

**`lib/core/services/archive_service.dart`** — lines 14–27:
```dart
// Replace hardcoded '7za.exe' with:
final binaryName = Platform.isWindows ? '7za.exe' : '7zzs';
final dest = p.join(dir.path, 'bin', binaryName);
if (!File(dest).existsSync()) {
  await Directory(p.dirname(dest)).create(recursive: true);
  final data = await rootBundle.load('assets/bin/$binaryName');
  await File(dest).writeAsBytes(data.buffer.asUint8List());
  if (!Platform.isWindows) await Process.run('chmod', ['+x', dest]);
  // DLLs are Windows-only
  if (Platform.isWindows) { /* existing DLL extraction code unchanged */ }
}
```

---

## Change 5: Fix `Process.run` Explorer Calls (5 locations)

All `explorer.exe` / `explorer` calls need macOS equivalents. Pattern: `open` for folder, `open -R` for reveal-in-finder.

| File | Line | Windows | macOS replacement |
|---|---|---|---|
| `lib/features/catalog/catalog_screen.dart` | 986, 1369 | `explorer.exe [dir]` | `open [dir]` |
| `lib/features/encode/encode_screen.dart` | 574 | `explorer /select, [path]` | `open -R [path]` |
| `lib/features/decode/decode_screen.dart` | 408 | `explorer [dir]` | `open [dir]` |
| `lib/features/decode/widgets/extracted_files_list.dart` | 136 | `explorer /select, [path]` | `open -R [path]` |

Suggested helper to add once (e.g. in a `platform_utils.dart`):
```dart
Future<void> revealInExplorer(String path, {bool isFile = false}) {
  if (Platform.isWindows) {
    return isFile
        ? Process.run('explorer', ['/select,', path])
        : Process.run('explorer.exe', [path]);
  }
  return Process.run('open', isFile ? ['-R', path] : [path]);
}
```

---

## Change 6: Fix PlayerScreen — Syncplay/VLC Paths + Process Kill

**`lib/features/player/player_screen.dart`**

Lines 121–123 (Syncplay paths) — make platform-aware:
```dart
final paths = Platform.isWindows ? [
  p.join(appDir, 'syncplay', 'SyncplayConsole.exe'),
  r'C:\Program Files\Syncplay\SyncplayConsole.exe',
  r'C:\Program Files (x86)\Syncplay\SyncplayConsole.exe',
] : [
  '/Applications/Syncplay.app/Contents/MacOS/syncplay',
  p.join(Platform.environment['HOME'] ?? '', 'Applications', 'syncplay'),
];
```

Lines 138–139 (VLC paths):
```dart
final paths = Platform.isWindows ? [
  r'C:\Program Files\VideoLAN\VLC\vlc.exe',
  r'C:\Program Files (x86)\VideoLAN\VLC\vlc.exe',
] : [
  '/Applications/VLC.app/Contents/MacOS/VLC',
];
```

Line 186 (`taskkill`):
```dart
if (Platform.isWindows) {
  await Process.run('taskkill', ['/F', '/T', '/PID', '${_syncplayProcess!.pid}']);
} else {
  _syncplayProcess!.kill(); // dart:io Process.kill()
}
```

---

## Change 7: Default Directory Path

**`lib/core/services/settings_service.dart`** — `_mStorageBase()`:
```dart
String _mStorageBase() {
  final home = Platform.environment['HOME'] ??
               Platform.environment['USERPROFILE'] ?? '';
  final mediaFolder = Platform.isMacOS ? 'Movies' : 'Videos';
  return p.join(home, mediaFolder, 'mStorage');
}
```

---

## Change 8: Updater — Platform-Aware Asset Filter

**`lib/features/updater/update_service.dart`** — lines 61, 72, 101:
```dart
final ext = Platform.isWindows ? '.exe' : Platform.isMacOS ? '.dmg' : '.tar.gz';
final asset = assets.firstWhere(
  (a) => (a['name'] as String? ?? '').endsWith(ext),
  orElse: () => {},
);
```

**`lib/features/updater/update_notifier.dart`** — line 27:
```dart
// Replace '.exe' error message:
if (info.assetUrl.isEmpty) throw Exception('No installer asset found for this platform');
```

Update installer launch in `update_service.dart` for macOS:
```dart
if (Platform.isMacOS) {
  await Process.run('open', [installerPath]); // opens DMG in Finder
} else {
  await Process.start(installerPath, [], mode: ProcessStartMode.detached);
}
```

---

## Change 9: macOS Runner Config (generated by CI)

The `macos/` directory is **auto-generated** by `flutter create --platforms=macos .` in CI — no manual porting of the Win32 C++ code needed.

After generation, two manual edits are needed in CI or committed to the repo once generated:

**`macos/Runner/Release.entitlements`** — add required capabilities:
```xml
<key>com.apple.security.network.client</key><true/>
<key>com.apple.security.files.user-selected.read-write</key><true/>
<key>com.apple.security.files.downloads.read-write</key><true/>
```

**`macos/Runner/Info.plist`** — add if using KeyInjector later:
```xml
<key>NSAccessibilityUsageDescription</key>
<string>mStorage needs accessibility access to send keyboard shortcuts to the browser for triggering downloads.</string>
```

---

## Implementation Order

**Phase 1 — Get it to compile** (do first, unblocks everything):
1. Change 3 (key_injector split) — compilation blocker
2. Change 2 (pubspec.yaml media_kit_libs_macos_video)
3. Change 4 (ffmpeg + 7zip binary names)
4. Change 1 (GitHub Actions workflow) — confirms compilation on macOS

**Phase 2 — Runtime correctness**:
5. Change 5 (explorer → open)
6. Change 6 (Syncplay/VLC paths, taskkill)
7. Change 7 (default directory)
8. Change 8 (updater asset filter)

**Phase 3 — Polish**:
9. Change 9 (entitlements — after first CI build confirms what's needed)
10. Add app icon `.icns` via `flutter_launcher_icons` package with `macos: true`
11. Add `scripts/reset_update_dismiss.sh` bash equivalent

---

## Difficulty Summary

| Change | Difficulty |
|---|---|
| pubspec.yaml media_kit addition | Trivial |
| explorer → open (5 files) | Easy |
| taskkill → kill | Easy |
| Default directory (Movies vs Videos) | Easy |
| Binary names (ffmpeg.exe → ffmpeg) | Easy |
| Syncplay/VLC paths | Easy |
| Updater asset filter | Easy |
| GitHub Actions workflow | Medium |
| key_injector conditional import split | Medium — must not break Windows |
| macOS entitlements | Medium-Hard — wrong values cause silent runtime failures |
| DMG installer creation | Medium |
| KeyInjector CGEvent (macOS Shift+D) | Hard + deferred — needs Accessibility permission |
| Code signing / notarization | Very Hard + Optional — needs Apple Developer account |

---

## Verification

1. Push the workflow file → check Actions tab for a green build
2. Download the `.app` artifact → open on any Mac to verify basic launch
3. Encode + decode a test video on macOS to verify ffmpeg and 7zzs work
4. Confirm `~/Movies/mStorage` is created as default directory
5. Open-in-Finder buttons reveal correct files
6. Updater finds `.dmg` on GitHub releases page
