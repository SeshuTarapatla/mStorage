import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../core/models/decode_config.dart';
import '../../core/providers/decode_request_provider.dart';
import '../../core/providers/player_request_provider.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tab_colors.dart';
import '../encode/widgets/drop_zone.dart';
import '../shell/app_shell.dart';
import '../shell/widgets/shared_widgets.dart';
import 'decode_notifier.dart';
import 'widgets/extracted_files_list.dart';

class DecodeScreen extends ConsumerStatefulWidget {
  const DecodeScreen({super.key});

  @override
  ConsumerState<DecodeScreen> createState() => _DecodeScreenState();
}

class _DecodeScreenState extends ConsumerState<DecodeScreen> {
  final _palette = AppTab.decode.palette;
  String? _videoPath;

  @override
  void initState() {
    super.initState();
    // Read any pending path that was set before this screen was built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final path = ref.read(decodeOpenRequestProvider);
      if (path != null && mounted) {
        setState(() => _videoPath = path);
        ref.read(decodeOpenRequestProvider.notifier).state = null;
      }
    });
  }

  void _onVideoDropped(String path) {
    final decState = ref.read(decodeProvider);
    if (!decState.isRunning && decState.step != DecodeStep.idle) {
      ref.read(decodeProvider.notifier).reset();
    }
    setState(() => _videoPath = path);
  }

  void _clearAll() => setState(() => _videoPath = null);

  void _openInPlayer(String path) {
    ref.read(playerOpenRequestProvider.notifier).state = path;
    ref.read(activeTabProvider.notifier).state = AppTab.player;
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp4'],
    );
    if (result != null) _onVideoDropped(result.files.first.path!);
  }

  Future<void> _pickOutputDir() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir != null) {
      ref.read(settingsProvider.notifier).setDecodeOutputDirectory(dir);
    }
  }

  Future<void> _runDecode() async {
    if (_videoPath == null) return;
    final settings = ref.read(settingsProvider);
    final outDir = settings.decodeOutputDirectory.isEmpty
        ? AppDirectories.decoded
        : settings.decodeOutputDirectory;

    await ref.read(decodeProvider.notifier).run(
          DecodeConfig(
            videoPath: _videoPath!,
            outputDirectory: outDir,
            password: settings.password,
          ),
        );
  }

  @override
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(decodeProvider);
    final settings = ref.watch(settingsProvider);
    final accent = _palette.primary;

    // Auto-delete the encoded source file when decode succeeds.
    // Keep the history record so Downloads still shows the entry with a Play button.
    ref.listen<DecodeState>(decodeProvider, (previous, next) {
      if (previous?.step != DecodeStep.done && next.step == DecodeStep.done) {
        if (!ref.read(settingsProvider).deleteAfterDecode) return;
        final path = _videoPath;
        if (path != null) {
          try {
            final file = File(path);
            if (file.existsSync()) file.deleteSync();
          } catch (_) {}
        }
      }
    });

    // Consume any file path sent from the Catalog "Decode this" shortcut.
    ref.listen<String?>(decodeOpenRequestProvider, (_, path) {
      if (path != null && mounted) {
        setState(() => _videoPath = path);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(decodeOpenRequestProvider.notifier).state = null;
        });
      }
    });

    final customDir = settings.decodeOutputDirectory;
    final displayOutDir = customDir.isNotEmpty ? customDir : AppDirectories.decoded;

    // First video in extracted files, for "Open in Player" shortcut
    final firstVideo = state.extractedFiles.where((f) {
      final ext = p.extension(f).replaceFirst('.', '').toLowerCase();
      return const {'mp4', 'mkv', 'avi', 'mov', 'webm'}.contains(ext);
    }).firstOrNull;

    return DropTarget(
      onDragDone: (details) {
        final path = details.files.first.path;
        final ext = path.split('.').last.toLowerCase();
        if (ext == 'mp4') _onVideoDropped(path);
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: SectionHeader(
                    icon: Icons.download_rounded,
                    title: 'Decode',
                    subtitle: 'Extract the hidden movie from a mask MP4',
                    color: accent,
                  ),
                ),
                if (state.isRunning)
                  TextButton.icon(
                    onPressed: () => ref.read(decodeProvider.notifier).cancel(),
                    icon: const Icon(Icons.cancel_rounded, size: 16),
                    label: const Text('Cancel'),
                    style: TextButton.styleFrom(
                      foregroundColor: kTextMuted,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ).animate().fadeIn(duration: 200.ms),
                if (_videoPath != null && state.step == DecodeStep.idle)
                  TextButton.icon(
                    onPressed: _clearAll,
                    icon: const Icon(Icons.clear_all_rounded, size: 16),
                    label: const Text('Clear all'),
                    style: TextButton.styleFrom(
                      foregroundColor: kTextMuted,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ).animate().fadeIn(duration: 200.ms),
              ],
            ),
            const SizedBox(height: 24),

            FileDropZone(
              label: 'Drop encoded MP4 here',
              hint: 'The mask file that hides a movie inside',
              accentColor: accent,
              currentPath: _videoPath,
              allowedExtensions: const ['mp4'],
              onFilePicked: _onVideoDropped,
              onTap: _pickVideo,
              onClear: () {
                final step = ref.read(decodeProvider).step;
                if (step == DecodeStep.done || step == DecodeStep.error) {
                  ref.read(decodeProvider.notifier).reset();
                }
                setState(() => _videoPath = null);
              },
            ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05),

            const SizedBox(height: 16),

            OutDirRow(
              dir: displayOutDir,
              accentColor: accent,
              onPick: _pickOutputDir,
              placeholder: 'Default: same folder as video',
              onClear: customDir.isEmpty
                  ? null
                  : () => ref
                      .read(settingsProvider.notifier)
                      .setDecodeOutputDirectory(''),
            ).animate().fadeIn(duration: 300.ms, delay: 80.ms),

            const SizedBox(height: 28),

            if (state.isRunning)
              _DecodeProgress(step: state.step, accentColor: accent)
                  .animate()
                  .fadeIn(),

            if (state.step == DecodeStep.error)
              (state.errorMessage == 'wrong_password'
                  ? PasswordWarningBanner(
                      accentColor: accent,
                      message: 'Incorrect password — the file could not be decrypted.',
                      onGoToSettings: () => ref
                          .read(activeTabProvider.notifier)
                          .state = AppTab.settings,
                    )
                  : ErrorBanner(message: state.errorMessage ?? 'Unknown error'))
                  .animate()
                  .fadeIn()
                  .shakeX(),

            if (state.step == DecodeStep.done) ...[
              _DecodeDoneBanner(
                outputDir: state.outputDirectory ?? '',
                accentColor: accent,
                firstVideoPath: firstVideo,
                onOpenInPlayer: firstVideo != null ? _openInPlayer : null,
                onReset: () {
                  ref.read(decodeProvider.notifier).reset();
                  _clearAll();
                },
              ).animate().fadeIn().scaleXY(begin: 0.95),
              const SizedBox(height: 16),
              ExtractedFilesList(
                files: state.extractedFiles,
                accentColor: accent,
                onOpenInPlayer: _openInPlayer,
              ).animate().fadeIn(delay: 200.ms),
            ],

            if (!state.isRunning && state.step != DecodeStep.done &&
                settings.password.isEmpty)
              PasswordWarningBanner(
                accentColor: accent,
                message: 'No password set — decoding will fail if the file is password-protected.',
                onGoToSettings: () => ref
                    .read(activeTabProvider.notifier)
                    .state = AppTab.settings,
              ).animate().fadeIn(duration: 300.ms),

            if (!state.isRunning && state.step != DecodeStep.done)
              _DecodeButton(
                enabled: _videoPath != null,
                accentColor: accent,
                onTap: _runDecode,
              ).animate().fadeIn(duration: 300.ms, delay: 140.ms),
          ],
        ),
      ),
    );
  }
}

