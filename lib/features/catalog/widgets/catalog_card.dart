import 'dart:async';
import 'dart:math' show max;
import 'dart:ui' show ImageFilter;
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../core/services/catalog_cache_manager.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tab_colors.dart';
import '../imdb_service.dart';
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
                rating: widget.entry.imdbRating,
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
                    if (widget.entry.genres.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 20,
                        child: ClipRect(
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: widget.entry.genres
                                .take(3)
                                .map((t) => _Tag(tag: t, palette: palette))
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

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Expanded card — used by the catalog screen's local overlay stack
// ---------------------------------------------------------------------------

class CatalogCardExpanded extends StatefulWidget {
  final CatalogEntry entry;
  final TabPalette palette;
  final VoidCallback onClose;
  final VoidCallback onOpenInBrowser;
  final double maxHeight;

  const CatalogCardExpanded({
    super.key,
    required this.entry,
    required this.palette,
    required this.onClose,
    required this.onOpenInBrowser,
    this.maxHeight = 640,
  });

  @override
  State<CatalogCardExpanded> createState() => CatalogCardExpandedState();
}

class CatalogCardExpandedState extends State<CatalogCardExpanded> {
  final _pageController = PageController();
  int _currentPage = 0;
  List<String> _images = [];
  Timer? _timer;

  static const _autoAdvanceInterval = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    final thumb = widget.entry.thumbnailUrl;
    if (thumb.isNotEmpty) _images = [thumb];
    _loadImages();
  }

  Future<void> _loadImages() async {
    final entry = widget.entry;
    final thumb = entry.thumbnailUrl;

    // Sheet-curated images take priority over the API
    if (entry.slideImages.isNotEmpty) {
      setState(() {
        _images = [
          if (thumb.isNotEmpty) thumb,
          ...entry.slideImages.where((u) => u != thumb),
        ];
      });
      _startTimer();
      return;
    }

    final imdbId = entry.imdbId;
    if (imdbId.isEmpty) return;
    final urls = await ImdbService().fetchImages(imdbId);
    if (!mounted || urls.isEmpty) return;
    final extras = urls.where((u) => u != thumb).toList();
    setState(() {
      _images = [if (thumb.isNotEmpty) thumb, ...extras];
    });
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    if (_images.length <= 1) return;
    _timer = Timer.periodic(_autoAdvanceInterval, (_) => navigate(1));
  }

  /// Moves [delta] steps (positive = forward, negative = backward).
  /// Called externally via GlobalKey for arrow-key navigation.
  void navigate(int delta) {
    if (_images.length <= 1) return;
    _startTimer(); // reset auto-advance interval on any navigation
    final next = (_currentPage + delta) % _images.length;
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  void _goToPage(int index) {
    if (index == _currentPage) return;
    navigate(index - _currentPage);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final palette = widget.palette;

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
          // Slideshow — fixed height banner at the top
          if (_images.isNotEmpty)
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(15)),
              child: SizedBox(
                height: 220,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PageView.builder(
                      controller: _pageController,
                      onPageChanged: (i) =>
                          setState(() => _currentPage = i),
                      itemCount: _images.length,
                      itemBuilder: (_, i) =>
                          _SlideshowPage(url: _images[i]),
                    ),
                    if (_images.length > 1)
                      Positioned(
                        bottom: 8,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            _images.length,
                            (i) => GestureDetector(
                              onTap: () => _goToPage(i),
                              child: _SlideshowDot(
                                active: i == _currentPage,
                                color: palette.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          // Body — Flexible so it fills remaining height without overflowing
          Flexible(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + close — always visible
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
                  // Scrollable middle — pills, stars, description, tags
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (entry.imdbRating != null)
                                _Pill(
                                  icon: Icons.star_rounded,
                                  label: entry.imdbRating!
                                      .toStringAsFixed(1),
                                  color: const Color(0xFFF5C518),
                                ),
                              if (entry.runtimeLabel != null)
                                _Pill(
                                  icon: Icons.schedule_rounded,
                                  label: entry.runtimeLabel!,
                                ),
                              if (entry.certificate != null)
                                _Pill(
                                  icon: Icons.verified_user_rounded,
                                  label: entry.certificate!,
                                ),
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
                              if (entry.language != null)
                                _Pill(
                                  icon: Icons.translate_rounded,
                                  label: entry.language!,
                                ),
                              if (entry.encoded)
                                _Pill(
                                  icon: Icons.lock_rounded,
                                  label: 'Encoded',
                                  color: palette.primary,
                                ),
                            ],
                          ),
                          if (entry.stars.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              entry.stars.join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11, color: kTextMuted),
                            ),
                          ],
                          if (entry.plot.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              entry.plot,
                              style: const TextStyle(
                                fontSize: 12,
                                color: kTextSecondary,
                                height: 1.55,
                              ),
                            ),
                          ],
                          if (entry.genres.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: entry.genres
                                  .map((t) => _Tag(tag: t, palette: palette))
                                  .toList(),
                            ),
                          ],
                          if (entry.tags.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: entry.tags
                                  .map((t) => _Tag(
                                        tag: t,
                                        palette: palette,
                                        muted: true,
                                      ))
                                  .toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Button — always visible at the bottom
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: entry.videoUrl.isNotEmpty
                          ? widget.onOpenInBrowser
                          : null,
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
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// Per-session cache: URL → normalized crop rect (0–1 coordinates).
// Rect.largest sentinel means "analyzed, no meaningful crop found".
final _cropRectCache = <String, Rect>{};

void clearSlideCropCache() => _cropRectCache.clear();

class _SlideshowPage extends StatefulWidget {
  final String url;
  const _SlideshowPage({required this.url});

  @override
  State<_SlideshowPage> createState() => _SlideshowPageState();
}

class _SlideshowPageState extends State<_SlideshowPage> {
  bool _isLandscape = false;
  // null = analysis in progress; Rect.largest = no crop needed.
  Rect? _cropRect;

  @override
  void initState() {
    super.initState();
    _detectOrientationAndCrop();
  }

  void _detectOrientationAndCrop() {
    // Return cached result immediately if available.
    if (_cropRectCache.containsKey(widget.url)) {
      _cropRect = _cropRectCache[widget.url];
    }

    final provider = CachedNetworkImageProvider(
      widget.url,
      cacheManager: CatalogCacheManager.instance,
    );
    final stream = provider.resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, _) async {
        stream.removeListener(listener);
        final image = info.image;
        final isLandscape = image.width > image.height;

        // Only run pixel analysis if not already cached.
        final crop = _cropRectCache.containsKey(widget.url)
            ? _cropRectCache[widget.url]!
            : await _detectDarkBorders(widget.url, image);

        if (mounted) setState(() { _isLandscape = isLandscape; _cropRect = crop; });
      },
      onError: (_, _) => stream.removeListener(listener),
    );
    stream.addListener(listener);
  }

  // Scans edge rows/columns for near-black pixels and returns a normalized
  // content rect. Returns Rect.largest if no meaningful border is detected.
  static Future<Rect> _detectDarkBorders(String url, ui.Image image) async {
    const kDarkThreshold  = 20;   // per-channel brightness to call a pixel "dark"
    const kDarkRowRatio   = 0.90; // fraction of sampled pixels that must be dark
    const kMinBorderFrac  = 0.02; // ignore borders thinner than 2 % of the dimension

    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bytes == null) {
      _cropRectCache[url] = Rect.largest;
      return Rect.largest;
    }

    final w    = image.width;
    final h    = image.height;
    final data = bytes.buffer.asUint8List();
    final xStep = max(1, w ~/ 30); // sample ~30 columns per row scan
    final yStep = max(1, h ~/ 30); // sample ~30 rows per column scan

    bool isRowDark(int y) {
      int dark = 0, total = 0;
      for (var x = 0; x < w; x += xStep) {
        final i = (y * w + x) * 4;
        if (data[i] < kDarkThreshold && data[i + 1] < kDarkThreshold && data[i + 2] < kDarkThreshold) dark++;
        total++;
      }
      return dark / total >= kDarkRowRatio;
    }

    bool isColDark(int x) {
      int dark = 0, total = 0;
      for (var y = 0; y < h; y += yStep) {
        final i = (y * w + x) * 4;
        if (data[i] < kDarkThreshold && data[i + 1] < kDarkThreshold && data[i + 2] < kDarkThreshold) dark++;
        total++;
      }
      return dark / total >= kDarkRowRatio;
    }

    int top = 0;
    while (top < h && isRowDark(top)) { top++; }
    int bottom = h - 1;
    while (bottom > top && isRowDark(bottom)) { bottom--; }
    int left = 0;
    while (left < w && isColDark(left)) { left++; }
    int right = w - 1;
    while (right > left && isColDark(right)) { right--; }

    final lf = left  / w;
    final tf = top   / h;
    final rf = (right  + 1) / w;
    final bf = (bottom + 1) / h;

    // Discard trivially small borders (noise / gradients).
    final crop = (lf < kMinBorderFrac && tf < kMinBorderFrac &&
                  rf > 1 - kMinBorderFrac && bf > 1 - kMinBorderFrac)
        ? Rect.largest
        : Rect.fromLTRB(lf, tf, rf, bf);

    _cropRectCache[url] = crop;
    return crop;
  }

  // Renders [provider] cropped to [crop] (normalized 0–1 rect) via a Positioned
  // child that is scaled and offset so the content fills the container exactly.
  Widget _croppedImage(ImageProvider provider, Rect crop) {
    final cx = (crop.left + crop.right)   / 2;
    final cy = (crop.top  + crop.bottom)  / 2;
    final scale = max(1.0 / crop.width, 1.0 / crop.height);

    return LayoutBuilder(builder: (_, constraints) {
      final w  = constraints.maxWidth;
      final h  = constraints.maxHeight;
      final sw = w * scale;
      final sh = h * scale;
      return ClipRect(
        child: SizedBox.expand(
          child: Stack(children: [
            Positioned(
              left:  w / 2 - cx * sw,
              top:   h / 2 - cy * sh,
              width:  sw,
              height: sh,
              child: Image(image: provider, fit: BoxFit.fill),
            ),
          ]),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final crop = _cropRect;
    // Only apply crop-and-zoom for landscape images; portrait posters in a
    // landscape container must use contain — the _croppedImage math assumes
    // image and container share the same aspect ratio (BoxFit.fill would stretch).
    final hasCrop = crop != null && crop != Rect.largest && _isLandscape;
    final foregroundFit = _isLandscape ? BoxFit.cover : BoxFit.contain;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Blurred background — always cover.
        CachedNetworkImage(
          imageUrl: widget.url,
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
        // Foreground — crop borders if detected, otherwise use normal fit.
        CachedNetworkImage(
          imageUrl: widget.url,
          cacheManager: CatalogCacheManager.instance,
          fit: hasCrop ? BoxFit.fill : foregroundFit,
          placeholder: (_, _) => const SizedBox.shrink(),
          errorWidget:  (_, _, _) => const SizedBox.shrink(),
          imageBuilder: hasCrop
              ? (_, ip) => _croppedImage(ip, crop)
              : null,
        ),
      ],
    );
  }
}

class _SlideshowDot extends StatelessWidget {
  final bool active;
  final Color color;
  const _SlideshowDot({required this.active, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 3),
      width: active ? 16 : 6,
      height: 6,
      decoration: BoxDecoration(
        color: active ? color : Colors.white.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

class _Thumbnail extends StatefulWidget {
  final String url;
  final double aspectRatio;
  final double? rating;

  const _Thumbnail({
    required this.url,
    required this.aspectRatio,
    this.rating,
  });

  @override
  State<_Thumbnail> createState() => _ThumbnailState();
}

class _ThumbnailState extends State<_Thumbnail> {
  // Default false (portrait) — updates after image dimensions are known.
  bool _isLandscape = false;

  @override
  void initState() {
    super.initState();
    _detectOrientation();
  }

  void _detectOrientation() {
    if (widget.url.isEmpty) return;
    final provider = CachedNetworkImageProvider(
      widget.url,
      cacheManager: CatalogCacheManager.instance,
    );
    final stream = provider.resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, _) {
        stream.removeListener(listener);
        if (mounted) {
          setState(() => _isLandscape = info.image.width > info.image.height);
        }
      },
      onError: (_, _) => stream.removeListener(listener),
    );
    stream.addListener(listener);
  }

  @override
  Widget build(BuildContext context) {
    // Portrait → cover (fills slot, minor crop on edges).
    // Landscape → contain (shows full image, blur fills the gaps).
    final foregroundFit = _isLandscape ? BoxFit.contain : BoxFit.cover;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: widget.url.isNotEmpty
            ? Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: widget.url,
                    cacheManager: CatalogCacheManager.instance,
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
                    imageUrl: widget.url,
                    cacheManager: CatalogCacheManager.instance,
                    fit: foregroundFit,
                    placeholder: (_, _) => const SizedBox.shrink(),
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                  ),
                  if (widget.rating != null)
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: _RatingBadge(rating: widget.rating!),
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
  final bool muted;
  const _Tag({required this.tag, required this.palette, this.muted = false});

  @override
  Widget build(BuildContext context) {
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
