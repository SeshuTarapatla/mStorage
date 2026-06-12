import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/models/encode_config.dart';
import '../../core/services/archive_service.dart';
import '../../core/services/ffmpeg_service.dart';
import '../../core/services/format_service.dart';

enum EncodeStep { idle, generatingMask, compressing, combining, done, error }

class EncodeState {
  final EncodeStep step;
  final String? errorMessage;
  final String? outputPath;
  final double compressProgress; // 0.0–1.0 during compressing step
  final double combineProgress;  // 0.0–1.0 during combining step

  const EncodeState({
    this.step = EncodeStep.idle,
    this.errorMessage,
    this.outputPath,
    this.compressProgress = 0.0,
    this.combineProgress = 0.0,
  });

  EncodeState copyWith({
    EncodeStep? step,
    String? errorMessage,
    String? outputPath,
    double? compressProgress,
    double? combineProgress,
  }) =>
      EncodeState(
        step: step ?? this.step,
        errorMessage: errorMessage ?? this.errorMessage,
        outputPath: outputPath ?? this.outputPath,
        compressProgress: compressProgress ?? this.compressProgress,
        combineProgress: combineProgress ?? this.combineProgress,
      );

  bool get isRunning => step == EncodeStep.generatingMask ||
      step == EncodeStep.compressing ||
      step == EncodeStep.combining;
}

class EncodeNotifier extends Notifier<EncodeState> {
  Process? _ffmpegProcess;
  Process? _zipProcess;
  bool _cancelled = false;

  @override
  EncodeState build() => const EncodeState();

  Future<void> run(EncodeConfig config) async {
    _cancelled = false;
    state = const EncodeState(step: EncodeStep.generatingMask);

    try {
      final tmpDir = await getTemporaryDirectory();
      final uid = DateTime.now().microsecondsSinceEpoch.toString();
      final cacheDir = Directory(p.join(tmpDir.path, 'mstorage_cache', uid));
      await cacheDir.create(recursive: true);

      final maskPath = p.join(cacheDir.path, 'mask.mp4');
      final archivePath = p.join(cacheDir.path, '${config.title}.zip');
      final outputPath =
          p.join(config.outputDirectory, '${config.title}.mp4');

      // Step 1 — generate mask video
      String posterPath = config.posterPath ?? '';
      if (posterPath.isEmpty) {
        final thumbPath = p.join(cacheDir.path, 'thumb.jpg');
        final thumbResult = await FfmpegService.extractThumbnail(
          videoPath: config.videoPath,
          outputPath: thumbPath,
        );
        if (thumbResult.exitCode == 0 && File(thumbPath).existsSync()) {
          posterPath = thumbPath;
        }
      }

      // Detect poster orientation to choose the right canvas size
      int targetWidth = 1920;
      int targetHeight = 1080;
      if (posterPath.isNotEmpty) {
        try {
          final bytes = await File(posterPath).readAsBytes();
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          if (frame.image.height > frame.image.width) {
            targetWidth = 1080;
            targetHeight = 1920;
          }
          frame.image.dispose();
          codec.dispose();
        } catch (_) {
          // Fall back to landscape on decode failure
        }
      }

      final ffmpegProcess = await FfmpegService.startMaskGeneration(
        posterPath: posterPath,
        outputPath: maskPath,
        date: config.date,
        time: config.time,
        durationSeconds: config.maskDurationSeconds,
        preserveAspectRatio: config.preserveAspectRatio,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      _ffmpegProcess = ffmpegProcess;
      final stderr = StringBuffer();
      ffmpegProcess.stderr.transform(utf8.decoder).listen(stderr.write);
      final ffmpegExit = await ffmpegProcess.exitCode;
      _ffmpegProcess = null;

      if (_cancelled) return;
      if (ffmpegExit != 0 || !File(maskPath).existsSync()) {
        state = state.copyWith(
          step: EncodeStep.error,
          errorMessage: 'ffmpeg failed: ${stderr.toString()}',
        );
        return;
      }

      // Step 2 — package payload (STORE ZIP, files renamed to <title>.<ext>)
      state = state.copyWith(step: EncodeStep.compressing, compressProgress: 0.0);
      final filesToArchive = <(String, String)>[
        (config.videoPath, '${config.title}${p.extension(config.videoPath)}'),
        if (config.srtPath != null && config.srtPath!.isNotEmpty)
          (config.srtPath!, '${config.title}${p.extension(config.srtPath!)}'),
        if (config.posterPath != null && config.posterPath!.isNotEmpty)
          (config.posterPath!, '${config.title}${p.extension(config.posterPath!)}'),
      ];

      // For unencrypted ZIP (runs in isolate), poll output file size for progress.
      int totalInputBytes = 0;
      if (config.password.isEmpty) {
        for (final (path, _) in filesToArchive) {
          try { totalInputBytes += File(path).lengthSync(); } catch (_) {}
        }
      }
      Timer? zipPoll;
      if (totalInputBytes > 0) {
        zipPoll = Timer.periodic(const Duration(milliseconds: 250), (_) {
          try {
            final written = File(archivePath).lengthSync();
            state = state.copyWith(
              compressProgress: (written / totalInputBytes).clamp(0.0, 0.99),
            );
          } catch (_) {}
        });
      }
      try {
        await ArchiveService.createZip(
          fileEntries: filesToArchive,
          outputPath: archivePath,
          password: config.password,
          onProgress: config.password.isNotEmpty
              ? (prog) => state = state.copyWith(compressProgress: prog)
              : null,
          onProcessStarted: config.password.isNotEmpty
              ? (proc) => _zipProcess = proc
              : null,
        );
      } finally {
        zipPoll?.cancel();
        _zipProcess = null;
      }

      if (_cancelled) return;
      if (!File(archivePath).existsSync()) {
        state = state.copyWith(
          step: EncodeStep.error,
          errorMessage: 'Archive creation failed.',
        );
        return;
      }

      // Step 3 — combine mask + archive into output file
      await Directory(config.outputDirectory).create(recursive: true);
      state = state.copyWith(step: EncodeStep.combining, combineProgress: 0.0);

      int maskLen = 0, archiveLen = 0;
      try { maskLen = File(maskPath).lengthSync(); } catch (_) {}
      try { archiveLen = File(archivePath).lengthSync(); } catch (_) {}
      final combineTotal = maskLen + archiveLen;

      Timer? combinePoll;
      if (combineTotal > 0) {
        combinePoll = Timer.periodic(const Duration(milliseconds: 250), (_) {
          try {
            final written = File(outputPath).lengthSync();
            state = state.copyWith(
              combineProgress: (written / combineTotal).clamp(0.0, 0.99),
            );
          } catch (_) {}
        });
      }

      try {
        await FormatService.combine(
          maskPath: maskPath,
          archivePath: archivePath,
          outputPath: outputPath,
        );
      } finally {
        combinePoll?.cancel();
      }

      // Cleanup own cache dir only
      try { await cacheDir.delete(recursive: true); } catch (_) {}

      state = state.copyWith(step: EncodeStep.done, outputPath: outputPath);
    } catch (e) {
      if (_cancelled) return;
      state = state.copyWith(
        step: EncodeStep.error,
        errorMessage: e.toString(),
      );
    }
  }

  void cancel() {
    _cancelled = true;
    _ffmpegProcess?.kill();
    _ffmpegProcess = null;
    _zipProcess?.kill();
    _zipProcess = null;
    state = const EncodeState();
  }

  void reset() => state = const EncodeState();
}

final encodeProvider =
    NotifierProvider<EncodeNotifier, EncodeState>(EncodeNotifier.new);
