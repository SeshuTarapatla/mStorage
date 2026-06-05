import 'dart:async';
import 'dart:io';
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
  @override
  EncodeState build() => const EncodeState();

  Future<void> run(EncodeConfig config) async {
    state = const EncodeState(step: EncodeStep.generatingMask);

    try {
      final tmpDir = await getTemporaryDirectory();
      final cacheDir = Directory(p.join(tmpDir.path, 'mstorage_cache'));
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

      final maskResult = await FfmpegService.generateMaskVideo(
        posterPath: posterPath,
        outputPath: maskPath,
        date: config.date,
        time: config.time,
      );
      if (maskResult.exitCode != 0 || !File(maskPath).existsSync()) {
        state = state.copyWith(
          step: EncodeStep.error,
          errorMessage: 'ffmpeg failed: ${maskResult.stderr}',
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
      await ArchiveService.createZip(
        fileEntries: filesToArchive,
        outputPath: archivePath,
        password: config.password,
        onProgress: (prog) => state = state.copyWith(compressProgress: prog),
      );
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

      // Cleanup cache
      await cacheDir.delete(recursive: true);

      state = state.copyWith(step: EncodeStep.done, outputPath: outputPath);
    } catch (e) {
      state = state.copyWith(
        step: EncodeStep.error,
        errorMessage: e.toString(),
      );
    }
  }

  void reset() => state = const EncodeState();
}

final encodeProvider =
    NotifierProvider<EncodeNotifier, EncodeState>(EncodeNotifier.new);
