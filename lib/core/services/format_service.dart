import 'dart:io';
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
  /// Scans the entire file for the separator (fixes the legacy 1 MB bug).
  static Future<bool> extractArchive({
    required String inputPath,
    required String outputArchivePath,
  }) async {
    final input = File(inputPath).openSync();
    try {
      final fileLen = await File(inputPath).length();
      const chunkSize = 1024 * 1024; // 1 MB read window
      int offset = 0;
      int sepOffset = -1;

      // Sliding-window search for separator
      Uint8List? tail;
      while (offset < fileLen) {
        final toRead = (offset + chunkSize > fileLen)
            ? (fileLen - offset).toInt()
            : chunkSize;
        input.setPositionSync(offset);
        final chunk = input.readSync(toRead);

        // Combine tail of previous read with current chunk to handle splits
        final search = tail != null
            ? Uint8List.fromList([...tail, ...chunk])
            : Uint8List.fromList(chunk);

        final idx = _findSeparator(search);
        if (idx != -1) {
          // Absolute offset of separator start
          final tailLen = tail?.length ?? 0;
          sepOffset = offset - tailLen + idx;
          break;
        }

        tail = chunk.length >= _separatorBytes.length
            ? Uint8List.fromList(
                chunk.sublist(chunk.length - _separatorBytes.length))
            : chunk;
        offset += toRead;
      }

      if (sepOffset == -1) return false;

      final payloadStart = sepOffset + _separatorBytes.length;
      final out = File(outputArchivePath).openWrite();
      try {
        input.setPositionSync(payloadStart);
        while (true) {
          final block = input.readSync(chunkSize);
          if (block.isEmpty) break;
          out.add(block);
        }
      } finally {
        await out.close();
      }
      return true;
    } finally {
      input.closeSync();
    }
  }

  static int _findSeparator(Uint8List data) {
    final sep = _separatorBytes;
    outer:
    for (int i = 0; i <= data.length - sep.length; i++) {
      for (int j = 0; j < sep.length; j++) {
        if (data[i + j] != sep[j]) continue outer;
      }
      return i;
    }
    return -1;
  }
}
