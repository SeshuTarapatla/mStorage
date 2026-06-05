import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_theme.dart';

class FileDropZone extends StatefulWidget {
  final String label;
  final String hint;
  final String? currentPath;
  final List<String> allowedExtensions;
  final Color accentColor;
  final ValueChanged<String> onFilePicked;
  final VoidCallback? onTap;
  final void Function(List<String>)? onMultiFileDrop;
  final VoidCallback? onClear;

  const FileDropZone({
    super.key,
    required this.label,
    required this.hint,
    required this.accentColor,
    required this.onFilePicked,
    this.currentPath,
    this.allowedExtensions = const [],
    this.onTap,
    this.onMultiFileDrop,
    this.onClear,
  });

  @override
  State<FileDropZone> createState() => _FileDropZoneState();
}

class _FileDropZoneState extends State<FileDropZone> {
  bool _isDragging = false;
  bool _isHovered = false;

  bool get _isActive => _isDragging || _isHovered;

  @override
  Widget build(BuildContext context) {
    final hasFile = widget.currentPath != null && widget.currentPath!.isNotEmpty;

    return Stack(
      children: [
        DropTarget(
          onDragEntered: (_) => setState(() => _isDragging = true),
          onDragExited: (_) => setState(() => _isDragging = false),
          onDragDone: (details) {
            setState(() => _isDragging = false);
            final files = details.files;
            if (files.isEmpty) return;
            if (files.length > 1 && widget.onMultiFileDrop != null) {
              widget.onMultiFileDrop!(files.map((f) => f.path).toList());
              return;
            }
            final path = files.first.path;
            final ext = path.split('.').last.toLowerCase();
            if (widget.allowedExtensions.isEmpty ||
                widget.allowedExtensions.contains(ext)) {
              widget.onFilePicked(path);
            }
          },
          child: MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                decoration: BoxDecoration(
                  color: _isActive
                      ? widget.accentColor.withValues(alpha: 0.08)
                      : kSurface2Color,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _isDragging
                        ? widget.accentColor
                        : _isHovered
                            ? widget.accentColor.withValues(alpha: 0.6)
                            : hasFile
                                ? widget.accentColor.withValues(alpha: 0.5)
                                : kBorderColor,
                    width: _isDragging ? 2 : 1.5,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: hasFile
                          ? Icon(Icons.check_circle_rounded,
                              key: const ValueKey('check'),
                              color: widget.accentColor,
                              size: 36)
                          : Icon(
                              _isDragging
                                  ? Icons.file_download_rounded
                                  : Icons.upload_file_rounded,
                              key: ValueKey(_isDragging),
                              color: _isActive ? widget.accentColor : kTextMuted,
                              size: 36,
                            ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      hasFile
                          ? widget.currentPath!.split(r'\').last.split('/').last
                          : widget.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: hasFile
                            ? widget.accentColor
                            : _isHovered
                                ? widget.accentColor
                                : kTextPrimary,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasFile ? 'Click to change' : widget.hint,
                      style: const TextStyle(fontSize: 12, color: kTextMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        )
            .animate(target: _isDragging ? 1 : 0)
            .scaleXY(end: 1.02, duration: 150.ms, curve: Curves.easeOut),

        // Clear button — outside the GestureDetector so it doesn't open the picker
        if (hasFile && widget.onClear != null)
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: widget.onClear,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kSurface2Color,
                  border: Border.all(color: kBorderColor),
                ),
                child: const Icon(Icons.close_rounded, size: 13, color: kTextMuted),
              ),
            ),
          ),
      ],
    );
  }
}
