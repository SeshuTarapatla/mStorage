import 'dart:io';
import 'dart:ui' show ImageFilter;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../core/providers/decode_request_provider.dart';
import '../../../core/providers/player_request_provider.dart';
import '../../../core/services/catalog_cache_manager.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tab_colors.dart';
import '../../../core/util/filename_sanitizer.dart';
import '../catalog_notifier.dart'
    show DownloadActive, DownloadRecord, downloadHistoryProvider, downloadProvider;
import '../models/series_entry.dart';
import '../widgets/webview_overlay.dart';
import '../../shell/app_shell.dart' show activeTabProvider;

class SeriesDetailScreen extends ConsumerStatefulWidget {
  final SeriesEntry entry;
  final VoidCallback onBack;

  const SeriesDetailScreen({super.key, required this.entry, required this.onBack});

  @override
  ConsumerState<SeriesDetailScreen> createState() =>
      _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends ConsumerState<SeriesDetailScreen> {
  int _seasonIndex = 0;


  @override
  Widget build(BuildContext context) {
    final e = widget.entry;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TopBar(title: e.title, onBack: widget.onBack),
        Divider(height: 1, thickness: 1, color: kBorderColor),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 288,
                child: _LeftPanel(entry: e),
              ),
              VerticalDivider(width: 1, thickness: 1, color: kBorderColor),
              Expanded(
                child: _RightPanel(
                  entry: e,
                  seasonIndex: _seasonIndex,
                  onSeasonChanged: (i) => setState(() => _seasonIndex = i),
                  onEpisodeDownload: _onEpisodeDownload,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _onEpisodeDownload(int seasonNumber, EpisodeEntry ep) {
    final e = widget.entry;
    final epCode =
        'S${seasonNumber.toString().padLeft(2, '0')}E${ep.episodeNumber.toString().padLeft(2, '0')}';
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => WebViewOverlay(
        url: ep.videoUrl,
        title: ep.displayTitle,
        onDownloadRequested: (dlUrl, filename) {
          ref.read(downloadProvider.notifier).enqueue(
                dlUrl, filename ?? '', ep.displayTitle, e.posterUrl,
                subtitle: '$epCode — ${e.title}');
        },
      ),
    );
  }

}

// ---------------------------------------------------------------------------
// Top bar
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;

  const _TopBar({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          InkWell(
            onTap: onBack,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back_rounded,
                      size: 16, color: kSeriesPalette.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Back',
                    style: TextStyle(
                      fontSize: 13,
                      color: kSeriesPalette.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: kTextPrimary,
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Left panel — poster + meta
// ---------------------------------------------------------------------------

class _LeftPanel extends StatelessWidget {
  final SeriesEntry entry;

  const _LeftPanel({required this.entry});

  @override
  Widget build(BuildContext context) {
    final e = entry;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Poster
          if (e.posterUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: e.posterUrl,
                      cacheManager: CatalogCacheManager.instance,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(color: kSurface2Color),
                      errorWidget: (_, _, _) => Container(color: kSurface2Color),
                      imageBuilder: (_, ip) => ImageFiltered(
                        imageFilter:
                            ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                        child: Image(image: ip, fit: BoxFit.cover),
                      ),
                    ),
                    Container(color: Colors.black.withValues(alpha: 0.15)),
                    CachedNetworkImage(
                      imageUrl: e.posterUrl,
                      cacheManager: CatalogCacheManager.instance,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => const SizedBox.shrink(),
                      errorWidget: (_, _, _) => const SizedBox.shrink(),
                    ),
                    if (e.imdbRating != null)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: _RatingBadge(rating: e.imdbRating!),
                      ),
                  ],
                ),
              ),
            )
          else
            AspectRatio(
              aspectRatio: 2 / 3,
              child: Container(
                decoration: BoxDecoration(
                  color: kSurface2Color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    Icon(Icons.live_tv_rounded, color: kTextMuted, size: 48),
              ),
            ),

          const SizedBox(height: 16),

          // Meta pills
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Pill(
                icon: Icons.live_tv_rounded,
                label: e.seasons.length == 1
                    ? '1 Season'
                    : '${e.seasons.length} Seasons',
              ),
              _Pill(
                icon: Icons.video_library_rounded,
                label: '${e.totalEpisodes} Episodes',
              ),
              if (e.certificate != null)
                _Pill(icon: Icons.verified_user_rounded, label: e.certificate!),
              if (e.language != null)
                _Pill(icon: Icons.translate_rounded, label: e.language!),
            ],
          ),

          // Genres
          if (e.genres.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: e.genres.map((g) => _Tag(tag: g)).toList(),
            ),
          ],

