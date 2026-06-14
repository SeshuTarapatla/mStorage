import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';
import '../../core/providers/player_request_provider.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tab_colors.dart';
import '../shell/app_shell.dart';
import '../shell/widgets/shared_widgets.dart';

const _kVideoExts = ['mp4', 'mkv', 'mov', 'avi', 'webm'];
const _kSubtitleExts = ['srt', 'ass', 'vtt'];

bool _isVideoFile(String path) =>
    _kVideoExts.contains(path.split('.').last.toLowerCase());

// Module-level singletons survive Flutter hot restart, preventing the
// "Callback invoked after it has been deleted" crash in media_kit's
// native texture layer.
final _sharedPlayer = Player();
final _sharedController = VideoController(
  _sharedPlayer,
  configuration: const VideoControllerConfiguration(
    enableHardwareAcceleration: true,
    // Cap the output texture at FHD — the window is never 4K wide, and this
    // cuts texture-upload bandwidth by 4× for 4K sources (most impactful fix
    // for high-bitrate HEVC 60fps videos that stutter in windowed players).
    width: 1920,
    height: 1080,
  ),
);
bool _mpvConfigured = false;

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  final _palette = AppTab.player.palette;

  Player get _player => _sharedPlayer;
  VideoController get _controller => _sharedController;

  late final TextEditingController _usernameCtrl;
  late final TextEditingController _roomCtrl;

  String? _videoPath;
  bool _syncplayFound = false;
  String? _syncplayPath;
  String? _vlcPath;
  Process? _syncplayProcess;
  final List<String> _syncplayLogs = [];
  bool _showLogs = false;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  StreamSubscription<bool>? _playingSub;

  List<String> _availableSubtitles = [];
  String? _activeSubtitle;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _usernameCtrl = TextEditingController(text: settings.syncplayUsername);
    _roomCtrl = TextEditingController(text: settings.syncplayRoom);
    _checkSyncplay();
    _checkVlc();
    if (!_mpvConfigured) {
      _mpvConfigured = true;
      _configureForHighRes();
    }
    _initVolume();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);

    // Mirror playing state into a provider so the sidebar dot can react.
    _playingSub = _sharedPlayer.stream.playing.listen((playing) {
      if (mounted) ref.read(playerPlayingProvider.notifier).state = playing;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final path = ref.read(playerOpenRequestProvider);
      if (path != null) {
        ref.read(playerOpenRequestProvider.notifier).state = null;
        _openVideo(path);
      }
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _playingSub?.cancel();
    ref.read(playerPlayingProvider.notifier).state = false;
    _player.stop();
    _usernameCtrl.dispose();
    _roomCtrl.dispose();
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    super.dispose();
  }

  Future<void> _initVolume() async {
    final vol = ref.read(settingsProvider).playerVolume;
    try { await _player.setVolume(vol); } catch (_) {}
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (_videoPath == null) return false;
    if (FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<TextField>() != null) {
      return false;
    }

    final key = event.logicalKey;
    final isRepeat = event is KeyRepeatEvent;

    if (key == LogicalKeyboardKey.space && !isRepeat) {
      _player.playOrPause();
      return true;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      final pos = _player.state.position;
      final newPos = pos - const Duration(seconds: 10);
      _player.seek(newPos.isNegative ? Duration.zero : newPos);
      return true;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _player.seek(_player.state.position + const Duration(seconds: 10));
      return true;
    }
    if (key == LogicalKeyboardKey.arrowUp && !isRepeat) {
      final newVol = (_player.state.volume + 5.0).clamp(0.0, 100.0);
      _player.setVolume(newVol);
      ref.read(settingsProvider.notifier).setPlayerVolume(newVol);
      return true;
    }
    if (key == LogicalKeyboardKey.arrowDown && !isRepeat) {
      final newVol = (_player.state.volume - 5.0).clamp(0.0, 100.0);
      _player.setVolume(newVol);
      ref.read(settingsProvider.notifier).setPlayerVolume(newVol);
      return true;
    }
    if (key == LogicalKeyboardKey.keyM && !isRepeat) {
      if (_player.state.volume > 0) {
        _player.setVolume(0);
      } else {
        final saved = ref.read(settingsProvider).playerVolume;
        _player.setVolume(saved > 0 ? saved : 100.0);
      }
      return true;
    }
    if (key == LogicalKeyboardKey.keyF && !isRepeat) {
      _toggleFullscreen();
      return true;
    }
    if (key == LogicalKeyboardKey.escape && !isRepeat) {
      if (ref.read(playerFullscreenProvider)) _toggleFullscreen();
      return true;
    }
    return false;
  }

  void _checkSyncplay({String? userPath}) {
    // User-chosen path takes priority over all auto-detect locations.
    final custom = userPath ?? ref.read(settingsProvider).syncplayPath;
    if (custom.isNotEmpty && File(custom).existsSync()) {
      setState(() { _syncplayFound = true; _syncplayPath = custom; });
      return;
    }
    final appDir = p.dirname(Platform.resolvedExecutable);
    final paths = [
      p.join(appDir, 'syncplay', 'SyncplayConsole.exe'),
      r'C:\Program Files\Syncplay\SyncplayConsole.exe',
      r'C:\Program Files (x86)\Syncplay\SyncplayConsole.exe',
    ];
    for (final path in paths) {
      if (File(path).existsSync()) {
        setState(() { _syncplayFound = true; _syncplayPath = path; });
        return;
      }
    }
    setState(() { _syncplayFound = false; _syncplayPath = null; });
  }

  void _checkVlc() {
    final paths = [
      r'C:\Program Files\VideoLAN\VLC\vlc.exe',
      r'C:\Program Files (x86)\VideoLAN\VLC\vlc.exe',
    ];
    for (final path in paths) {
      if (File(path).existsSync()) {
        setState(() => _vlcPath = path);
        return;
      }
    }
  }

  Future<void> _configureForHighRes() async {
    try {
      final native = _sharedPlayer.platform as NativePlayer;
      // Force NVIDIA NVDEC for hardware decode. 'auto' on a laptop with iGPU+dGPU
      // typically picks D3D11VA on the Intel iGPU (the display adapter). nvdec-copy
      // uses the RTX 4070's dedicated NVDEC unit — far better for 4K HEVC 60fps —
      // and copies decoded frames to system RAM for Flutter texture upload.
      // Falls back to auto if NVDEC is unavailable (e.g., non-NVIDIA systems).
      await native.setProperty('hwdec', 'nvdec-copy,auto');
      await native.setProperty('hwdec-codecs', 'all');
      // video-sync=audio is the VFR-safe default. display-resample looks great on
      // constant-fps content but causes severe jitter on VFR phone-camera footage
      // (which has variable frame durations), especially at 240Hz where mpv must
      // fit ~59.76fps frames into 240Hz refresh slots with variable timing.
      await native.setProperty('video-sync', 'audio');
      // Drop frames at both the decode and output stages when behind schedule —
      // keeps A/V sync intact during transient CPU/GPU spikes.
      await native.setProperty('framedrop', 'yes');
      // 400 MiB demux buffer ≈ 50 s at 60 Mbps; prevents stalls in high-bitrate files.
      await native.setProperty('demuxer-max-bytes', '400MiB');
      await native.setProperty('demuxer-readahead-secs', '30');
      // Seekable RAM cache so scrubbing stays smooth in large files.
      await native.setProperty('cache', 'yes');
      await native.setProperty('cache-secs', '30');
    } catch (_) {}
  }

  Future<void> _launchVlc() async {
    if (_vlcPath == null || _videoPath == null) return;
    _player.pause();
    await Process.start(_vlcPath!, [_videoPath!]);
  }

  List<String> _scanSubtitles(String videoPath) {
    try {
      final dir = Directory(p.dirname(videoPath));
      if (!dir.existsSync()) return [];
      return dir
          .listSync()
          .whereType<File>()
          .where((f) => _kSubtitleExts.contains(
              p.extension(f.path).toLowerCase().replaceFirst('.', '')))
          .map((f) => f.path)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _attachSubtitle(String path) async {
    setState(() => _activeSubtitle = path);
    try {
      final native = _sharedPlayer.platform as NativePlayer;
      await native.setProperty('sub-file', path);
      await native.setProperty('sub-visibility', 'yes');
    } catch (_) {}
  }

  void _disableSubtitles() {
    setState(() => _activeSubtitle = null);
    try {
      (_sharedPlayer.platform as NativePlayer).setProperty('sub-visibility', 'no');
    } catch (_) {}
  }

  Future<void> _toggleFullscreen() async {
    final entering = !ref.read(playerFullscreenProvider);
    ref.read(playerFullscreenProvider.notifier).state = entering;
    await windowManager.setFullScreen(entering);
  }

  void _openVideo(String path) {
    final subs = _scanSubtitles(path);
    setState(() {
      _videoPath = path;
      _availableSubtitles = subs;
      _activeSubtitle = subs.isNotEmpty ? subs.first : null;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _player.open(Media(path));
      if (!mounted) return;

      final vol = ref.read(settingsProvider).playerVolume;
      try { await _player.setVolume(vol); } catch (_) {}
      if (!mounted) return;

      if (_activeSubtitle != null) {
        await _attachSubtitle(_activeSubtitle!);
        if (!mounted) return;
      }

      _player.play();
      if (mounted) ref.read(settingsProvider.notifier).setLastVideoPath(path);
    });
  }

  void _closeVideo() {
    _player.stop();
    setState(() {
      _videoPath = null;
      _availableSubtitles = [];
      _activeSubtitle = null;
    });
  }

  void _stopSyncplay() {
    if (_syncplayProcess != null) {
      Process.run('taskkill', ['/F', '/T', '/PID', '${_syncplayProcess!.pid}']);
    }
    setState(() => _syncplayProcess = null);
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _kVideoExts,
    );
    if (result != null && result.files.isNotEmpty) {
      _openVideo(result.files.first.path!);
    }
  }

  Future<void> _launchSyncplay() async {
    if (_syncplayPath == null || _videoPath == null) return;
    _player.pause();
    final settings = ref.read(settingsProvider);

    final args = [
      '--host', 'syncplay.pl:${settings.syncplayPort}',
      if (settings.syncplayUsername.isNotEmpty) ...['--name', settings.syncplayUsername],
      if (settings.syncplayRoom.isNotEmpty) ...['--room', settings.syncplayRoom],
      _videoPath!,
    ];

    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();

    final process = await Process.start(_syncplayPath!, args);
    setState(() { _syncplayProcess = process; _syncplayLogs.clear(); });

    final decoder = utf8.decoder;
    _stdoutSub = process.stdout
        .transform(decoder)
        .transform(const LineSplitter())
        .listen(_handleSyncplayLine);
    _stderrSub = process.stderr
        .transform(decoder)
        .transform(const LineSplitter())
        .listen((line) => _handleSyncplayLine('[err] $line'));

    process.exitCode.then((_) {
      if (mounted) setState(() => _syncplayProcess = null);
    });
  }

  void _handleSyncplayLine(String line) {
    if (!mounted) return;
    setState(() => _syncplayLogs.add(line));
  }

  @override
  Widget build(BuildContext context) {
    final accent = _palette.primary;
    final settings = ref.watch(settingsProvider);
    final isFullscreen = ref.watch(playerFullscreenProvider);

    ref.listen<String?>(playerOpenRequestProvider, (_, path) {
      if (path != null && ref.read(activeTabProvider) == AppTab.player) {
        ref.read(playerOpenRequestProvider.notifier).state = null;
        _openVideo(path);
      }
    });


    // Re-run detection when the user picks or clears a custom Syncplay path.
    ref.listen<String>(
      settingsProvider.select((s) => s.syncplayPath),
      (_, path) => _checkSyncplay(userPath: path),
    );

    // Pause automatically when leaving the Player tab.
    ref.listen<AppTab>(activeTabProvider, (prev, next) {
      if (prev == AppTab.player && next != AppTab.player) {
        _player.pause();
      }
    });

    // ── Fullscreen mode: just the video + exit button ─────────────────────
    if (isFullscreen) {
      return GestureDetector(
        onDoubleTap: _toggleFullscreen,
        child: Stack(
          children: [
            Positioned.fill(child: Video(controller: _controller)),
            Positioned(
              top: 16,
              right: 16,
              child: Tooltip(
                message: 'Exit fullscreen  (F / Esc)',
                child: InkWell(
                  onTap: _toggleFullscreen,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.fullscreen_exit_rounded,
                      color: Colors.white70,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ── Normal mode ───────────────────────────────────────────────────────
    return DropTarget(
      onDragDone: (details) {
        final path = details.files.first.path;
        if (_isVideoFile(path)) _openVideo(path);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: SectionHeader(
                    icon: Icons.play_circle_rounded,
                    title: 'Player',
                    subtitle: 'Preview videos and launch Syncplay',
                    color: accent,
                  ),
                ),
                if (_videoPath != null) ...[
                  if (_availableSubtitles.isNotEmpty)
                    _CcButton(
                      subtitles: _availableSubtitles,
                      activeSubtitle: _activeSubtitle,
                      accent: accent,
                      onSelect: _attachSubtitle,
                      onDisable: _disableSubtitles,
                    ).animate().fadeIn(duration: 200.ms),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: _closeVideo,
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Close'),
                    style: TextButton.styleFrom(
                      foregroundColor: kTextMuted,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ).animate().fadeIn(duration: 200.ms),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Video area — Expanded to fill available height
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, anim) {
                  final curved = CurvedAnimation(parent: anim, curve: Curves.easeOut);
                  return FadeTransition(
                    opacity: anim,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
                      child: child,
                    ),
                  );
                },
                child: _videoPath != null
                    ? _VideoArea(
                        key: const ValueKey('video'),
                        controller: _controller,
                        accent: accent,
                        onDrop: _openVideo,
                        onDoubleTap: _toggleFullscreen,
                      )
                    : _PlayerPlaceholder(
                        key: const ValueKey('placeholder'),
                        accent: accent,
                        onTap: _pickVideo,
                        onDrop: _openVideo,
                        lastVideoPath: settings.lastVideoPath.isEmpty
                            ? null
                            : settings.lastVideoPath,
                        onResume: settings.lastVideoPath.isEmpty
                            ? null
                            : () => _openVideo(settings.lastVideoPath),
                      ),
              ),
            ),
          ),

          // Controls below the video (scrollable if logs expand)
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_videoPath != null) ...[
                  const SizedBox(height: 10),
                  _FilenameBar(path: _videoPath!, accent: accent)
                      .animate()
                      .fadeIn(duration: 200.ms)
                      .slideY(begin: 0.1),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: SmallButton(
                        label: _videoPath == null ? 'Open Video' : 'Change Video',
                        icon: Icons.folder_open_rounded,
                        color: accent,
                        onTap: _pickVideo,
                      ),
                    ),
                    const SizedBox(width: 12),
                    _VlcButton(
                      enabled: _vlcPath != null && _videoPath != null,
                      accent: accent,
                      onTap: _launchVlc,
                    ),
                    const SizedBox(width: 12),
                    _SyncplayButton(
                      found: _syncplayFound,
                      enabled: _syncplayFound && _videoPath != null,
                      running: _syncplayProcess != null,
                      accent: accent,
                      onTap: _launchSyncplay,
                      onStop: _stopSyncplay,
                    ),
                  ],
                ).animate().fadeIn(duration: 300.ms, delay: 100.ms),
                const SizedBox(height: 16),
                _SyncplaySection(
                  found: _syncplayFound,
                  accent: accent,
                  usernameCtrl: _usernameCtrl,
                  roomCtrl: _roomCtrl,
                  onUsernameChanged: (v) =>
                      ref.read(settingsProvider.notifier).setSyncplayUsername(v),
                  onRoomChanged: (v) =>
                      ref.read(settingsProvider.notifier).setSyncplayRoom(v),
                  onPortChanged: (v) =>
                      ref.read(settingsProvider.notifier).setSyncplayPort(v),
                  selectedPort: settings.syncplayPort,
                ).animate().fadeIn(duration: 300.ms, delay: 150.ms),
                if (_syncplayLogs.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _SyncplayLogPanel(
                    logs: _syncplayLogs,
                    accent: accent,
                    expanded: _showLogs,
                    onToggle: () => setState(() => _showLogs = !_showLogs),
                  ).animate().fadeIn(duration: 200.ms),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _CcButton extends StatelessWidget {
  final List<String> subtitles;
  final String? activeSubtitle;
  final Color accent;
  final ValueChanged<String> onSelect;
  final VoidCallback onDisable;

  const _CcButton({
    required this.subtitles,
    required this.activeSubtitle,
    required this.accent,
    required this.onSelect,
    required this.onDisable,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String?>(
      tooltip: 'Subtitles',
      icon: Icon(
        Icons.closed_caption_rounded,
        size: 18,
        color: activeSubtitle != null ? accent : kTextMuted,
      ),
      color: kSurfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      itemBuilder: (_) => [
        PopupMenuItem<String?>(
          value: '',
          child: Row(
            children: [
              Icon(
                activeSubtitle == null ? Icons.check_rounded : Icons.subtitles_off_outlined,
                size: 15,
                color: activeSubtitle == null ? accent : kTextMuted,
              ),
              const SizedBox(width: 8),
              Text('None', style: TextStyle(fontSize: 13, color: kTextPrimary)),
            ],
          ),
        ),
        for (final sub in subtitles)
          PopupMenuItem<String?>(
            value: sub,
            child: Row(
              children: [
                Icon(
                  activeSubtitle == sub ? Icons.check_rounded : Icons.subtitles_outlined,
                  size: 15,
                  color: activeSubtitle == sub ? accent : kTextMuted,
                ),
                const SizedBox(width: 8),
                Text(
                  p.basename(sub),
                  style: TextStyle(fontSize: 13, color: kTextPrimary),
                ),
              ],
            ),
          ),
      ],
      onSelected: (val) {
        if (val == null || val.isEmpty) {
          onDisable();
        } else {
          onSelect(val);
        }
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _VideoArea extends StatefulWidget {
  final VideoController controller;
  final Color accent;
  final ValueChanged<String> onDrop;
  final VoidCallback onDoubleTap;

  const _VideoArea({
    super.key,
    required this.controller,
    required this.accent,
    required this.onDrop,
    required this.onDoubleTap,
  });

  @override
  State<_VideoArea> createState() => _VideoAreaState();
}

class _VideoAreaState extends State<_VideoArea> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (details) {
        setState(() => _isDragging = false);
        final path = details.files.first.path;
        if (_isVideoFile(path)) widget.onDrop(path);
      },
      child: GestureDetector(
        onDoubleTap: widget.onDoubleTap,
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _isDragging
                        ? widget.accent
                        : widget.accent.withValues(alpha: 0.3),
                    width: _isDragging ? 2 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                        color: widget.accent.withValues(alpha: 0.15),
                        blurRadius: 24),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Video(controller: widget.controller),
              ),
            ),
            if (_isDragging)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.file_download_rounded,
                          color: widget.accent, size: 42),
                      const SizedBox(height: 10),
                      Text(
                        'Drop to change video',
                        style: TextStyle(
                          color: widget.accent,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _PlayerPlaceholder extends StatefulWidget {
  final Color accent;
  final VoidCallback onTap;
  final ValueChanged<String> onDrop;
  final String? lastVideoPath;
  final VoidCallback? onResume;

  const _PlayerPlaceholder({
    super.key,
    required this.accent,
    required this.onTap,
    required this.onDrop,
    this.lastVideoPath,
    this.onResume,
  });

  @override
  State<_PlayerPlaceholder> createState() => _PlayerPlaceholderState();
}

class _PlayerPlaceholderState extends State<_PlayerPlaceholder> {
  bool _hovered = false;
  bool _isDragging = false;

  bool get _isActive => _hovered || _isDragging;

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (details) {
        setState(() => _isDragging = false);
        final path = details.files.first.path;
        if (_isVideoFile(path)) widget.onDrop(path);
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            // Fill available height (from Expanded parent)
            height: double.infinity,
            decoration: BoxDecoration(
              color: _isActive
                  ? widget.accent.withValues(alpha: 0.06)
                  : kSurface2Color,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _isDragging
                    ? widget.accent
                    : _isActive
                        ? widget.accent.withValues(alpha: 0.5)
                        : kBorderColor,
                width: _isDragging ? 2 : 1.5,
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      _isDragging
                          ? Icons.file_download_rounded
                          : Icons.play_circle_outline_rounded,
                      key: ValueKey(_isDragging),
                      size: 56,
                      color: _isActive ? widget.accent : kTextMuted,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _isDragging
                        ? 'Drop to open'
                        : 'Drop a video or click to browse',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _isActive ? widget.accent : kTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'MP4 · MKV · MOV · AVI · WebM',
                    style: TextStyle(fontSize: 12, color: kTextMuted),
                  ),
                  if (widget.lastVideoPath != null && !_isDragging) ...[
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: widget.onResume,
                      icon: Icon(Icons.history_rounded,
                          size: 14, color: widget.accent),
                      label: Text(
                        'Resume: ${p.basename(widget.lastVideoPath!)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: widget.accent,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    )
        .animate(target: _isDragging ? 1 : 0)
        .scaleXY(end: 1.02, duration: 150.ms, curve: Curves.easeOut);
  }
}

// ---------------------------------------------------------------------------

class _FilenameBar extends StatelessWidget {
  final String path;
  final Color accent;

  const _FilenameBar({required this.path, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: kSurface2Color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorderColor),
      ),
      child: Row(
        children: [
          Icon(Icons.movie_rounded, color: accent, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              p.basename(path),
              style: TextStyle(fontSize: 13, color: kTextPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            p.dirname(path),
            style: TextStyle(fontSize: 11, color: kTextMuted),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _VlcButton extends StatefulWidget {
  final bool enabled;
  final Color accent;
  final VoidCallback onTap;

  const _VlcButton({
    required this.enabled,
    required this.accent,
    required this.onTap,
  });

  @override
  State<_VlcButton> createState() => _VlcButtonState();
}

class _VlcButtonState extends State<_VlcButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.enabled
        ? Color.lerp(widget.accent, const Color(0xFFFF6600), 0.22)!
        : kTextMuted;

    return MouseRegion(
      cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() { _hovered = false; _pressed = false; }),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: widget.enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: widget.enabled ? () => setState(() => _pressed = false) : null,
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 80),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            decoration: BoxDecoration(
              gradient: widget.enabled
                  ? LinearGradient(colors: [color, color.withValues(alpha: 0.75)])
                  : null,
              color: widget.enabled ? null : kSurface2Color,
              borderRadius: BorderRadius.circular(10),
              boxShadow: widget.enabled && _hovered
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 3),
                      )
                    ]
                  : [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.videocam_rounded,
                    size: 16,
                    color: widget.enabled ? Colors.white : kTextMuted),
                const SizedBox(width: 8),
                Text(
                  'Open in VLC',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: widget.enabled ? Colors.white : kTextMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _SyncplayButton extends StatefulWidget {
  final bool found;
  final bool enabled;
  final bool running;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onStop;

  const _SyncplayButton({
    required this.found,
    required this.enabled,
    required this.running,
    required this.accent,
    required this.onTap,
    required this.onStop,
  });

  @override
  State<_SyncplayButton> createState() => _SyncplayButtonState();
}

class _SyncplayButtonState extends State<_SyncplayButton> {
  bool _hovered = false;
  bool _pressed = false;

  bool get _active => widget.running || widget.enabled;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _active ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() { _hovered = false; _pressed = false; }),
      child: GestureDetector(
        onTap: widget.running
            ? widget.onStop
            : widget.enabled
                ? widget.onTap
                : null,
        onTapDown: _active ? (_) => setState(() => _pressed = true) : null,
        onTapUp: _active ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: _active ? () => setState(() => _pressed = false) : null,
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 80),
          child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          decoration: BoxDecoration(
            gradient: (widget.enabled || widget.running)
                ? LinearGradient(colors: [
                    widget.running
                        ? const Color(0xFFEF4444)
                        : widget.accent,
                    (widget.running
                            ? const Color(0xFFEF4444)
                            : widget.accent)
                        .withValues(alpha: 0.75),
                  ])
                : null,
            color: (widget.enabled || widget.running) ? null : kSurface2Color,
            borderRadius: BorderRadius.circular(10),
            boxShadow: (widget.enabled || widget.running) && _hovered
                ? [
                    BoxShadow(
                      color: (widget.running
                              ? const Color(0xFFEF4444)
                              : widget.accent)
                          .withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 3),
                    )
                  ]
                : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.running)
                const Icon(Icons.stop_rounded, size: 16, color: Colors.white)
              else
                Icon(Icons.sync_rounded,
                    size: 16,
                    color: widget.enabled ? Colors.white : kTextMuted),
              const SizedBox(width: 8),
              Text(
                widget.running ? 'Stop Syncplay' : 'Open in Syncplay',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: (widget.enabled || widget.running)
                      ? Colors.white
                      : kTextMuted,
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _SyncplaySection extends StatelessWidget {
  final bool found;
  final Color accent;
  final TextEditingController usernameCtrl;
  final TextEditingController roomCtrl;
  final ValueChanged<String> onUsernameChanged;
  final ValueChanged<String> onRoomChanged;
  final ValueChanged<int> onPortChanged;
  final int selectedPort;

  const _SyncplaySection({
    required this.found,
    required this.accent,
    required this.usernameCtrl,
    required this.roomCtrl,
    required this.onUsernameChanged,
    required this.onRoomChanged,
    required this.onPortChanged,
    required this.selectedPort,
  });

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF10B981);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: found ? green : kTextMuted,
                boxShadow: found
                    ? [const BoxShadow(color: Color(0x6610B981), blurRadius: 8)]
                    : [],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              found
                  ? 'Syncplay detected — watch-together ready'
                  : 'Syncplay not found — install from syncplay.pl or place portable bundle in syncplay/ next to the app',
              style: TextStyle(
                fontSize: 12,
                color: found ? green : kTextMuted,
              ),
            ),
          ],
        ),
        if (found) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kSurface2Color,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kBorderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SYNCPLAY CONFIG',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: accent,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(Icons.settings_ethernet_rounded,
                        size: 15, color: kTextMuted),
                    const SizedBox(width: 8),
                    Text('Port',
                        style:
                            TextStyle(fontSize: 13, color: kTextSecondary)),
                    const SizedBox(width: 12),
                    for (final port in [8995, 8996, 8997, 8998, 8999])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _PortChip(
                          port: port,
                          selected: selectedPort == port,
                          accent: accent,
                          onTap: () => onPortChanged(port),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: kBorderColor),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _SyncplayField(
                        icon: Icons.person_outline_rounded,
                        hint: 'Username',
                        controller: usernameCtrl,
                        accent: accent,
                        onChanged: onUsernameChanged,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SyncplayField(
                        icon: Icons.meeting_room_outlined,
                        hint: 'Default room',
                        controller: roomCtrl,
                        accent: accent,
                        onChanged: onRoomChanged,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PortChip extends StatelessWidget {
  final int port;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _PortChip({
    required this.port,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.15) : kSurface2Color,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: selected ? accent : kBorderColor,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          '$port',
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? accent : kTextSecondary,
          ),
        ),
      ),
    ),
    );
  }
}

class _SyncplayField extends StatelessWidget {
  final IconData icon;
  final String hint;
  final TextEditingController controller;
  final Color accent;
  final ValueChanged<String> onChanged;

  const _SyncplayField({
    required this.icon,
    required this.hint,
    required this.controller,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: kTextMuted),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            style: TextStyle(fontSize: 13, color: kTextPrimary),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(fontSize: 13, color: kTextMuted),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: kBorderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: accent, width: 1.5),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _SyncplayLogPanel extends StatelessWidget {
  final List<String> logs;
  final Color accent;
  final bool expanded;
  final VoidCallback onToggle;

  const _SyncplayLogPanel({
    required this.logs,
    required this.accent,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.terminal_rounded, size: 14, color: accent),
                  const SizedBox(width: 8),
                  Text(
                    'Syncplay log  (${logs.length} lines)',
                    style: TextStyle(
                      fontSize: 12,
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: kTextMuted,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            child: expanded
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Divider(height: 1, color: kBorderColor),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          itemCount: logs.length,
                          reverse: true,
                          itemBuilder: (_, i) {
                            final line = logs[logs.length - 1 - i];
                            final isErr = line.startsWith('[err]');
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                line,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: isErr
                                      ? const Color(0xFFFF6B6B)
                                      : const Color(0xFF8B949E),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
