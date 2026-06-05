import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../core/models/encode_config.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tab_colors.dart';
import '../shell/widgets/shared_widgets.dart';
import 'encode_notifier.dart';
import 'widgets/drop_zone.dart';
import 'widgets/progress_pipeline.dart';

class EncodeScreen extends ConsumerStatefulWidget {
  const EncodeScreen({super.key});

  @override
  ConsumerState<EncodeScreen> createState() => _EncodeScreenState();
}

class _EncodeScreenState extends ConsumerState<EncodeScreen> {
  final _palette = AppTab.encode.palette;

  String? _videoPath;
  String? _posterPath;
  String? _srtPath;

  final _titleCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _timeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateCtrl.text =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _timeCtrl.text = '07:00:00';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _dateCtrl.dispose();
    _timeCtrl.dispose();
    super.dispose();
  }

  void _onVideoDropped(String path) {
    setState(() {
      _videoPath = path;
      if (_titleCtrl.text.isEmpty) {
        _titleCtrl.text = p.basenameWithoutExtension(path);
      }
    });
    _autoDetectSiblings(path);
  }

  /// Scans the same directory as [videoPath] for any image and/or subtitle file.
  /// Uses directory listing so the filename doesn't need to match exactly.
  void _autoDetectSiblings(String videoPath,
      {bool skipPoster = false, bool skipSrt = false}) {
    final dir = p.dirname(videoPath);

    try {
      final entries = Directory(dir).listSync().whereType<File>().toList();

      if (!skipPoster && _posterPath == null) {
        const imageExts = {'jpg', 'jpeg', 'png', 'webp'};
        for (final f in entries) {
          final ext = p.extension(f.path).toLowerCase().replaceFirst('.', '');
          if (imageExts.contains(ext)) {
            setState(() => _posterPath = f.path);
            break;
          }
        }
      }

      if (!skipSrt && _srtPath == null) {
        const subExts = {'srt', 'ass', 'vtt'};
        for (final f in entries) {
          final ext = p.extension(f.path).toLowerCase().replaceFirst('.', '');
          if (subExts.contains(ext)) {
            setState(() => _srtPath = f.path);
            break;
          }
        }
      }
    } catch (_) {}
  }

  /// Routes a batch of dropped file paths to the correct fields by extension.
  void _routeFiles(List<String> paths) {
    String? videoPath, posterPath, srtPath;
    for (final path in paths) {
      final ext = path.split('.').last.toLowerCase();
      if (['mp4', 'mkv', 'avi', 'mov', 'wmv', 'webm'].contains(ext)) {
        videoPath = path;
      } else if (['jpg', 'jpeg', 'png', 'webp'].contains(ext)) {
        posterPath = path;
      } else if (['srt', 'ass', 'vtt'].contains(ext)) {
        srtPath = path;
      }
    }

    setState(() {
      if (videoPath != null) {
        _videoPath = videoPath;
        if (_titleCtrl.text.isEmpty) {
          _titleCtrl.text = p.basenameWithoutExtension(videoPath);
        }
      }
      if (posterPath != null) _posterPath = posterPath;
      if (srtPath != null) _srtPath = srtPath;
    });

    // Auto-detect only for fields not already covered by the drop batch
    if (videoPath != null) {
      _autoDetectSiblings(videoPath,
          skipPoster: posterPath != null,
          skipSrt: srtPath != null);
    }
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );
    if (result != null && result.files.isNotEmpty) {
      _onVideoDropped(result.files.first.path!);
    }
  }

  Future<void> _pickPoster() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result != null) {
      setState(() => _posterPath = result.files.first.path);
    }
  }

  Future<void> _pickSrt() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['srt', 'ass', 'vtt'],
    );
    if (result != null) {
      setState(() => _srtPath = result.files.first.path);
    }
  }

  Future<void> _pickOutputDir() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir != null) {
      ref.read(settingsProvider.notifier).setOutputDirectory(dir);
    }
  }

  void _clearAll() {
    setState(() {
      _videoPath = null;
      _posterPath = null;
      _srtPath = null;
      _titleCtrl.clear();
    });
  }

  Future<void> _runEncode() async {
    if (_videoPath == null) return;
    final settings = ref.read(settingsProvider);
    final title = _titleCtrl.text.trim().isEmpty
        ? p.basenameWithoutExtension(_videoPath!)
        : _titleCtrl.text.trim();
    final outDir = settings.outputDirectory.isEmpty
        ? p.dirname(_videoPath!)
        : settings.outputDirectory;

    await ref.read(encodeProvider.notifier).run(
          EncodeConfig(
            videoPath: _videoPath!,
            title: title,
            date: _dateCtrl.text.trim(),
            time: _timeCtrl.text.trim(),
            posterPath: _posterPath,
            srtPath: _srtPath,
            outputDirectory: outDir,
            password: settings.password,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final encodeState = ref.watch(encodeProvider);
    final settings = ref.watch(settingsProvider);
    final accent = _palette.primary;

    final anyFieldSet = _videoPath != null || _posterPath != null || _srtPath != null;

    return DropTarget(
      onDragDone: (details) =>
          _routeFiles(details.files.map((f) => f.path).toList()),
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
                        icon: Icons.upload_rounded,
                        title: 'Encode',
                        subtitle: 'Hide a movie inside a mask MP4',
                        color: accent,
                      ),
                    ),
                    if (anyFieldSet && encodeState.step == EncodeStep.idle)
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

                // Video drop zone (primary — large)
                FileDropZone(
                  label: 'Drop video file here',
                  hint: 'MP4, MKV, AVI, MOV — or click to browse',
                  accentColor: accent,
                  currentPath: _videoPath,
                  allowedExtensions: ['mp4', 'mkv', 'avi', 'mov', 'wmv', 'webm'],
                  onFilePicked: _onVideoDropped,
                  onTap: _pickVideo,
                  onMultiFileDrop: _routeFiles,
                  onClear: () => setState(() {
                    _videoPath = null;
                    _titleCtrl.clear();
                  }),
                ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05),

                const SizedBox(height: 20),

                // Metadata row
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _Field(
                        controller: _titleCtrl,
                        label: 'Title',
                        hint: 'Auto-filled from filename',
                        accentColor: accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: _Field(
                        controller: _dateCtrl,
                        label: 'Date',
                        hint: 'YYYY-MM-DD',
                        accentColor: accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: _Field(
                        controller: _timeCtrl,
                        label: 'Time',
                        hint: 'HH:MM:SS',
                        accentColor: accent,
                      ),
                    ),
                  ],
                ).animate().fadeIn(duration: 300.ms, delay: 80.ms),

                const SizedBox(height: 16),

                // Optional files row
                Row(
                  children: [
                    Expanded(
                      child: FileDropZone(
                        label: 'Poster Image',
                        hint: 'Optional — JPG/PNG\nor auto-extracted',
                        accentColor: accent,
                        currentPath: _posterPath,
                        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
                        onFilePicked: (path) =>
                            setState(() => _posterPath = path),
                        onTap: _pickPoster,
                        onMultiFileDrop: _routeFiles,
                        onClear: () => setState(() => _posterPath = null),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FileDropZone(
                        label: 'Subtitle File',
                        hint: 'Optional — SRT/ASS/VTT',
                        accentColor: accent,
                        currentPath: _srtPath,
                        allowedExtensions: ['srt', 'ass', 'vtt'],
                        onFilePicked: (path) => setState(() => _srtPath = path),
                        onTap: _pickSrt,
                        onMultiFileDrop: _routeFiles,
                        onClear: () => setState(() => _srtPath = null),
                      ),
                    ),
                  ],
                ).animate().fadeIn(duration: 300.ms, delay: 140.ms),

                const SizedBox(height: 16),

                // Output directory
                OutDirRow(
                  dir: settings.outputDirectory,
                  accentColor: accent,
                  onPick: _pickOutputDir,
                ).animate().fadeIn(duration: 300.ms, delay: 180.ms),

                const SizedBox(height: 28),

                // Progress pipeline (only during/after run)
                if (encodeState.step != EncodeStep.idle) ...[
                  ProgressPipeline(
                    currentStep: encodeState.step,
                    accentColor: accent,
                    compressProgress: encodeState.compressProgress,
                    combineProgress: encodeState.combineProgress,
                  ).animate().fadeIn(duration: 400.ms),
                  const SizedBox(height: 24),
                ],

                // Error message
                if (encodeState.step == EncodeStep.error)
                  ErrorBanner(message: encodeState.errorMessage ?? 'Unknown error')
                      .animate()
                      .fadeIn()
                      .shakeX(),

                // Done banner
                if (encodeState.step == EncodeStep.done)
                  _DoneBanner(
                    outputPath: encodeState.outputPath ?? '',
                    accentColor: accent,
                    onReset: () {
                      ref.read(encodeProvider.notifier).reset();
                      _clearAll();
                    },
                  ).animate().fadeIn().scaleXY(begin: 0.95),

                // Encode button
                if (encodeState.step == EncodeStep.idle ||
                    encodeState.step == EncodeStep.error)
                  _EncodeButton(
                    enabled: _videoPath != null && !encodeState.isRunning,
                    accentColor: accent,
                    onTap: _runEncode,
                  ).animate().fadeIn(duration: 300.ms, delay: 220.ms),
              ],
            ),
          ),
    );
  }
}


