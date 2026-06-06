import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../../core/theme/app_theme.dart';

const _kVideoExts = {'mp4', 'mkv', 'avi', 'mov', 'webm'};

class ExtractedFilesList extends StatelessWidget {
  final List<String> files;
  final Color accentColor;
  final ValueChanged<String>? onOpenInPlayer;

  const ExtractedFilesList({
    super.key,
    required this.files,
    required this.accentColor,
    this.onOpenInPlayer,
  });

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Extracted files (${files.length})',
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: kTextSecondary),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: kSurface2Color,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kBorderColor),
          ),
          child: Column(
            children: [
              for (int i = 0; i < files.length; i++) ...[
                if (i > 0) Divider(height: 1, color: kBorderColor),
                _FileRow(
                  path: files[i],
                  accentColor: accentColor,
                  onOpenInPlayer: _kVideoExts.contains(
                          p.extension(files[i]).replaceFirst('.', '').toLowerCase())
                      ? onOpenInPlayer
                      : null,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  final String path;
  final Color accentColor;
  final ValueChanged<String>? onOpenInPlayer;

  const _FileRow({
    required this.path,
    required this.accentColor,
    this.onOpenInPlayer,
  });

  IconData _iconFor(String ext) {
    return switch (ext) {
      'mp4' || 'mkv' || 'avi' || 'mov' || 'webm' => Icons.movie_rounded,
      'srt' || 'ass' || 'vtt' => Icons.subtitles_rounded,
      'jpg' || 'jpeg' || 'png' || 'webp' => Icons.image_rounded,
      _ => Icons.insert_drive_file_rounded,
    };
  }

  String _sizeLabel(String path) {
    try {
      final bytes = File(path).lengthSync();
      if (bytes < 1024) return '${bytes}B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    final name = p.basename(path);
    final size = _sizeLabel(path);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(_iconFor(ext), color: accentColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(fontSize: 13, color: kTextPrimary),
                    overflow: TextOverflow.ellipsis),
                if (size.isNotEmpty)
                  Text(size,
                      style:
                          const TextStyle(fontSize: 11, color: kTextMuted)),
              ],
            ),
          ),
          if (onOpenInPlayer != null)
            IconButton(
              icon: Icon(Icons.play_circle_rounded,
                  size: 16, color: accentColor),
              onPressed: () => onOpenInPlayer!(path),
              tooltip: 'Open in Player',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.folder_open_rounded,
                size: 16, color: kTextMuted),
            onPressed: () => Process.run('explorer', ['/select,', path]),
            tooltip: 'Show in Explorer',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}
