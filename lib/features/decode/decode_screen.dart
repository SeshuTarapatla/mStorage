import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../core/models/decode_config.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tab_colors.dart';
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

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp4'],
    );
    if (result != null) {
      setState(() => _videoPath = result.files.first.path);
    }
  }

  Future<void> _pickOutputDir() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir != null) {
      ref.read(settingsProvider.notifier).setOutputDirectory(dir);
    }
  }

  Future<void> _runDecode() async {
    if (_videoPath == null) return;
    final settings = ref.read(settingsProvider);
    final outDir = settings.outputDirectory.isEmpty
        ? p.dirname(_videoPath!)
        : settings.outputDirectory;

    await ref.read(decodeProvider.notifier).run(
          DecodeConfig(
            videoPath: _videoPath!,
            outputDirectory: outDir,
            password: settings.password,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(decodeProvider);
    final accent = _palette.primary;

    return SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              icon: Icons.download_rounded,
              title: 'Decode',
              subtitle: 'Extract the hidden movie from a mask MP4',
              color: accent,
            ),
            const SizedBox(height: 24),

            // Drop zone
            _DecodeDropZone(
              videoPath: _videoPath,
              accentColor: accent,
              onFilePicked: (path) => setState(() => _videoPath = path),
              onTap: _pickVideo,
            ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05),

            const SizedBox(height: 16),

            // Output directory
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 13),
                    decoration: BoxDecoration(
                      color: kSurface2Color,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kBorderColor),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.folder_outlined,
                            color: kTextMuted, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            ref
                                    .watch(settingsProvider)
                                    .outputDirectory
                                    .isEmpty
                                ? 'Output — same folder as video'
                                : ref
                                    .watch(settingsProvider)
                                    .outputDirectory,
                            style: TextStyle(
                              fontSize: 13,
                              color: ref
                                      .watch(settingsProvider)
                                      .outputDirectory
                                      .isEmpty
                                  ? kTextMuted
                                  : kTextPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SmallButton(
                  label: 'Browse',
                  icon: Icons.folder_open_rounded,
                  color: accent,
                  onTap: _pickOutputDir,
                ),
              ],
            ).animate().fadeIn(duration: 300.ms, delay: 80.ms),

            const SizedBox(height: 28),

            // Progress
            if (state.isRunning)
              _DecodeProgress(step: state.step, accentColor: accent)
                  .animate()
                  .fadeIn(),

            // Error
            if (state.step == DecodeStep.error)
              ErrorBanner(message: state.errorMessage ?? 'Unknown error')
                  .animate()
                  .fadeIn()
                  .shakeX(),

            // Done
            if (state.step == DecodeStep.done) ...[
              _DecodeDoneBanner(
                outputDir: state.outputDirectory ?? '',
                accentColor: accent,
                onReset: () {
                  ref.read(decodeProvider.notifier).reset();
                  setState(() => _videoPath = null);
                },
              ).animate().fadeIn().scaleXY(begin: 0.95),
              const SizedBox(height: 16),
              ExtractedFilesList(
                files: state.extractedFiles,
                accentColor: accent,
              ).animate().fadeIn(delay: 200.ms),
            ],

            // Decode button
            if (!state.isRunning && state.step != DecodeStep.done)
              _DecodeButton(
                enabled: _videoPath != null,
                accentColor: accent,
                onTap: _runDecode,
              ).animate().fadeIn(duration: 300.ms, delay: 140.ms),
          ],
        ),
    );
  }
}

class _DecodeDropZone extends StatefulWidget {
  final String? videoPath;
  final Color accentColor;
  final ValueChanged<String> onFilePicked;
  final VoidCallback onTap;

  const _DecodeDropZone({
    required this.videoPath,
    required this.accentColor,
    required this.onFilePicked,
    required this.onTap,
  });

  @override
  State<_DecodeDropZone> createState() => _DecodeDropZoneState();
}

class _DecodeDropZoneState extends State<_DecodeDropZone> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final hasFile = widget.videoPath != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        decoration: BoxDecoration(
          color: _isHovered || hasFile
              ? widget.accentColor.withValues(alpha: 0.06)
              : kSurface2Color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _isHovered
                ? widget.accentColor.withValues(alpha: 0.6)
                : hasFile
                    ? widget.accentColor.withValues(alpha: 0.5)
                    : kBorderColor,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(
              hasFile
                  ? Icons.video_file_rounded
                  : Icons.file_open_rounded,
              color: hasFile ? widget.accentColor : kTextMuted,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              hasFile
                  ? widget.videoPath!.split(r'\').last.split('/').last
                  : 'Drop encoded MP4 here',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: hasFile ? widget.accentColor : kTextPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              hasFile ? 'Click to change file' : 'or click to browse',
              style: const TextStyle(fontSize: 12, color: kTextMuted),
            ),
          ],
        ),
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
      (DecodeStep.extractingArchive, 'Splitting archive'),
      (DecodeStep.extractingFiles, 'Unpacking files'),
    ];
    return Column(
      children: steps.map((s) {
        final isActive = step == s.$1;
        final isDone = step.index > s.$1.index;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDone || isActive
                      ? accentColor.withValues(alpha: 0.15)
                      : kSurface2Color,
                  border: Border.all(
                    color: isDone || isActive ? accentColor : kBorderColor,
                  ),
                ),
                child: Center(
                  child: isDone
                      ? Icon(Icons.check_rounded,
                          color: accentColor, size: 14)
                      : isActive
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: accentColor,
                              ),
                            )
                          : null,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                s.$2,
                style: TextStyle(
                  fontSize: 13,
                  color: isDone || isActive ? kTextPrimary : kTextMuted,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _DecodeDoneBanner extends StatelessWidget {
  final String outputDir;
  final Color accentColor;
  final VoidCallback onReset;

  const _DecodeDoneBanner({
    required this.outputDir,
    required this.accentColor,
    required this.onReset,
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
                    style: const TextStyle(
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
          TextButton(onPressed: onReset, child: const Text('New')),
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
