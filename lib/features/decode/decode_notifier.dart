import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/models/decode_config.dart';
import '../../core/services/archive_service.dart';
import '../../core/services/format_service.dart';
import '../../core/util/filename_sanitizer.dart';

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
  Process? _extractProcess;
  bool _cancelled = false;

  @override
  DecodeState build() => const DecodeState();

  Future<void> run(DecodeConfig config) async {
    _cancelled = false;
    state = const DecodeState(step: DecodeStep.extractingArchive);

    try {
      final tmpDir = await getTemporaryDirectory();
      final uid = DateTime.now().microsecondsSinceEpoch.toString();
      final cacheDir = Directory(p.join(tmpDir.path, 'mstorage_cache', uid));
      await cacheDir.create(recursive: true);

      final title = sanitizeFilename(p.basenameWithoutExtension(config.videoPath));
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

      if (_cancelled) return;

      // Step 2 — unpack via 7za, keeping the Process handle for cancellation
      state = state.copyWith(step: DecodeStep.extractingFiles);
      final outDir = p.join(config.outputDirectory, title);
      await Directory(outDir).create(recursive: true);

      final sevenZip = await ArchiveService.sevenZipPath;
      final args = [
        'x', archivePath,
        '-o$outDir',
        '-y',
        if (config.password.isNotEmpty) '-p${config.password}',
      ];

      final process = await Process.start(sevenZip, args);
      _extractProcess = process;

      final stderr = StringBuffer();
      process.stderr.transform(utf8.decoder).listen(stderr.write);

      final exitCode = await process.exitCode;
      _extractProcess = null;

      if (_cancelled) return;

      if (exitCode != 0) {
        final errText = stderr.toString();
        final isWrongPassword = errText.contains('Wrong password') ||
            errText.contains('CRC Failed');
        state = state.copyWith(
          step: DecodeStep.error,
          errorMessage: isWrongPassword ? 'wrong_password' : 'Extraction failed: $errText',
        );
        return;
      }

      final files = Directory(outDir)
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path)
          .toList();

      try { await cacheDir.delete(recursive: true); } catch (_) {}

      state = state.copyWith(
        step: DecodeStep.done,
        extractedFiles: files,
        outputDirectory: outDir,
      );
    } catch (e) {
      if (_cancelled) return;
      state = state.copyWith(
        step: DecodeStep.error,
        errorMessage: e.toString(),
      );
    }
  }

  void cancel() {
    _cancelled = true;
    _extractProcess?.kill();
    _extractProcess = null;
    state = const DecodeState();
  }

  void reset() => state = const DecodeState();
}

final decodeProvider =
    NotifierProvider<DecodeNotifier, DecodeState>(DecodeNotifier.new);
