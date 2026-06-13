import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../core/services/catalog_cache_manager.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tab_colors.dart';
import '../models/catalog_entry.dart';

class CatalogDetailPanel extends StatelessWidget {
  final CatalogEntry entry;
  final VoidCallback onClose;
  final VoidCallback onOpenInBrowser;

  const CatalogDetailPanel({
    super.key,
    required this.entry,
    required this.onClose,
    required this.onOpenInBrowser,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppTab.catalog.palette;

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: kSurfaceColor,
        border: Border(left: BorderSide(color: kBorderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(entry: entry, palette: palette, onClose: onClose),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (entry.thumbnailUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: entry.thumbnailUrl,
                        cacheManager: CatalogCacheManager.instance,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        placeholder: (_, _) => Container(height: 160, color: kSurface2Color),
                        errorWidget: (_, _, _) => Container(
                          height: 160,
                          color: kSurface2Color,
                          child: Icon(Icons.movie_rounded, color: kTextMuted, size: 40),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (entry.plot.isNotEmpty) ...[
                    Text(
                      entry.plot,
                      style: TextStyle(fontSize: 13, color: kTextSecondary, height: 1.5),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _MetaRow(label: 'Date', value: _formatDate(entry.date)),
                  if (entry.sizeMb != null)
                    _MetaRow(label: 'Size', value: '${entry.sizeMb} MB'),
                  _MetaRow(
                    label: 'Encoded',
                    value: entry.encoded ? 'Yes' : 'No',
                    valueColor: entry.encoded ? palette.primary : kTextMuted,
                  ),
                  if (entry.genres.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: entry.genres
                          .map((t) => _TagChip(tag: t, palette: palette))
                          .toList(),
                    ),
                  ],
                  if (entry.tags.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: entry.tags
                          .map((t) => _TagChip(tag: t, palette: palette, muted: true))
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: entry.videoUrl.isNotEmpty ? onOpenInBrowser : null,
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('View & Download'),
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.primary,
                        foregroundColor: onAccentColor(palette.primary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '—';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}

class _Header extends StatelessWidget {
  final CatalogEntry entry;
  final TabPalette palette;
  final VoidCallback onClose;

  const _Header({required this.entry, required this.palette, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: kBorderColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              entry.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
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
              child: Icon(Icons.close_rounded, size: 18, color: kTextMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _MetaRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(label, style: TextStyle(fontSize: 12, color: kTextMuted)),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: valueColor ?? kTextSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String tag;
  final TabPalette palette;
  final bool muted;

  const _TagChip({required this.tag, required this.palette, this.muted = false});

  @override
  Widget build(BuildContext context) {
    final color = muted ? kTextMuted : palette.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(tag, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}
