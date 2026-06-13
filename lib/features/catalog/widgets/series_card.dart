import 'dart:ui' show ImageFilter;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../core/services/catalog_cache_manager.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tab_colors.dart';
import '../models/series_entry.dart';

// ---------------------------------------------------------------------------
// Compact grid card — one per series
// ---------------------------------------------------------------------------

class SeriesCard extends StatefulWidget {
  final SeriesEntry entry;
  final double aspectRatio;
  final bool isDownloaded;
  final VoidCallback onExpand;

  const SeriesCard({
    super.key,
    required this.entry,
    required this.aspectRatio,
    this.isDownloaded = false,
    required this.onExpand,
  });

  @override
  State<SeriesCard> createState() => _SeriesCardState();
}

class _SeriesCardState extends State<SeriesCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = kSeriesPalette;
    final e = widget.entry;
    final seasonCount  = e.seasons.length;
    final episodeCount = e.totalEpisodes;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onExpand,
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
              Stack(
                children: [
                  _SeriesThumbnail(
                    url: e.posterUrl,
                    aspectRatio: widget.aspectRatio,
                    rating: e.imdbRating,
                  ),
                  if (widget.isDownloaded)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: const Icon(Icons.download_done_rounded,
                          size: 16, color: Color(0xFFEA580C)),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: kTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _countLabel(seasonCount, episodeCount),
                      style: TextStyle(fontSize: 11, color: kTextMuted),
                    ),
                    if (e.genres.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 20,
                        child: ClipRect(
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: e.genres
                                .take(3)
                                .map((t) => _Tag(tag: t))
                                .toList(),
                          ),
                        ),
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

  static String _countLabel(int seasons, int episodes) {
    final s = seasons == 1 ? '1 season' : '$seasons seasons';
    final e = episodes == 1 ? '1 episode' : '$episodes episodes';
    return '$s · $e';
  }
}

// ---------------------------------------------------------------------------
// Expanded overlay card
// ---------------------------------------------------------------------------

class SeriesCardExpanded extends StatefulWidget {
  final SeriesEntry entry;
  final VoidCallback onClose;
  final void Function(SeriesEntry entry, String videoUrl) onOpenEpisode;
  final void Function(String videoUrl, String title, String thumbnailUrl)
      onDownloadEpisode;
  final double maxHeight;

  const SeriesCardExpanded({
    super.key,
    required this.entry,
    required this.onClose,
    required this.onOpenEpisode,
    required this.onDownloadEpisode,
    this.maxHeight = 640,
  });

  @override
  State<SeriesCardExpanded> createState() => SeriesCardExpandedState();
}

class SeriesCardExpandedState extends State<SeriesCardExpanded> {
  // Track which seasons are expanded; default first season open
  late Set<int> _expandedSeasons;

  @override
  void initState() {
    super.initState();
    _expandedSeasons = widget.entry.seasons.isNotEmpty
        ? {widget.entry.seasons.first.number}
        : {};
  }

  @override
  Widget build(BuildContext context) {
    final palette = kSeriesPalette;
    final e = widget.entry;

    return Container(
      clipBehavior: Clip.antiAlias,
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
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
          // Poster banner
          if (e.posterUrl.isNotEmpty)
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(15)),
              child: SizedBox(
                height: 200,
                width: double.infinity,
                child: _PosterBanner(url: e.posterUrl),
              ),
            ),
          // Content
          Flexible(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          e.title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: kTextPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: widget.onClose,
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
                  // Scrollable body
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Meta pills
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (e.imdbRating != null)
                                _Pill(
                                  icon: Icons.star_rounded,
                                  label: e.imdbRating!.toStringAsFixed(1),
                                  color: const Color(0xFFF5C518),
                                ),
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
                              if (e.language != null)
                                _Pill(
                                  icon: Icons.translate_rounded,
                                  label: e.language!,
                                ),
                            ],
                          ),
                          // Genres
                          if (e.genres.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: e.genres
                                  .map((t) => _Tag(tag: t))
                                  .toList(),
                            ),
                          ],
                          // Tags
                          if (e.tags.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: e.tags
                                  .map((t) => _Tag(tag: t, muted: true))
                                  .toList(),
                            ),
                          ],
                          // Plot
                          if (e.plot.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              e.plot,
                              style: TextStyle(
                                fontSize: 12,
                                color: kTextSecondary,
                                height: 1.55,
                              ),
                            ),
                          ],
                          // Season accordion
                          if (e.seasons.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            ...e.seasons.map(
                              (season) => _SeasonSection(
                                season: season,
                                expanded:
                                    _expandedSeasons.contains(season.number),
                                onToggle: () => setState(() {
                                  if (_expandedSeasons
                                      .contains(season.number)) {
                                    _expandedSeasons.remove(season.number);
                                  } else {
                                    _expandedSeasons.add(season.number);
                                  }
                                }),
                                onOpen: (ep) => widget.onOpenEpisode(
                                    widget.entry, ep.videoUrl),
                                onDownload: (ep) {
                                  final label = ep.displayTitle.isNotEmpty
                                      ? ep.displayTitle
                                      : 'Episode ${ep.episodeNumber}';
                                  widget.onDownloadEpisode(
                                    ep.videoUrl,
                                    '${e.title} S${_pad(season.number)}E${_pad(ep.episodeNumber)} — $label',
                                    e.posterUrl,
                                  );
                                },
                              ),
                            ),
                          ],
                        ],
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

  static String _pad(int n) => n.toString().padLeft(2, '0');
}

// ---------------------------------------------------------------------------
// Season section — collapsible
// ---------------------------------------------------------------------------

