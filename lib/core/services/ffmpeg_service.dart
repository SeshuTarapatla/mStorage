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

  /// Builds a 5-second mask video from [posterPath].
  /// Fixes aspect ratio: scale-to-fit + letterbox/pillarbox to 1920x1080.
  static Future<ProcessResult> generateMaskVideo({
    required String posterPath,
    required String outputPath,
    required String date,
    required String time,
    int durationSeconds = 5,
  }) async {
    final ffmpeg = await binaryPath;
    final creationTime = '${date}T$time';
    final scaleFilter =
        'scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=black';
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
