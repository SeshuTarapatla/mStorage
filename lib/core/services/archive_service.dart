import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ArchiveService {
  static String? _sevenZipPath;

  static Future<String> get sevenZipPath async {
    if (_sevenZipPath != null) return _sevenZipPath!;
    final dir = await getApplicationSupportDirectory();
    final dest = p.join(dir.path, 'bin', '7za.exe');
    if (!File(dest).existsSync()) {
      await Directory(p.dirname(dest)).create(recursive: true);
      final data = await rootBundle.load('assets/bin/7za.exe');
      await File(dest).writeAsBytes(data.buffer.asUint8List());

      for (final dll in ['7za.dll', '7zxa.dll']) {
        try {
          final bytes = await rootBundle.load('assets/bin/$dll');
          await File(p.join(p.dirname(dest), dll))
              .writeAsBytes(bytes.buffer.asUint8List());
        } catch (_) {}
      }
    }
    _sevenZipPath = dest;
    return dest;
  }

  // ---------------------------------------------------------------------------
  // ZIP STORE writer (no compression, no encryption)
  // ---------------------------------------------------------------------------

  static final _crcTable = _buildCrcTable();
  static List<int> _buildCrcTable() {
    final t = List<int>.filled(256, 0);
    for (int i = 0; i < 256; i++) {
      int c = i;
      for (int j = 0; j < 8; j++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
      }
      t[i] = c;
    }
    return t;
  }

  static int _crc32Update(int crc, Uint8List data) {
    final table = _crcTable;
    for (final b in data) {
      crc = table[(crc ^ b) & 0xFF] ^ (crc >> 8);
    }
    return crc;
  }

  static List<int> _u16(int v) {
    final b = ByteData(2);
    b.setUint16(0, v & 0xFFFF, Endian.little);
    return b.buffer.asUint8List();
  }

  static List<int> _u32(int v) {
    final b = ByteData(4);
    b.setUint32(0, v & 0xFFFFFFFF, Endian.little);
    return b.buffer.asUint8List();
  }

  /// Packages [fileEntries] (sourcePath, archiveName) pairs into a ZIP.
  /// When [password] is set, delegates to 7za for AES-256 encryption via stdin
  /// (avoids copying large video files). Falls back to the pure Dart STORE
  /// writer when no password is required.
  ///
  /// Unencrypted: runs in a background isolate; progress is polled externally
  /// via the output file size. [onProgress] is only called with 1.0 on completion.
  /// Encrypted: [onProgress] fires per 0.5 % of bytes piped to 7za.
  static Future<void> createZip({
    required List<(String, String)> fileEntries,
    required String outputPath,
    String password = '',
    void Function(double)? onProgress,
    void Function(Process)? onProcessStarted,
  }) async {
    if (password.isNotEmpty) {
      await _createEncryptedZip(
        fileEntries, outputPath, password, onProgress,
        onProcessStarted: onProcessStarted,
      );
      return;
    }
    await Isolate.run(() => _doCreateZip(fileEntries, outputPath));
    onProgress?.call(1.0);
  }

  /// Pure-sync ZIP STORE writer — runs inside a background isolate.
  static void _doCreateZip(
    List<(String, String)> fileEntries,
    String outputPath,
  ) {
    final outFile = File(outputPath).openSync(mode: FileMode.write);
    int offset = 0;
    final cdRecords = <List<int>>[];

    void w(List<int> bytes) {
      outFile.writeFromSync(bytes);
      offset += bytes.length;
    }

    try {
      for (final (sourcePath, archiveName) in fileEntries) {
        final nameBytes = utf8.encode(archiveName);
        final localOffset = offset;

        // Local file header (30 bytes + filename)
        w([0x50, 0x4B, 0x03, 0x04]);
        w(_u16(20));
        w(_u16(0x0808));
        w(_u16(0));
        w(_u16(0));
        w(_u16(0));
        w(_u32(0));
        w(_u32(0));
        w(_u32(0));
        w(_u16(nameBytes.length));
        w(_u16(0));
        w(nameBytes);

        // Stream file data, computing CRC-32 incrementally
        final inFile = File(sourcePath).openSync();
        int crc = 0xFFFFFFFF;
        int fileSize = 0;
        try {
          while (true) {
            final block = inFile.readSync(65536);
            if (block.isEmpty) break;
            w(block);
            crc = _crc32Update(crc, block);
            fileSize += block.length;
          }
        } finally {
          inFile.closeSync();
        }
        final finalCrc = (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;

        // Data descriptor
        w([0x50, 0x4B, 0x07, 0x08]);
        w(_u32(finalCrc));
        w(_u32(fileSize));
        w(_u32(fileSize));

        // Central directory record
        final cd = <int>[];
        void cw(List<int> b) => cd.addAll(b);
        cw([0x50, 0x4B, 0x01, 0x02]);
        cw(_u16(20));
        cw(_u16(20));
        cw(_u16(0x0808));
        cw(_u16(0));
        cw(_u16(0));
        cw(_u16(0));
        cw(_u32(finalCrc));
        cw(_u32(fileSize));
        cw(_u32(fileSize));
        cw(_u16(nameBytes.length));
        cw(_u16(0));
        cw(_u16(0));
        cw(_u16(0));
        cw(_u16(0));
        cw(_u32(0));
        cw(_u32(localOffset));
        cw(nameBytes);
        cdRecords.add(cd);
      }

      // Central directory
      final cdOffset = offset;
      for (final rec in cdRecords) {
        w(rec);
      }
      final cdSize = offset - cdOffset;

      // End of central directory record
      w([0x50, 0x4B, 0x05, 0x06]);
      w(_u16(0));
      w(_u16(0));
      w(_u16(cdRecords.length));
      w(_u16(cdRecords.length));
      w(_u32(cdSize));
      w(_u32(cdOffset));
      w(_u16(0));
    } finally {
      outFile.closeSync();
    }
  }

  // ---------------------------------------------------------------------------

  static Future<void> _createEncryptedZip(
    List<(String, String)> fileEntries,
    String outputPath,
    String password,
    void Function(double)? onProgress, {
    void Function(Process)? onProcessStarted,
  }) async {
    final sevenZ = await sevenZipPath;
    int totalBytes = 0;
    for (final (path, _) in fileEntries) {
      try {
        totalBytes += await File(path).length();
      } catch (_) {}
    }
    int processed = 0;
    double lastFrac = 0.0;

    for (final (sourcePath, archiveName) in fileEntries) {
      final process = await Process.start(sevenZ, [
        'a', '-tzip', '-p$password', '-mem=AES256', outputPath, '-si$archiveName',
      ]);
      onProcessStarted?.call(process);

      // addStream provides natural backpressure; map() throttles progress calls.
      final countingStream = File(sourcePath).openRead().map((chunk) {
        processed += chunk.length;
        if (onProgress != null && totalBytes > 0) {
          final frac = (processed / totalBytes).clamp(0.0, 0.99);
          if (frac - lastFrac >= 0.005) {
            lastFrac = frac;
            onProgress(frac);
          }
        }
        return chunk;
      });
      await process.stdin.addStream(countingStream);
      await process.stdin.close();

      final exitCode = await process.exitCode;
      if (exitCode != 0) {
        final err = await process.stderr.transform(utf8.decoder).join();
        throw Exception('7za encryption failed (exit $exitCode): $err');
      }
    }
    onProgress?.call(1.0);
  }

  // ---------------------------------------------------------------------------

  /// Extracts an archive (ZIP or RAR) at [archivePath] into [outputDir].
  static Future<ProcessResult> extractArchive({
    required String archivePath,
    required String outputDir,
    String password = '',
  }) async {
    final sevenZ = await sevenZipPath;
    await Directory(outputDir).create(recursive: true);
    final args = [
      'x',
      archivePath,
      '-o$outputDir',
      '-y',
      if (password.isNotEmpty) '-p$password',
    ];
    return Process.run(sevenZ, args);
  }
}
