import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tab_colors.dart';
import '../shell/widgets/shared_widgets.dart';

final _playerProvider = Provider.autoDispose((ref) {
  final player = Player();
  ref.onDispose(player.dispose);
  return player;
});

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  final _palette = AppTab.player.palette;
  VideoController? _controller;
  String? _videoPath;
  bool _syncplayFound = false;
  String? _syncplayPath;

  @override
  void initState() {
    super.initState();
    _checkSyncplay();
    final player = ref.read(_playerProvider);
    _controller = VideoController(player);
  }

  void _checkSyncplay() {
    final paths = [
      r'C:\Program Files\Syncplay\SyncplayConsole.exe',
      r'C:\Program Files (x86)\Syncplay\SyncplayConsole.exe',
    ];
    for (final p in paths) {
      if (File(p).existsSync()) {
        setState(() {
          _syncplayFound = true;
          _syncplayPath = p;
        });
        return;
      }
    }
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp4', 'mkv', 'mov', 'avi', 'webm'],
    );
    if (result != null && result.files.isNotEmpty) {
      final path = result.files.first.path!;
      setState(() => _videoPath = path);
      await ref.read(_playerProvider).open(Media(path));
    }
  }

  void _launchSyncplay() {
    if (_syncplayPath == null || _videoPath == null) return;
    Process.start(_syncplayPath!, [_videoPath!], mode: ProcessStartMode.detached);
  }

  @override
  Widget build(BuildContext context) {
    final accent = _palette.primary;

    return SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              icon: Icons.play_circle_rounded,
              title: 'Player',
              subtitle: 'Preview videos and launch Syncplay',
              color: accent,
            ),
            const SizedBox(height: 24),

            // Video player area
            if (_videoPath != null && _controller != null)
              _VideoArea(controller: _controller!, accent: accent)
                  .animate()
                  .fadeIn(duration: 300.ms)
            else
              _PickerPlaceholder(accent: accent, onTap: _pickVideo)
                  .animate()
                  .fadeIn(duration: 300.ms).slideY(begin: 0.05),

            const SizedBox(height: 16),

            // Controls row
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
                _SyncplayButton(
                  found: _syncplayFound,
                  enabled: _syncplayFound && _videoPath != null,
                  accent: accent,
                  onTap: _launchSyncplay,
                ),
              ],
            ).animate().fadeIn(duration: 300.ms, delay: 100.ms),

            const SizedBox(height: 16),
            _SyncplayStatus(found: _syncplayFound, accent: accent)
                .animate()
                .fadeIn(duration: 300.ms, delay: 150.ms),
          ],
        ),
    );
  }
}

class _VideoArea extends StatelessWidget {
  final VideoController controller;
  final Color accent;

  const _VideoArea({required this.controller, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 320,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: 0.15), blurRadius: 24),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Video(controller: controller),
    );
  }
}

class _PickerPlaceholder extends StatefulWidget {
  final Color accent;
  final VoidCallback onTap;

  const _PickerPlaceholder({required this.accent, required this.onTap});

  @override
  State<_PickerPlaceholder> createState() => _PickerPlaceholderState();
}

class _PickerPlaceholderState extends State<_PickerPlaceholder> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 280,
          decoration: BoxDecoration(
            color: _hovered
                ? widget.accent.withValues(alpha: 0.06)
                : kSurface2Color,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _hovered
                  ? widget.accent.withValues(alpha: 0.5)
                  : kBorderColor,
              width: 1.5,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_circle_outline_rounded,
                    size: 56,
                    color: _hovered ? widget.accent : kTextMuted),
                const SizedBox(height: 14),
                Text('Open a video to preview',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _hovered ? widget.accent : kTextPrimary)),
                const SizedBox(height: 4),
                const Text('MP4, MKV, MOV, AVI, WebM',
                    style: TextStyle(fontSize: 12, color: kTextMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SyncplayButton extends StatefulWidget {
  final bool found;
  final bool enabled;
  final Color accent;
  final VoidCallback onTap;

  const _SyncplayButton({
    required this.found,
    required this.enabled,
    required this.accent,
    required this.onTap,
  });

  @override
  State<_SyncplayButton> createState() => _SyncplayButtonState();
}

class _SyncplayButtonState extends State<_SyncplayButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          decoration: BoxDecoration(
            gradient: widget.enabled
                ? LinearGradient(colors: [
                    widget.accent,
                    widget.accent.withValues(alpha: 0.75),
                  ])
                : null,
            color: widget.enabled ? null : kSurface2Color,
            borderRadius: BorderRadius.circular(10),
            boxShadow: widget.enabled && _hovered
                ? [
                    BoxShadow(
                      color: widget.accent.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 3),
                    )
                  ]
                : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sync_rounded,
                  size: 16,
                  color: widget.enabled ? Colors.white : kTextMuted),
              const SizedBox(width: 8),
              Text('Open in Syncplay',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: widget.enabled ? Colors.white : kTextMuted,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _SyncplayStatus extends StatelessWidget {
  final bool found;
  final Color accent;

  const _SyncplayStatus({required this.found, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: found ? const Color(0xFF10B981) : kTextMuted,
            boxShadow: found
                ? [
                    BoxShadow(
                        color: const Color(0x6610B981), blurRadius: 8)
                  ]
                : [],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          found
              ? 'Syncplay detected — watch-together ready'
              : 'Syncplay not found — install from syncplay.pl',
          style: TextStyle(
            fontSize: 12,
            color: found ? const Color(0xFF10B981) : kTextMuted,
          ),
        ),
      ],
    );
  }
}
