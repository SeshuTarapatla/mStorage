import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

const _separator = '\nbreakpoint\n';
final _separatorBytes = Uint8List.fromList(_separator.codeUnits);

class FormatService {
  /// Appends [mask] + separator + [archive] into [outputPath].
  static Future<void> combine({
    required String maskPath,
    required String archivePath,
    required String outputPath,
  }) async {
    final out = File(outputPath).openWrite();
    try {
      await out.addStream(File(maskPath).openRead());
      out.add(_separatorBytes);
      await out.addStream(File(archivePath).openRead());
    } finally {
      await out.close();
    }
  }

  /// Extracts the archive payload from an encoded MP4 into [outputArchivePath].
  /// Runs in a background isolate to avoid freezing the UI on large files.
  static Future<bool> extractArchive({
    required String inputPath,
    required String outputArchivePath,
  }) =>
      Isolate.run(() => _doExtractArchive(inputPath, outputArchivePath));

  static bool _doExtractArchive(String inputPath, String outputArchivePath) {
    const chunkSize = 1024 * 1024;
    final input = File(inputPath).openSync();
    try {
      final fileLen = input.lengthSync();
      final tailSize = _separatorBytes.length - 1; // 12 bytes — only what's needed to catch splits
      int offset = 0;
      int sepOffset = -1;
      Uint8List? tail;

      while (offset < fileLen) {
        final toRead = (offset + chunkSize > fileLen)
            ? (fileLen - offset).toInt()
            : chunkSize;
        input.setPositionSync(offset);
        final chunk = input.readSync(toRead);

        final Uint8List search;
        if (tail != null) {
          search = Uint8List(tail.length + chunk.length)
            ..setRange(0, tail.length, tail)
            ..setRange(tail.length, tail.length + chunk.length, chunk);
        } else {
          search = chunk;
        }

        final idx = _findSeparator(search);
        if (idx != -1) {
          final tailLen = tail?.length ?? 0;
          sepOffset = offset - tailLen + idx;
          break;
        }

        tail = chunk.length >= tailSize
            ? Uint8List.fromList(chunk.sublist(chunk.length - tailSize))
            : Uint8List.fromList(chunk);
        offset += toRead;
      }

      if (sepOffset == -1) return false;

      final payloadStart = sepOffset + _separatorBytes.length;
      final out = File(outputArchivePath).openSync(mode: FileMode.write);
      try {
        input.setPositionSync(payloadStart);
        while (true) {
          final block = input.readSync(chunkSize);
          if (block.isEmpty) break;
          out.writeFromSync(block);
        }
      } finally {
        out.closeSync();
      }
      return true;
    } finally {
      input.closeSync();
    }
  }

  static int _findSeparator(Uint8List data) {
    final sep = _separatorBytes;
    final first = sep[0];
    outer:
    for (int i = 0; i <= data.length - sep.length; i++) {
      if (data[i] != first) continue;
      for (int j = 1; j < sep.length; j++) {
        if (data[i + j] != sep[j]) continue outer;
      }
      return i;
    }
    return -1;
  }
}