class _SeasonSection extends StatelessWidget {
  final SeasonEntry season;
  final bool expanded;
  final VoidCallback onToggle;
  final void Function(EpisodeEntry) onOpen;
  final void Function(EpisodeEntry) onDownload;

  const _SeasonSection({
    required this.season,
    required this.expanded,
    required this.onToggle,
    required this.onOpen,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final palette = kSeriesPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Season header
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(Icons.chevron_right_rounded,
                      size: 16, color: palette.primary),
                ),
                const SizedBox(width: 6),
                Text(
                  'Season ${season.number}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: palette.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${season.episodes.length} episodes',
                  style: TextStyle(fontSize: 11, color: kTextMuted),
                ),
              ],
            ),
          ),
        ),
        // Episodes
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Column(
            children: season.episodes
                .map((ep) => _EpisodeRow(
                      episode: ep,
                      onOpen: () => onOpen(ep),
                      onDownload: () => onDownload(ep),
                    ))
                .toList(),
          ),
          crossFadeState: expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
          sizeCurve: Curves.easeOut,
        ),
        Divider(height: 1, color: kBorderColor),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Episode row
// ---------------------------------------------------------------------------

class _EpisodeRow extends StatelessWidget {
  final EpisodeEntry episode;
  final VoidCallback onOpen;
  final VoidCallback onDownload;

  const _EpisodeRow({
    required this.episode,
    required this.onOpen,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final palette = kSeriesPalette;
    final ep = episode;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 5, 0, 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Episode number + optional rating
          SizedBox(
            width: 36,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'E${ep.episodeNumber.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: kTextMuted,
                    fontFamily: 'monospace',
                  ),
                ),
                if (ep.imdbRating != null)
                  Text(
                    '★ ${ep.imdbRating!.toStringAsFixed(1)}',
                    style: const TextStyle(
                      fontSize: 9,
                      color: Color(0xFFF5C518),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ep.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: kTextPrimary),
                ),
                if (ep.plot.isNotEmpty)
                  Text(
                    ep.plot,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10, color: kTextMuted, height: 1.4),
                  )
                else if (ep.airDate != null)
                  Text(
                    _fmtDate(ep.airDate!),
                    style: TextStyle(fontSize: 10, color: kTextMuted),
                  ),
                if (ep.plot.isNotEmpty && ep.airDate != null)
                  Text(
                    _fmtDate(ep.airDate!),
                    style: TextStyle(fontSize: 10, color: kTextMuted),
                  ),
              ],
            ),
          ),
          if (ep.videoUrl.isNotEmpty) ...[
            _EpBtn(
              icon: Icons.open_in_new_rounded,
              tooltip: 'Open',
              color: palette.primary,
              onTap: onOpen,
            ),
            const SizedBox(width: 2),
            _EpBtn(
              icon: Icons.download_rounded,
              tooltip: 'Download',
              color: kTextSecondary,
              onTap: onDownload,
            ),
          ],
        ],
      ),
    );
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _EpBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _EpBtn({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Poster banner (single image, no slideshow for series)
// ---------------------------------------------------------------------------

class _PosterBanner extends StatelessWidget {
  final String url;
  const _PosterBanner({required this.url});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: url,
          cacheManager: CatalogCacheManager.instance,
          fit: BoxFit.cover,
          placeholder: (_, _) => Container(color: kSurface2Color),
          errorWidget: (_, _, _) => Container(color: kSurface2Color),
          imageBuilder: (_, ip) => ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Image(image: ip, fit: BoxFit.cover),
          ),
        ),
        Container(color: Colors.black.withValues(alpha: 0.22)),
        CachedNetworkImage(
          imageUrl: url,
          cacheManager: CatalogCacheManager.instance,
          fit: BoxFit.contain,
          placeholder: (_, _) => const SizedBox.shrink(),
          errorWidget: (_, _, _) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Thumbnail for the compact grid card
// ---------------------------------------------------------------------------

class _SeriesThumbnail extends StatelessWidget {
  final String url;
  final double aspectRatio;
  final double? rating;

  const _SeriesThumbnail({
    required this.url,
    required this.aspectRatio,
    this.rating,
  });

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
                    cacheManager: CatalogCacheManager.instance,
                    memCacheWidth: 400,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => _placeholder(),
                    errorWidget: (_, _, _) => _placeholder(),
                    imageBuilder: (_, ip) => ImageFiltered(
                      imageFilter:
                          ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                      child: Image(image: ip, fit: BoxFit.cover),
                    ),
                  ),
                  Container(
                      color: Colors.black.withValues(alpha: 0.18)),
                  CachedNetworkImage(
                    imageUrl: url,
                    cacheManager: CatalogCacheManager.instance,
                    memCacheWidth: 400,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => const SizedBox.shrink(),
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                  ),
                  if (rating != null)
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: _RatingBadge(rating: rating!),
                    ),
                ],
              )
            : _placeholder(),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: kSurface2Color,
        child: Icon(Icons.live_tv_rounded,
            color: kTextMuted, size: 32),
      );
}

class _RatingBadge extends StatelessWidget {
  final double rating;
  const _RatingBadge({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 9, color: Color(0xFFF5C518)),
          const SizedBox(width: 3),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

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
  final bool muted;
  const _Tag({required this.tag, this.muted = false});

  @override
  Widget build(BuildContext context) {
    final palette = kSeriesPalette;
    final color = muted ? kTextMuted : palette.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(tag, style: TextStyle(fontSize: 10, color: color)),
    );
  }
}
