import 'dart:ui' show ImageFilter;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tab_colors.dart';
import '../models/catalog_entry.dart';

class CatalogCard extends StatefulWidget {
  final CatalogEntry entry;
  final double aspectRatio;
  final VoidCallback onOpenInBrowser;
  final void Function(Rect globalRect) onExpand;

  const CatalogCard({
    super.key,
    required this.entry,
    required this.aspectRatio,
    required this.onOpenInBrowser,
    required this.onExpand,
  });

  @override
  State<CatalogCard> createState() => _CatalogCardState();
}

class _CatalogCardState extends State<CatalogCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppTab.catalog.palette;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          final box = context.findRenderObject() as RenderBox;
          widget.onExpand(box.localToGlobal(Offset.zero) & box.size);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _hovered ? kSurface2Color : kSurfaceColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered
                  ? palette.primary.withValues(alpha: 0.5)
                  : kBorderColor,
            ),
            boxShadow: _hovered
                ? [BoxShadow(color: palette.glow, blurRadius: 12)]
                : [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _Thumbnail(
                url: widget.entry.thumbnailUrl,
                aspectRatio: widget.aspectRatio,
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: kTextPrimary,
                      ),
                    ),
                    if (widget.entry.date != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        _fmt(widget.entry.date!),
                        style:
                            const TextStyle(fontSize: 11, color: kTextMuted),
                      ),
                    ],
                    if (widget.entry.tags.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: widget.entry.tags
                            .take(3)
                            .map((t) => _Tag(tag: t, palette: palette))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Expanded card — used by the catalog screen's local overlay stack
// ---------------------------------------------------------------------------

class CatalogCardExpanded extends StatelessWidget {
  final CatalogEntry entry;
  final TabPalette palette;
  final VoidCallback onClose;
  final VoidCallback onOpenInBrowser;

  const CatalogCardExpanded({
    super.key,
    required this.entry,
    required this.palette,
    required this.onClose,
    required this.onOpenInBrowser,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: kSurfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: palette.primary.withValues(alpha: 0.45),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(color: palette.glow, blurRadius: 48, spreadRadius: 4),
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.6), blurRadius: 24),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entry.thumbnailUrl.isNotEmpty)
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(15)),
              child: SizedBox(
                height: 280,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: entry.thumbnailUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, _) =>
                          Container(color: kSurface2Color),
                      errorWidget: (_, _, _) =>
                          Container(color: kSurface2Color),
                      imageBuilder: (_, ip) => ImageFiltered(
                        imageFilter:
                            ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                        child: Image(image: ip, fit: BoxFit.cover),
                      ),
                    ),
                    Container(
                        color: Colors.black.withValues(alpha: 0.22)),
                    CachedNetworkImage(
                      imageUrl: entry.thumbnailUrl,
                      fit: BoxFit.contain,
                      placeholder: (_, _) => const SizedBox.shrink(),
                      errorWidget: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        entry.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: kTextPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: onClose,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.close_rounded,
                            size: 18, color: kTextMuted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (entry.date != null)
                      _Pill(
                        icon: Icons.calendar_today_rounded,
                        label: _fmtDate(entry.date!),
                      ),
                    if (entry.sizeMb != null)
                      _Pill(
                        icon: Icons.storage_rounded,
                        label: '${entry.sizeMb} MB',
                      ),
                    if (entry.encoded)
                      _Pill(
                        icon: Icons.lock_rounded,
                        label: 'Encoded',
                        color: palette.primary,
                      ),
                  ],
                ),
                if (entry.description.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    entry.description,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: kTextSecondary,
                      height: 1.55,
                    ),
                  ),
                ],
                if (entry.tags.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: entry.tags
                        .map((t) => _Tag(tag: t, palette: palette))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        entry.photosUrl.isNotEmpty ? onOpenInBrowser : null,
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('View & Download'),
                    style: FilledButton.styleFrom(
                      backgroundColor: palette.primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

class _Thumbnail extends StatelessWidget {
  final String url;
  final double aspectRatio;

  const _Thumbnail({required this.url, required this.aspectRatio});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: url.isNotEmpty
            ? Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => _placeholder(),
                    errorWidget: (_, _, _) => _placeholder(),
                    imageBuilder: (_, ip) => ImageFiltered(
                      imageFilter:
                          ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                      child: Image(image: ip, fit: BoxFit.cover),
                    ),
                  ),
                  Container(color: Colors.black.withValues(alpha: 0.18)),
                  CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.contain,
                    placeholder: (_, _) => const SizedBox.shrink(),
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                  ),
                ],
              )
            : _placeholder(),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: kSurface2Color,
        child: const Icon(Icons.movie_rounded, color: kTextMuted, size: 32),
      );
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _Pill({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? kTextSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: c),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: c)),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String tag;
  final TabPalette palette;
  const _Tag({required this.tag, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: palette.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child:
          Text(tag, style: TextStyle(fontSize: 10, color: palette.primary)),
    );
  }
}
