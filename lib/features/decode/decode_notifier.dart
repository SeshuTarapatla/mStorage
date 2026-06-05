import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/models/decode_config.dart';
import '../../core/services/archive_service.dart';
import '../../core/services/format_service.dart';

enum DecodeStep { idle, extractingArchive, extractingFiles, done, error }

class DecodeState {
  final DecodeStep step;
  final String? errorMessage;
  final List<String> extractedFiles;
  final String? outputDirectory;

  const DecodeState({
    this.step = DecodeStep.idle,
    this.errorMessage,
    this.extractedFiles = const [],
    this.outputDirectory,
  });

  DecodeState copyWith({
    DecodeStep? step,
    String? errorMessage,
    List<String>? extractedFiles,
    String? outputDirectory,
  }) =>
      DecodeState(
        step: step ?? this.step,
        errorMessage: errorMessage ?? this.errorMessage,
        extractedFiles: extractedFiles ?? this.extractedFiles,
        outputDirectory: outputDirectory ?? this.outputDirectory,
      );

  bool get isRunning =>
      step == DecodeStep.extractingArchive ||
      step == DecodeStep.extractingFiles;
}

class DecodeNotifier extends Notifier<DecodeState> {
  @override
  DecodeState build() => const DecodeState();

  Future<void> run(DecodeConfig config) async {
    state = const DecodeState(step: DecodeStep.extractingArchive);

    try {
      final tmpDir = await getTemporaryDirectory();
      final cacheDir = Directory(p.join(tmpDir.path, 'mstorage_cache'));
      await cacheDir.create(recursive: true);

      final title = p.basenameWithoutExtension(config.videoPath);
      final archivePath = p.join(cacheDir.path, '$title.archive');

      // Step 1 — split out the archive payload
      final found = await FormatService.extractArchive(
        inputPath: config.videoPath,
        outputArchivePath: archivePath,
      );
      if (!found) {
        state = state.copyWith(
          step: DecodeStep.error,
          errorMessage: 'No mStorage payload found in this file.',
        );
        return;
      }

      // Step 2 — unpack archive (ZIP or legacy RAR via 7z)
      state = state.copyWith(step: DecodeStep.extractingFiles);
      final outDir = p.join(config.outputDirectory, title);
      final result = await ArchiveService.extractArchive(
        archivePath: archivePath,
        outputDir: outDir,
        password: config.password,
      );
      if (result.exitCode != 0) {
        state = state.copyWith(
          step: DecodeStep.error,
          errorMessage: 'Extraction failed: ${result.stderr}',
        );
        return;
      }

      // Collect extracted files
      final files = Directory(outDir)
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path)
          .toList();

      await cacheDir.delete(recursive: true);

      state = state.copyWith(
        step: DecodeStep.done,
        extractedFiles: files,
        outputDirectory: outDir,
      );
    } catch (e) {
      state = state.copyWith(
        step: DecodeStep.error,
        errorMessage: e.toString(),
      );
    }
  }

  void reset() => state = const DecodeState();
}

final decodeProvider =
    NotifierProvider<DecodeNotifier, DecodeState>(DecodeNotifier.new);