class _DecodeProgress extends StatelessWidget {
  final DecodeStep step;
  final Color accentColor;

  const _DecodeProgress({required this.step, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final steps = [
      (DecodeStep.extractingArchive, Icons.call_split_rounded, 'Splitting'),
      (DecodeStep.extractingFiles, Icons.folder_zip_rounded, 'Unpacking'),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < steps.length; i++) ...[
            _DecodeStepDot(
              icon: steps[i].$2,
              label: steps[i].$3,
              isActive: step == steps[i].$1,
              isDone: step.index > steps[i].$1.index,
              accentColor: accentColor,
            ),
            if (i < steps.length - 1)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 19),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    height: 2,
                    color: step.index > steps[i].$1.index
                        ? accentColor
                        : kBorderColor,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _DecodeStepDot extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isDone;
  final Color accentColor;

  const _DecodeStepDot({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.isDone,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDone || isActive ? accentColor : kTextMuted;

    final Widget innerChild;
    if (isDone) {
      innerChild = Icon(Icons.check_rounded, color: accentColor, size: 18);
    } else if (isActive) {
      innerChild = SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: accentColor),
      );
    } else {
      innerChild = Icon(icon, color: kTextMuted, size: 18);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDone || isActive
                ? accentColor.withValues(alpha: 0.15)
                : kSurface2Color,
            border: Border.all(color: color, width: isActive ? 2 : 1),
            boxShadow: isActive
                ? [
                    BoxShadow(
                        color: accentColor.withValues(alpha: 0.4),
                        blurRadius: 12)
                  ]
                : [],
          ),
          child: Center(child: innerChild),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

class _DecodeDoneBanner extends StatelessWidget {
  final String outputDir;
  final Color accentColor;
  final VoidCallback onReset;
  final String? firstVideoPath;
  final ValueChanged<String>? onOpenInPlayer;

  const _DecodeDoneBanner({
    required this.outputDir,
    required this.accentColor,
    required this.onReset,
    this.firstVideoPath,
    this.onOpenInPlayer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: accentColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Decoded successfully!',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: accentColor)),
                Text(outputDir,
                    style: TextStyle(
                        fontSize: 12, color: kTextSecondary),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.folder_open_rounded),
            color: accentColor,
            onPressed: () => Process.run('explorer', [outputDir]),
            tooltip: 'Open in Explorer',
          ),
          if (onOpenInPlayer != null)
            TextButton.icon(
              onPressed: () => onOpenInPlayer!(firstVideoPath!),
              icon: Icon(Icons.play_circle_rounded, size: 16, color: accentColor),
              label: const Text('Play'),
              style: TextButton.styleFrom(foregroundColor: accentColor),
            ),
          TextButton(
            onPressed: onReset,
            style: TextButton.styleFrom(foregroundColor: accentColor),
            child: const Text('New'),
          ),
        ],
      ),
    );
  }
}

class _DecodeButton extends StatefulWidget {
  final bool enabled;
  final Color accentColor;
  final VoidCallback onTap;

  const _DecodeButton({
    required this.enabled,
    required this.accentColor,
    required this.onTap,
  });

  @override
  State<_DecodeButton> createState() => _DecodeButtonState();
}

class _DecodeButtonState extends State<_DecodeButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: widget.enabled
                ? LinearGradient(colors: [
                    widget.accentColor,
                    widget.accentColor.withValues(alpha: 0.75),
                  ])
                : null,
            color: widget.enabled ? null : kSurface2Color,
            borderRadius: BorderRadius.circular(12),
            boxShadow: widget.enabled && _hovered
                ? [
                    BoxShadow(
                      color: widget.accentColor.withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    )
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_open_rounded,
                  size: 18,
                  color: widget.enabled ? Colors.white : kTextMuted),
              const SizedBox(width: 10),
              Text(
                'Decode File',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: widget.enabled ? Colors.white : kTextMuted,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