          // Tags
          if (e.tags.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: e.tags.map((t) => _Tag(tag: t, muted: true)).toList(),
            ),
          ],

          // Plot
          if (e.plot.isNotEmpty) ...[
            const SizedBox(height: 14),
            Divider(color: kBorderColor),
            const SizedBox(height: 10),
            Text(
              e.plot,
              style: TextStyle(
                fontSize: 12,
                color: kTextSecondary,
                height: 1.65,
              ),
            ),
          ],

          // Stars
          if (e.stars.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              e.stars.join(' · '),
              style: TextStyle(fontSize: 11, color: kTextMuted),
            ),
          ],

        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Right panel — season selector + episode list
// ---------------------------------------------------------------------------

class _RightPanel extends StatelessWidget {
  final SeriesEntry entry;
  final int seasonIndex;
  final ValueChanged<int> onSeasonChanged;
  final void Function(int seasonNumber, EpisodeEntry) onEpisodeDownload;

  const _RightPanel({
    required this.entry,
    required this.seasonIndex,
    required this.onSeasonChanged,
    required this.onEpisodeDownload,
  });

  @override
  Widget build(BuildContext context) {
    final e = entry;

    if (e.seasons.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.video_library_outlined, size: 48, color: kTextMuted),
            const SizedBox(height: 16),
            Text(
              'No episodes yet',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: kTextPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'Add rows to the Episodes sheet to get started.',
              style: TextStyle(fontSize: 13, color: kTextMuted),
            ),
          ],
        ),
      );
    }

    final season = e.seasons[seasonIndex.clamp(0, e.seasons.length - 1)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Season selector
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(e.seasons.length, (i) {
                final s = e.seasons[i];
                final active = i == seasonIndex;
                return _SeasonPill(
                  label: 'Season ${s.number}',
                  count: s.episodes.length,
                  active: active,
                  onTap: () => onSeasonChanged(i),
                );
              }),
            ),
          ),
        ),
        Divider(height: 1, thickness: 1, color: kBorderColor),
        // Episode list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            itemCount: season.episodes.length,
            itemBuilder: (context, i) {
              final ep = season.episodes[i];
              return _EpisodeDetailRow(
                episode: ep,
                onDownload: () => onEpisodeDownload(season.number, ep),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Season pill selector
// ---------------------------------------------------------------------------

class _SeasonPill extends StatelessWidget {
  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  const _SeasonPill({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = kSeriesPalette;
    final color = active ? palette.primary : kTextMuted;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: active
                ? palette.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active
                  ? palette.primary.withValues(alpha: 0.6)
                  : kBorderColor,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      active ? FontWeight.w600 : FontWeight.w400,
                  color: color,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count ep',
                style: TextStyle(
                  fontSize: 10,
                  color: active ? palette.secondary : kTextMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Episode detail row
// ---------------------------------------------------------------------------

class _EpisodeDetailRow extends ConsumerStatefulWidget {
  final EpisodeEntry episode;
  final VoidCallback onDownload;

  const _EpisodeDetailRow({
    required this.episode,
    required this.onDownload,
  });

  @override
  ConsumerState<_EpisodeDetailRow> createState() => _EpisodeDetailRowState();
}

class _EpisodeDetailRowState extends ConsumerState<_EpisodeDetailRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = kSeriesPalette;
    final ep = widget.episode;
    final dlState = ref.watch(downloadProvider);
    final activeDl = dlState is DownloadActive && dlState.title == ep.displayTitle
        ? dlState
        : null;
    final history = ref.watch(downloadHistoryProvider);
    final downloadRecord = history.cast<DownloadRecord?>().firstWhere(
      (r) => r!.title == ep.displayTitle && File(r.filePath).existsSync(),
      orElse: () => null,
    );
    final settings = ref.watch(settingsProvider);
    final decodeDir = settings.decodeOutputDirectory.isEmpty
        ? AppDirectories.decoded
        : settings.decodeOutputDirectory;
    final decodedPath = _decodedVideoPath(decodeDir, ep.displayTitle);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.only(bottom: 8),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: _hovered ? kSurface2Color : kSurfaceColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _hovered
                ? palette.primary.withValues(alpha: 0.35)
                : kBorderColor,
          ),
          boxShadow: _hovered
              ? [BoxShadow(color: palette.glow.withValues(alpha: 0.25), blurRadius: 8)]
              : [],
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Thumbnail — flush left, full card height
              SizedBox(
                width: 120,
                child: ep.posterUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: ep.posterUrl,
                        cacheManager: CatalogCacheManager.instance,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(color: kSurface2Color),
                        errorWidget: (_, _, _) =>
                            Container(color: kSurface2Color),
                      )
                    : Container(
                        color: kSurface2Color,
                        child: Icon(Icons.movie_rounded,
                            size: 22, color: kTextMuted),
                      ),
              ),
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 0, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title row + plot + meta
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Episode number + title + rating on one line
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  'E${ep.episodeNumber.toString().padLeft(2, '0')}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: palette.primary,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    ep.displayTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: kTextPrimary,
                                    ),
                                  ),
                                ),
                                if (ep.imdbRating != null) ...[
                                  const SizedBox(width: 8),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.star_rounded,
                                          size: 11, color: Color(0xFFF5C518)),
                                      const SizedBox(width: 3),
                                      Text(
                                        ep.imdbRating!.toStringAsFixed(1),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFFF5C518),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                            if (ep.plot.isNotEmpty) ...[
                              const SizedBox(height: 5),
                              Text(
                                ep.plot,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: kTextSecondary,
                                  height: 1.5,
                                ),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                if (ep.airDate != null)
                                  _MetaChip(label: _fmtDate(ep.airDate!)),
                                if (ep.runtimeLabel.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  _MetaChip(label: ep.runtimeLabel),
                                ],
                                if (ep.sizeMb != null) ...[
                                  const SizedBox(width: 6),
                                  _MetaChip(label: '${ep.sizeMb} MB'),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Action button: progress → play → decode → download
                      if (ep.videoUrl.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 10, right: 12),
                          child: Center(
                            child: activeDl != null
                                ? _EpisodeProgressBtn(
                                    received: activeDl.receivedBytes,
                                    total: activeDl.totalBytes,
                                    color: palette.primary,
                                  )
                                : decodedPath != null
                                    ? _ActionBtn(
                                        icon: Icons.play_circle_rounded,
                                        label: 'Play',
                                        color: palette.primary,
                                        onTap: () {
                                          ref.read(playerOpenRequestProvider.notifier).state =
                                              decodedPath;
                                          ref.read(activeTabProvider.notifier).state =
                                              AppTab.player;
                                        },
                                      )
                                    : downloadRecord != null
                                        ? _ActionBtn(
                                            icon: Icons.lock_open_rounded,
                                            label: 'Decode',
                                            color: palette.primary,
                                            onTap: () {
                                              ref.read(decodeOpenRequestProvider.notifier).state =
                                                  downloadRecord.filePath;
                                              ref.read(activeTabProvider.notifier).state =
                                                  AppTab.decode;
                                            },
                                          )
                                        : _ActionBtn(
                                            icon: Icons.download_rounded,
                                            label: 'Download',
                                            color: palette.primary,
                                            onTap: widget.onDownload,
                                          ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static const _kVideoExts = {'mp4', 'mkv', 'avi', 'mov', 'webm'};

  static String? _decodedVideoPath(String decodeDir, String title) {
    final folder = Directory(p.join(decodeDir, sanitizeFilename(title)));
    if (!folder.existsSync()) return null;
    try {
      for (final entry in folder.listSync()) {
        if (entry is File) {
          final ext = p.extension(entry.path).replaceFirst('.', '').toLowerCase();
          if (_kVideoExts.contains(ext)) return entry.path;
        }
      }
    } catch (_) {}
    return null;
  }
}

// ---------------------------------------------------------------------------
// Action button
// ---------------------------------------------------------------------------

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Episode download progress button
// ---------------------------------------------------------------------------

class _EpisodeProgressBtn extends StatelessWidget {
  final int received;
  final int total;
  final Color color;

  const _EpisodeProgressBtn({
    required this.received,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total > 0 ? received / total : null;
    final label = progress != null
        ? '${(progress * 100).toStringAsFixed(0)}%'
        : 'Loading…';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 2,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Meta chip
// ---------------------------------------------------------------------------

class _MetaChip extends StatelessWidget {
  final String label;
  const _MetaChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: kSurface2Color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: kTextMuted),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helpers (mirrored from series_card.dart)
// ---------------------------------------------------------------------------

class _RatingBadge extends StatelessWidget {
  final double rating;
  const _RatingBadge({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 10, color: Color(0xFFF5C518)),
          const SizedBox(width: 3),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Pill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = kTextSecondary;
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
  final bool muted;
  const _Tag({required this.tag, this.muted = false});

  @override
  Widget build(BuildContext context) {
    final palette = kSeriesPalette;
    final color = muted ? kTextMuted : palette.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(tag, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}