class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final Color accentColor;

  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 14, color: kTextPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accentColor, width: 1.5),
        ),
      ),
    );
  }
}


class _EncodeButton extends StatefulWidget {
  final bool enabled;
  final Color accentColor;
  final VoidCallback onTap;

  const _EncodeButton({
    required this.enabled,
    required this.accentColor,
    required this.onTap,
  });

  @override
  State<_EncodeButton> createState() => _EncodeButtonState();
}

class _EncodeButtonState extends State<_EncodeButton> {
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
                ? LinearGradient(
                    colors: [
                      widget.accentColor,
                      widget.accentColor.withValues(alpha: 0.75),
                    ],
                  )
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
              Icon(
                Icons.lock_rounded,
                size: 18,
                color: widget.enabled ? Colors.white : kTextMuted,
              ),
              const SizedBox(width: 10),
              Text(
                'Encode File',
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


class _DoneBanner extends StatelessWidget {
  final String outputPath;
  final Color accentColor;
  final VoidCallback onReset;

  const _DoneBanner({
    required this.outputPath,
    required this.accentColor,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
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
                Text('Encoded successfully!',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: accentColor)),
                Text(outputPath,
                    style: const TextStyle(
                        fontSize: 12, color: kTextSecondary),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          TextButton(
            onPressed: onReset,
            child: const Text('New'),
          ),
        ],
      ),
    );
  }
}
