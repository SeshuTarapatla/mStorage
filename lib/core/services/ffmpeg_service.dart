import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FfmpegService {
  static String? _binaryPath;

  static Future<String> get binaryPath async {
    if (_binaryPath != null) return _binaryPath!;
    final dir = await getApplicationSupportDirectory();
    final dest = p.join(dir.path, 'bin', 'ffmpeg.exe');
    if (!File(dest).existsSync()) {
      await Directory(p.dirname(dest)).create(recursive: true);
      final data = await rootBundle.load('assets/bin/ffmpeg.exe');
      await File(dest).writeAsBytes(data.buffer.asUint8List());
    }
    _binaryPath = dest;
    return dest;
  }

  /// Starts mask video generation and returns the [Process] handle so the
  /// caller can cancel it. Collect stderr and await [Process.exitCode] yourself.
  static Future<Process> startMaskGeneration({
    required String posterPath,
    required String outputPath,
    required String date,
    required String time,
    int durationSeconds = 5,
    bool preserveAspectRatio = true,
    int targetWidth = 1920,
    int targetHeight = 1080,
  }) async {
    final ffmpeg = await binaryPath;
    final creationTime = '${date}T$time';
    final w = targetWidth;
    final h = targetHeight;
    final scaleFilter = preserveAspectRatio
        ? 'scale=$w:$h:force_original_aspect_ratio=decrease,pad=$w:$h:(ow-iw)/2:(oh-ih)/2:color=black'
        : 'scale=$w:$h';
    final args = [
      '-y',
      '-loop', '1',
      '-i', posterPath,
      '-c:v', 'libx264',
      '-t', '$durationSeconds',
      '-pix_fmt', 'yuv420p',
      '-vf', scaleFilter,
      '-metadata', 'creation_time=$creationTime',
      outputPath,
    ];
    return Process.start(ffmpeg, args);
  }

  /// Builds a mask video from [posterPath].
  /// [targetWidth]x[targetHeight] is auto-detected from poster orientation by
  /// the caller. [preserveAspectRatio] letterboxes; false stretches to fill.
  static Future<ProcessResult> generateMaskVideo({
    required String posterPath,
    required String outputPath,
    required String date,
    required String time,
    int durationSeconds = 5,
    bool preserveAspectRatio = true,
    int targetWidth = 1920,
    int targetHeight = 1080,
  }) async {
    final ffmpeg = await binaryPath;
    final creationTime = '${date}T$time';
    final w = targetWidth;
    final h = targetHeight;
    final scaleFilter = preserveAspectRatio
        ? 'scale=$w:$h:force_original_aspect_ratio=decrease,pad=$w:$h:(ow-iw)/2:(oh-ih)/2:color=black'
        : 'scale=$w:$h';
    final args = [
      '-y',
      '-loop', '1',
      '-i', posterPath,
      '-c:v', 'libx264',
      '-t', '$durationSeconds',
      '-pix_fmt', 'yuv420p',
      '-vf', scaleFilter,
      '-metadata', 'creation_time=$creationTime',
      outputPath,
    ];
    return Process.run(ffmpeg, args);
  }

  /// Extracts a single thumbnail frame from [videoPath] at [seekSeconds].
  static Future<ProcessResult> extractThumbnail({
    required String videoPath,
    required String outputPath,
    int seekSeconds = 5,
  }) async {
    final ffmpeg = await binaryPath;
    final args = [
      '-y',
      '-ss', '$seekSeconds',
      '-i', videoPath,
      '-vframes', '1',
      '-q:v', '2',
      outputPath,
    ];
    return Process.run(ffmpeg, args);
  }
}
