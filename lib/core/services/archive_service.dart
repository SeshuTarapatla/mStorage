import 'dart:convert';
import 'dart:io';
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

  static int _crc32Update(int crc, List<int> data) {
    for (final b in data) {
      crc = _crcTable[(crc ^ b) & 0xFF] ^ (crc >> 8);
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

  /// Packages [fileEntries] (sourcePath, archiveName) pairs into a STORE ZIP.
  /// Each file is stored under its [archiveName], allowing in-archive renaming
  /// (e.g., to `<title>.mp4`). Progress is reported inline during streaming.
  static Future<void> createZip({
    required List<(String, String)> fileEntries,
    required String outputPath,
    String password = '',
    void Function(double)? onProgress,
  }) async {
    int totalBytes = 0;
    for (final (path, _) in fileEntries) {
      try {
        totalBytes += await File(path).length();
      } catch (_) {}
    }

    final out = File(outputPath).openWrite();
    int offset = 0;
    int bytesWritten = 0;
    double lastReported = -1.0;
    final cdRecords = <List<int>>[];

    void w(List<int> bytes) {
      out.add(bytes);
      offset += bytes.length;
    }

    try {
      for (final (sourcePath, archiveName) in fileEntries) {
        final nameBytes = utf8.encode(archiveName);
        final localOffset = offset;

        // Local file header (30 bytes + filename)
        w([0x50, 0x4B, 0x03, 0x04]);   // LFH signature
        w(_u16(20));                     // version needed: 2.0
        w(_u16(0x0808));                 // flags: bit3=data-descriptor, bit11=UTF-8
        w(_u16(0));                      // compression: STORE
        w(_u16(0));                      // mod time
        w(_u16(0));                      // mod date
        w(_u32(0));                      // CRC-32 (deferred via data descriptor)
        w(_u32(0));                      // compressed size (deferred)
        w(_u32(0));                      // uncompressed size (deferred)
        w(_u16(nameBytes.length));       // filename length
        w(_u16(0));                      // extra field length
        w(nameBytes);                    // filename

        // Stream file data, computing CRC-32 incrementally
        int crc = 0xFFFFFFFF;
        int fileSize = 0;
        await for (final chunk in File(sourcePath).openRead()) {
          w(chunk);
          crc = _crc32Update(crc, chunk);
          fileSize += chunk.length;
          bytesWritten += chunk.length;
          if (onProgress != null && totalBytes > 0) {
            final frac = (bytesWritten / totalBytes).clamp(0.0, 0.99);
            if (frac - lastReported >= 0.005) {
              lastReported = frac;
              onProgress(frac);
            }
          }
        }
        final finalCrc = (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;

        // Data descriptor (sig + CRC + compressed size + uncompressed size)
        w([0x50, 0x4B, 0x07, 0x08]);   // DD signature
        w(_u32(finalCrc));
        w(_u32(fileSize));
        w(_u32(fileSize));              // compressed == uncompressed for STORE

        // Central directory record for this file
        final cd = <int>[];
        void cw(List<int> b) => cd.addAll(b);
        cw([0x50, 0x4B, 0x01, 0x02]);  // CDR signature
        cw(_u16(20));                    // version made by
        cw(_u16(20));                    // version needed
        cw(_u16(0x0808));                // flags (match LFH)
        cw(_u16(0));                     // compression: STORE
        cw(_u16(0));                     // mod time
        cw(_u16(0));                     // mod date
        cw(_u32(finalCrc));
        cw(_u32(fileSize));              // compressed size
        cw(_u32(fileSize));              // uncompressed size
        cw(_u16(nameBytes.length));      // filename length
        cw(_u16(0));                     // extra field length
        cw(_u16(0));                     // comment length
        cw(_u16(0));                     // disk number start
        cw(_u16(0));                     // internal file attributes
        cw(_u32(0));                     // external file attributes
        cw(_u32(localOffset));           // offset of local header
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
      w([0x50, 0x4B, 0x05, 0x06]);     // EOCD signature
      w(_u16(0));                        // disk number
      w(_u16(0));                        // disk with CD start
      w(_u16(cdRecords.length));         // entries on this disk
      w(_u16(cdRecords.length));         // total entries
      w(_u32(cdSize));                   // CD size
      w(_u32(cdOffset));                 // CD offset
      w(_u16(0));                        // comment length

      await out.flush();
      onProgress?.call(1.0);
    } finally {
      await out.close();
    }
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
