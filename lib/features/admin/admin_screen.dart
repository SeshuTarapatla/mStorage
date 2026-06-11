import 'dart:async';
import 'dart:math' show min;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/catalog_cache_manager.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tab_colors.dart';
import '../catalog/imdb_service.dart';
import '../catalog/models/imdb_data.dart';
import '../catalog/models/episode_sheet_schema.dart';
import '../catalog/models/series_entry.dart';
import '../catalog/models/series_sheet_schema.dart';
import '../catalog/models/sheet_schema.dart';
import '../catalog/series_notifier.dart';

final _adminPalette = AppTab.admin.palette;

// Amber badge for top-4 slide picks.
const _kTop4Color = Color(0xFFF59E0B);

enum _AdminMode { movie, series, episode }

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  final _imdbIdCtrl = TextEditingController();

  bool _fetching = false;
  String? _error;
  ImdbData? _data;

  List<String> _genres = [];
  List<String> _tags = [];
  final _tagInputCtrl   = TextEditingController();
  final _tagFocusNode   = FocusNode();
  final _genreInputCtrl = TextEditingController();
  final _genreFocusNode = FocusNode();

  // ── Extra sheet fields (not from IMDB) ───────────────────────────────────
  final _videoUrlCtrl    = TextEditingController();
  final _languageCtrl    = TextEditingController();
  final _languageFocusNode = FocusNode();
  final _sizeMbCtrl      = TextEditingController();
  bool _encoded = true;
  bool _show    = true;

  // ── Series mode ──────────────────────────────────────────────────────────
  _AdminMode _mode = _AdminMode.movie;
  final _seriesImdbCtrl     = TextEditingController();
  final _seriesImdbFocusNode = FocusNode();
  final _seasonCtrl     = TextEditingController(text: '1');
  final _episodeCtrl    = TextEditingController(text: '1');
  ImdbData? _episodeData; // episode IMDB data (fetched from _imdbIdCtrl in series mode)

  // All images fetched from API (up to 100).
  List<String> _allImages = [];

  // Ordered preference queue — front = highest priority.
  // Positions 0-3 are slide_images (amber star); 4+ are cyan border.
  List<String> _selected = [];

  // Cursor for the next images page; null = no more pages available.
  String? _nextPageToken;
  // True while a "Load more" or paste-enrichment API call is in flight.
  bool _loadingMore = false;

  // Brief highlight on pool image tap; auto-clears after 200 ms.
  String? _flashUrl;
  Timer?  _flashTimer;

  // Inline paste-validation error; auto-clears after 3 s.
  String? _pasteError;
  Timer?  _pasteErrorTimer;

  int? _selectedYear;
  int  _selectedMonth = 1;
  int  _selectedDay   = 1;

  void _onFieldChanged() {
    if (mounted && _data != null) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    for (final c in [
      _videoUrlCtrl, _languageCtrl, _sizeMbCtrl,
      _seasonCtrl, _episodeCtrl,
    ]) {
      c.addListener(_onFieldChanged);
    }
  }

  @override
  void dispose() {
    _imdbIdCtrl.dispose();
    _tagInputCtrl.dispose();
    _tagFocusNode.dispose();
    _genreInputCtrl.dispose();
    _genreFocusNode.dispose();
    _videoUrlCtrl.dispose();
    _languageCtrl.dispose();
    _languageFocusNode.dispose();
    _sizeMbCtrl.dispose();
    _seriesImdbCtrl.dispose();
    _seriesImdbFocusNode.dispose();
    _seasonCtrl.dispose();
    _episodeCtrl.dispose();
    _pasteErrorTimer?.cancel();
    _flashTimer?.cancel();
    super.dispose();
  }

  void _showPasteError(String msg) {
    _pasteErrorTimer?.cancel();
    setState(() => _pasteError = msg);
    _pasteErrorTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _pasteError = null);
    });
  }

  // ── Selection helpers ─────────────────────────────────────────────────────

  // Click: unselected → append to queue; selected → remove.
  void _toggleImage(String url) {
    _flashTimer?.cancel();
    setState(() {
      if (_selected.contains(url)) {
        _selected.remove(url);
      } else {
        _selected.add(url);
      }
      _flashUrl = url;
    });
    _flashTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _flashUrl = null);
    });
  }

  void _removeImage(String url) {
    setState(() => _selected.remove(url));
  }

  // Selected first (queue order), then all remaining unselected API images.
  List<String> get _displayImages {
    final selectedSet = _selected.toSet();
    return [
      ..._selected,
      ..._allImages.where((u) => !selectedSet.contains(u)),
    ];
  }

  // ── Data fetching ─────────────────────────────────────────────────────────

  void _setMode(_AdminMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode             = mode;
      _data             = null;
      _episodeData      = null;
      _error            = null;
      _genres           = [];
      _tags             = [];
      _allImages        = [];
      _selected         = [];
      _videoUrlCtrl.clear();
      _languageCtrl.clear();
      _sizeMbCtrl.clear();
      _seriesImdbCtrl.clear();
      _encoded          = true;
      _show             = true;
      _selectedYear     = null;
      _selectedMonth    = 1;
      _selectedDay      = 1;
      _seasonCtrl.text  = '1';
      _episodeCtrl.text = '1';
    });
  }

  Future<void> _fetch() async {
    final id = _imdbIdCtrl.text.trim();
    if (id.isEmpty) return;
    switch (_mode) {
      case _AdminMode.movie:   await _fetchMovie(id);
      case _AdminMode.series:  await _fetchSeries(id);
      case _AdminMode.episode: await _fetchEpisode(id, _seriesImdbCtrl.text.trim());
    }
  }

  Future<void> _fetchMovie(String id) async {
    setState(() {
      _fetching  = true; _error = null; _data = null; _episodeData = null;
      _genres = []; _tags = []; _allImages = []; _selected = [];
      _videoUrlCtrl.clear(); _languageCtrl.clear(); _sizeMbCtrl.clear();
      _encoded = true; _show = true;
    });
    try {
      final results = await ImdbService().resolve([id]);
      final data = results[id];
      if (!mounted) return;
      if (data == null) {
        setState(() { _error = 'No data found for "$id".'; _fetching = false; });
        return;
      }
      final page1 = await ImdbService().fetchImagesUncached(id);
      if (!mounted) return;
      setState(() {
        _data = data;
        _genres = List<String>.from(data.genres);
        _allImages = page1.images;
        _selected = page1.images.take(4).toList();
        _nextPageToken = page1.nextPageToken;
        _selectedYear  = data.releaseDate?.year;
        _selectedMonth = data.releaseDate?.month ?? 1;
        _selectedDay   = data.releaseDate?.day   ?? 1;
        _fetching = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _fetching = false; });
    }
  }

  Future<void> _fetchSeries(String id) async {
    setState(() {
      _fetching = true; _error = null; _data = null;
      _genres = []; _tags = [];
    });
    try {
      final results = await ImdbService().resolve([id]);
      if (!mounted) return;
      final data = results[id];
      if (data == null) {
        setState(() { _error = 'No data found for "$id".'; _fetching = false; });
        return;
      }
      setState(() {
        _data   = data;
        _genres = List<String>.from(data.genres);
        _fetching = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _fetching = false; });
    }
  }

  Future<void> _fetchEpisode(String episodeId, String seriesId) async {
    if (seriesId.isEmpty) {
      setState(() => _error = 'Series IMDB ID is required.');
      return;
    }
    setState(() {
      _fetching = true; _error = null; _data = null; _episodeData = null;
      _videoUrlCtrl.clear(); _languageCtrl.clear(); _sizeMbCtrl.clear();
      _encoded = true; _show = true;
    });
    try {
      final ids = <String>[seriesId];
      if (episodeId.isNotEmpty) ids.add(episodeId);
      final results = await ImdbService().resolve(ids);
      if (!mounted) return;
      final seriesData = results[seriesId];
      if (seriesData == null) {
        setState(() { _error = 'No series data for "$seriesId".'; _fetching = false; });
        return;
      }
      final epData = episodeId.isNotEmpty ? results[episodeId] : null;
      if (episodeId.isNotEmpty && epData == null) {
        setState(() { _error = 'No episode data for "$episodeId".'; _fetching = false; });
        return;
      }
      setState(() {
        _data        = seriesData;
        _episodeData = epData;
        _selectedYear  = epData?.releaseDate?.year;
        _selectedMonth = 1;
        _selectedDay   = 1;
        _fetching = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _fetching = false; });
    }
  }

  Future<void> _loadMoreImages() async {
    final id = _imdbIdCtrl.text.trim();
    if (id.isEmpty || _loadingMore || _nextPageToken == null) return;
    final token = _nextPageToken!;
    setState(() => _loadingMore = true);
    try {
      final next = await ImdbService().fetchImagesUncached(id, pageToken: token);
      if (!mounted) return;
      final existing = _allImages.toSet();
      final fresh = next.images.where((u) => !existing.contains(u)).toList();
      setState(() {
        _allImages = [..._allImages, ...fresh];
        _nextPageToken = next.nextPageToken;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }


  // ── Clipboard paste ───────────────────────────────────────────────────────

  static final _imdbIdRe = RegExp(r'^tt\d+$');

  Future<void> _pasteFromClipboard() async {
    final clipData = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipData?.text?.trim() ?? '';
    if (text.isEmpty) return;

    // Case 1: bare IMDB ID → just fetch.
    if (_imdbIdRe.hasMatch(text)) {
      _imdbIdCtrl.text = text;
      _fetch();
      return;
    }

    // Case 3: not a TSV row → reject.
    if (!text.contains('\t')) {
      _showPasteError('Invalid clipboard data. Expected an IMDB ID (tt…) or a tab-separated sheet row.');
      return;
    }

    final tabCols = text.split('\t');

    // Case 2a: Series TSV (10 cols) in series mode.
    if (_mode == _AdminMode.series && tabCols.length >= SeriesSheetSchema.columnCount) {
      final sc = SeriesSheetSchema.parseTsv(text);
      final genresRaw = sc[SeriesSheetSchema.iGenres];
      final tagsRaw   = sc[SeriesSheetSchema.iTags];
      final genres = genresRaw.isEmpty ? <String>[] : genresRaw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      final tags   = tagsRaw.isEmpty   ? <String>[] : tagsRaw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      final startYear = int.tryParse(sc[SeriesSheetSchema.iStartYear]);
      final seriesId  = sc[SeriesSheetSchema.iSeriesImdbId];

      setState(() {
        _imdbIdCtrl.text = seriesId;
        _genres  = genres;
        _tags    = tags;
        _show    = sc[SeriesSheetSchema.iShow].toLowerCase() != 'false';
        _data    = ImdbData(
          id: seriesId,
          title: sc[SeriesSheetSchema.iTitle],
          plot: sc[SeriesSheetSchema.iPlot],
          genres: genres,
          releaseDate: startYear != null ? DateTime(startYear) : null,
          posterUrl: sc[SeriesSheetSchema.iPosterUrl],
          rating: double.tryParse(sc[SeriesSheetSchema.iRating]),
          voteCount: null, runtimeSeconds: null, stars: const [], certificate: null,
          endYear: int.tryParse(sc[SeriesSheetSchema.iEndYear]),
        );
        _loadingMore = seriesId.isNotEmpty;
        _fetching    = false;
        _error       = null;
      });

      // Enrich from API in background
      if (seriesId.isEmpty) return;
      try {
        final results = await ImdbService().resolve([seriesId]);
        if (!mounted) return;
        final meta = results[seriesId];
        if (meta == null) { setState(() => _loadingMore = false); return; }
        final pasted = _data!;
        setState(() {
          _data = ImdbData(
            id: seriesId,
            title: pasted.title.isNotEmpty ? pasted.title : meta.title,
            plot: pasted.plot.isNotEmpty ? pasted.plot : meta.plot,
            genres: pasted.genres.isNotEmpty ? pasted.genres : List<String>.from(meta.genres),
            releaseDate: meta.releaseDate ?? pasted.releaseDate,
            posterUrl: pasted.posterUrl.isNotEmpty ? pasted.posterUrl : meta.posterUrl,
            rating: meta.rating, voteCount: meta.voteCount,
            runtimeSeconds: meta.runtimeSeconds,
            stars: meta.stars, certificate: meta.certificate,
            endYear: meta.endYear ?? pasted.endYear,
          );
          _genres      = _data!.genres;
          _loadingMore = false;
        });
      } catch (_) {
        if (mounted) setState(() => _loadingMore = false);
      }
      return;
    }

    // Case 2b: Episode TSV (14 cols) in episode mode.
    if (_mode == _AdminMode.episode && tabCols.length >= EpisodeSheetSchema.columnCount) {
      final ec     = EpisodeSheetSchema.parseTsv(text);
      final epDate = DateTime.tryParse(ec[EpisodeSheetSchema.iAirDate]);
      final seriesId = ec[EpisodeSheetSchema.iSeriesImdbId];

      setState(() {
        _imdbIdCtrl.text     = ec[EpisodeSheetSchema.iEpisodeImdbId];
        _seriesImdbCtrl.text = seriesId;
        _seasonCtrl.text     = ec[EpisodeSheetSchema.iSeason].isNotEmpty ? ec[EpisodeSheetSchema.iSeason] : '1';
        _episodeCtrl.text    = ec[EpisodeSheetSchema.iEpisode].isNotEmpty ? ec[EpisodeSheetSchema.iEpisode] : '1';
        _videoUrlCtrl.text   = ec[EpisodeSheetSchema.iVideoUrl];
        _languageCtrl.text   = ec[EpisodeSheetSchema.iLanguage];
        _sizeMbCtrl.text     = ec[EpisodeSheetSchema.iSizeMb];
        _encoded       = ec[EpisodeSheetSchema.iEncoded].toLowerCase() == 'true';
        _show          = ec[EpisodeSheetSchema.iShow].toLowerCase() != 'false';
        _selectedYear  = epDate?.year;
        _selectedMonth = epDate?.month ?? 1;
        _selectedDay   = epDate?.day   ?? 1;
        _episodeData   = ec[EpisodeSheetSchema.iTitle].isNotEmpty
            ? ImdbData(
                id: ec[EpisodeSheetSchema.iEpisodeImdbId],
                title: ec[EpisodeSheetSchema.iTitle],
                plot: ec[EpisodeSheetSchema.iPlot],
                genres: const [],
                releaseDate: epDate,
                posterUrl: ec[EpisodeSheetSchema.iThumbnailUrl],
                rating: double.tryParse(ec[EpisodeSheetSchema.iRating]),
                voteCount: null, runtimeSeconds: null, stars: const [], certificate: null,
              )
            : null;
        // Minimal series placeholder so form renders; enriched below.
        _data = ImdbData(
          id: seriesId, title: '', plot: '', genres: const [],
          releaseDate: null, posterUrl: '', rating: null,
          voteCount: null, runtimeSeconds: null, stars: const [], certificate: null,
        );
        _allImages = []; _selected = []; _nextPageToken = null;
        _loadingMore = seriesId.isNotEmpty;
        _fetching    = false;
        _error       = null;
      });

      // Enrich series context from API in background
      if (seriesId.isEmpty) return;
      try {
        final results = await ImdbService().resolve([seriesId]);
        if (!mounted) return;
        final meta = results[seriesId];
        if (meta == null) { setState(() => _loadingMore = false); return; }
        setState(() { _data = meta; _loadingMore = false; });
      } catch (_) {
        if (mounted) setState(() => _loadingMore = false);
      }
      return;
    }

    // Case 2b: tab-separated movies sheet row → proceed with full paste.
    final cols = SheetSchema.parseTsv(text);

    final title      = cols[SheetSchema.iTitle];
    final imdbId     = cols[SheetSchema.iImdbId];
    final dateStr    = cols[SheetSchema.iDate];
    final videoUrl   = cols[SheetSchema.iVideoUrl];
    final posterUrl  = cols[SheetSchema.iPosterUrl];
    final sizeMb     = cols[SheetSchema.iSizeMb];
    final language   = cols[SheetSchema.iLanguage];
    final plot       = cols[SheetSchema.iPlot];
    final genresRaw  = cols[SheetSchema.iGenres];
    final tagsRaw    = cols[SheetSchema.iTags];
    final encodedRaw = cols[SheetSchema.iEncoded].toLowerCase();
    final showRaw    = cols[SheetSchema.iShow].toLowerCase();
    final slidesRaw  = cols[SheetSchema.iSlideImages];

    final genres = genresRaw.isEmpty
        ? <String>[]
        : genresRaw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final tags = tagsRaw.isEmpty
        ? <String>[]
        : tagsRaw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    // sheet order (pos 1 first); queue needs newest-first so reverse later
    final slideImages = slidesRaw.isEmpty
        ? <String>[]
        : slidesRaw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    final date = DateTime.tryParse(dateStr);

    // Show clipboard data immediately so the UI is responsive.
    setState(() {
      _imdbIdCtrl.text   = imdbId;
      _videoUrlCtrl.text = videoUrl;
      _languageCtrl.text = language;
      _sizeMbCtrl.text   = sizeMb;
      _encoded = encodedRaw == 'true';
      _show    = showRaw != 'false';
      _selectedYear  = date?.year;
      _selectedMonth = date?.month ?? 1;
      _selectedDay   = date?.day   ?? 1;
      _genres = genres;
      _tags   = tags;
      _data   = ImdbData(
        id: imdbId, title: title, plot: plot, genres: genres,
        releaseDate: date, posterUrl: posterUrl,
        rating: null, voteCount: null, runtimeSeconds: null,
        stars: const [], certificate: null,
      );
      _allImages     = List<String>.from(slideImages);
      _selected      = List<String>.from(slideImages);
      _nextPageToken = null;
      // _loadingMore spinner shows while we enrich from API below
      _loadingMore   = imdbId.isNotEmpty;
      _fetching     = false;
      _error        = null;
    });

    if (imdbId.isEmpty) return;

    // Enrich: fetch metadata + fresh images in parallel; clipboard wins on conflicts.
    try {
      final results = await Future.wait([
        ImdbService().resolve([imdbId]),
        ImdbService().fetchImagesUncached(imdbId),
      ]);
      if (!mounted) return;

      final meta    = (results[0] as Map<String, ImdbData>)[imdbId];
      final page1   = results[1] as ({List<String> images, String? nextPageToken});
      final apiImgs = page1.images;

      // Clipboard values take priority; API fills any gaps.
      final mergedPosterUrl = posterUrl.isNotEmpty ? posterUrl : (meta?.posterUrl ?? '');
      final mergedPlot      = plot.isNotEmpty      ? plot      : (meta?.plot ?? '');
      final mergedGenres    = genres.isNotEmpty    ? genres    : List<String>.from(meta?.genres ?? []);
      final mergedDate      = date ?? meta?.releaseDate;
      final mergedTitle     = title.isNotEmpty     ? title     : (meta?.title ?? '');

      // Image pool: API images first, then any pasted slides not already in pool.
      final apiSet     = apiImgs.toSet();
      final extraSlides = slideImages.where((u) => !apiSet.contains(u)).toList();
      final mergedImages = [...apiImgs, ...extraSlides];

      setState(() {
        _data = ImdbData(
          id: imdbId, title: mergedTitle, plot: mergedPlot,
          genres: mergedGenres, releaseDate: mergedDate, posterUrl: mergedPosterUrl,
          rating: meta?.rating, voteCount: meta?.voteCount,
          runtimeSeconds: meta?.runtimeSeconds,
          stars: meta?.stars ?? const [], certificate: meta?.certificate,
        );
        _genres        = mergedGenres;
        _selectedYear  = mergedDate?.year  ?? _selectedYear;
        _selectedMonth = mergedDate?.month ?? _selectedMonth;
        _selectedDay   = mergedDate?.day   ?? _selectedDay;
        _allImages     = mergedImages;
        _selected      = List<String>.from(slideImages);
        _nextPageToken = page1.nextPageToken;
        _loadingMore   = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  // ── Lightbox ──────────────────────────────────────────────────────────────

  void _showImagePreview(int displayIndex) {
    showGeneralDialog<List<String>>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black.withValues(alpha: 0.9),
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.88, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, _, _) => _ImageLightbox(
        images: _displayImages,
        initialIndex: displayIndex,
        selected: List<String>.from(_selected),
      ),
    ).then((result) {
      if (result != null && mounted) {
        setState(() => _selected = result);
      }
    });
  }

  void _copy(String text) => Clipboard.setData(ClipboardData(text: text));

  String get _dateResult {
    if (_selectedYear == null) return '';
    final m = _selectedMonth.toString().padLeft(2, '0');
    final d = _selectedDay.toString().padLeft(2, '0');
    return '$_selectedYear-$m-$d';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: _pasteError == null
                ? const SizedBox.shrink()
                : Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _adminPalette.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _adminPalette.primary.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 15, color: _adminPalette.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _pasteError!,
                            style: TextStyle(fontSize: 12, color: _adminPalette.secondary),
                          ),
                        ),
                        GestureDetector(
                          onTap: () { _pasteErrorTimer?.cancel(); setState(() => _pasteError = null); },
                          child: Icon(Icons.close_rounded, size: 14, color: _adminPalette.primary),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 20),
          if (_fetching)
            Expanded(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(color: _adminPalette.primary),
                  const SizedBox(height: 12),
                  Text('Fetching from IMDB…',
                      style: TextStyle(fontSize: 13, color: kTextMuted)),
                ]),
              ),
            )
          else if (_error != null)
            Expanded(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 40, color: Colors.redAccent),
                  const SizedBox(height: 12),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, color: kTextSecondary)),
                ]),
              ),
            )
          else if (_data == null)
            Expanded(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.manage_search_rounded, size: 52, color: kTextMuted),
                  const SizedBox(height: 14),
                  Text('Enter an IMDB ID above to get started',
                      style: TextStyle(fontSize: 14, color: kTextMuted)),
                  const SizedBox(height: 6),
                  Text('e.g. tt1234567',
                      style: TextStyle(fontSize: 12, color: kTextMuted)),
                ]),
              ),
            )
          else
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPreview(),
                    const SizedBox(height: 24),
                    if (_mode != _AdminMode.series) ...[
                      _buildDateEditor(
                        label: _mode == _AdminMode.episode ? 'Air Date' : 'Date',
                      ),
                      const SizedBox(height: 24),
                    ],
                    if (_mode != _AdminMode.episode) ...[
                      _buildGenreEditor(),
                      const SizedBox(height: 24),
                      _buildTagsEditor(),
                      const SizedBox(height: 24),
                    ],
                    if (_mode == _AdminMode.episode) ...[
                      _buildEpisodeSection(),
                      const SizedBox(height: 24),
                    ],
                    if (_mode != _AdminMode.series) ...[
                      _buildRowExtras(),
                      const SizedBox(height: 24),
                    ] else ...[
                      Row(children: [
                        _ToggleChip(
                          label: 'Show',
                          value: _show,
                          onChanged: (v) => setState(() => _show = v),
                          palette: _adminPalette,
                        ),
                      ]),
                      const SizedBox(height: 24),
                    ],
                    if (_mode == _AdminMode.movie) ...[
                      _buildImagePicker(),
                      const SizedBox(height: 24),
                    ],
                    _buildResults(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final isEpisode = _mode == _AdminMode.episode;
    return Row(
      children: [
        Icon(Icons.admin_panel_settings_rounded,
            color: _adminPalette.primary, size: 20),
        const SizedBox(width: 8),
        Text('Admin',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _adminPalette.primary)),
        const SizedBox(width: 12),
        // Mode dropdown
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: kSurfaceColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: kBorderColor),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<_AdminMode>(
              value: _mode,
              isDense: true,
              dropdownColor: kSurfaceColor,
              style: TextStyle(fontSize: 13, color: kTextPrimary),
              icon: Icon(Icons.expand_more_rounded, size: 16, color: kTextMuted),
              items: const [
                DropdownMenuItem(value: _AdminMode.movie,   child: Text('Movie')),
                DropdownMenuItem(value: _AdminMode.series,  child: Text('Series')),
                DropdownMenuItem(value: _AdminMode.episode, child: Text('Episode')),
              ],
              onChanged: (v) { if (v != null) _setMode(v); },
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Primary IMDB ID field
        Expanded(
          child: TextField(
            controller: _imdbIdCtrl,
            style: TextStyle(fontSize: 13, color: kTextPrimary),
            decoration: InputDecoration(
              hintText: switch (_mode) {
                _AdminMode.movie    => 'IMDB ID  (e.g. tt30825738)',
                _AdminMode.series   => 'Series IMDB ID  (tt…)',
                _AdminMode.episode  => 'Episode IMDB ID  (tt…)',
              },
              hintStyle: TextStyle(fontSize: 13, color: kTextMuted),
              filled: true,
              fillColor: kSurfaceColor,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: kBorderColor)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: kBorderColor)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: _adminPalette.primary)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            onSubmitted: (_) => _fetch(),
          ),
        ),
        // Series IMDB ID — Episode mode only
        if (isEpisode) ...[
          const SizedBox(width: 8),
          Expanded(child: _buildSeriesIdField()),
        ],
        const SizedBox(width: 8),
        Tooltip(
          message: 'Paste row from clipboard',
          child: IconButton(
            onPressed: _pasteFromClipboard,
            icon: const Icon(Icons.content_paste_rounded, size: 18),
            style: IconButton.styleFrom(
              foregroundColor: kTextSecondary,
              backgroundColor: kSurfaceColor,
              side: BorderSide(color: kBorderColor),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.all(12),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _fetching ? null : _fetch,
          icon: const Icon(Icons.search_rounded, size: 16),
          label: const Text('Fetch'),
          style: FilledButton.styleFrom(
            backgroundColor: _adminPalette.primary,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }

  // ── Series ID autocomplete (Episode mode header) ──────────────────────────

  Widget _buildSeriesIdField() {
    final seriesState = ref.watch(seriesProvider);
    final series = seriesState is SeriesCatalogLoaded
        ? seriesState.series
        : <SeriesEntry>[];

    if (series.isEmpty) {
      return TextField(
        controller: _seriesImdbCtrl,
        focusNode: _seriesImdbFocusNode,
        style: TextStyle(fontSize: 13, color: kTextPrimary),
        decoration: InputDecoration(
          hintText: 'Series IMDB ID  (tt…)  — required',
          hintStyle: TextStyle(fontSize: 13, color: kTextMuted),
          filled: true,
          fillColor: kSurfaceColor,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: kBorderColor)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: kBorderColor)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: kSeriesPalette.primary)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        onSubmitted: (_) => _fetch(),
      );
    }

    return RawAutocomplete<SeriesEntry>(
      textEditingController: _seriesImdbCtrl,
      focusNode: _seriesImdbFocusNode,
      displayStringForOption: (e) => e.imdbId,
      optionsBuilder: (v) {
        if (v.text.isEmpty) return series;
        final q = v.text.toLowerCase();
        return series.where(
          (e) => e.title.toLowerCase().contains(q) || e.imdbId.toLowerCase().contains(q),
        );
      },
      onSelected: (e) {
        _seriesImdbCtrl.text = e.imdbId;
      },
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          color: kSurfaceColor,
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (context, index) {
                final entry = options.elementAt(index);
                return InkWell(
                  onTap: () => onSelected(entry),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.title,
                            style: TextStyle(fontSize: 12, color: kTextPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(entry.imdbId,
                            style: TextStyle(fontSize: 11, color: kTextMuted)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) => TextField(
        controller: controller,
        focusNode: focusNode,
        onSubmitted: (_) { onSubmitted(); _fetch(); },
        style: TextStyle(fontSize: 13, color: kTextPrimary),
        decoration: InputDecoration(
          hintText: 'Series  (search title or paste tt…)',
          hintStyle: TextStyle(fontSize: 13, color: kTextMuted),
          filled: true,
          fillColor: kSurfaceColor,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: kBorderColor)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: kBorderColor)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: kSeriesPalette.primary)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }

  // ── Preview ───────────────────────────────────────────────────────────────

  Widget _buildPreview() {
    final data = _data!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 110,
            height: 165,
            child: data.posterUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: data.posterUrl,
                    fit: BoxFit.cover,
                    cacheManager: CatalogCacheManager.instance,
                    errorWidget: (_, _, _) => _posterPlaceholder(),
                  )
                : _posterPlaceholder(),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(data.title,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: kTextPrimary)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (data.releaseDate != null)
                  _MetaChip(label: '${data.releaseDate!.year}'),
                if (data.rating != null)
                  _MetaChip(
                      label: '★ ${data.rating!.toStringAsFixed(1)}',
                      color: const Color(0xFFF5C518)),
                if (data.runtimeSeconds != null)
                  _MetaChip(label: _fmtRuntime(data.runtimeSeconds!)),
                if (data.certificate != null)
                  _MetaChip(label: data.certificate!),
              ]),
              if (data.plot.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(data.plot,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: kTextSecondary, height: 1.5)),
              ],
              if (data.stars.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(data.stars.join(' · '),
                    style: const TextStyle(fontSize: 11, color: kTextMuted)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _posterPlaceholder() => Container(
      color: kSurface2Color,
      child: const Icon(Icons.movie_rounded, size: 36, color: kTextMuted));

  // ── Date editor ───────────────────────────────────────────────────────────

  static const _kMonths = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static List<int> _daysInMonth(int year, int month) {
    final count = DateUtils.getDaysInMonth(year, month);
    return List.generate(count, (i) => i + 1);
  }

  Widget _buildDateEditor({String label = 'Date'}) {
    final currentYear = DateTime.now().year;
    final years = List.generate(currentYear - 1899, (i) => currentYear - i);
    final days = _daysInMonth(_selectedYear ?? currentYear, _selectedMonth);
    // Clamp day if month/year change reduces days (e.g. Feb 31 → Feb 28).
    final clampedDay = _selectedDay.clamp(1, days.last);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          label: label,
          subtitle: 'API provides year only — fill in month and day if known',
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _DateDropdown<int>(
              label: 'Year',
              value: _selectedYear,
              items: years,
              itemLabel: (y) => '$y',
              hint: 'YYYY',
              width: 100,
              palette: _adminPalette,
              onChanged: (v) => setState(() {
                _selectedYear = v;
                _selectedDay  = _selectedDay.clamp(
                    1, _daysInMonth(v ?? currentYear, _selectedMonth).last);
              }),
            ),
            const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text('–', style: TextStyle(color: kTextMuted))),
            _DateDropdown<int>(
              label: 'Month',
              value: _selectedMonth,
              items: List.generate(12, (i) => i + 1),
              itemLabel: (m) => _kMonths[m - 1],
              hint: 'Month',
              width: 140,
              palette: _adminPalette,
              onChanged: (v) => setState(() {
                _selectedMonth = v ?? 1;
                _selectedDay   = clampedDay.clamp(
                    1, _daysInMonth(_selectedYear ?? currentYear, v ?? 1).last);
              }),
            ),
            const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text('–', style: TextStyle(color: kTextMuted))),
            _DateDropdown<int>(
              label: 'Day',
              value: clampedDay,
              items: days,
              itemLabel: (d) => '$d',
              hint: 'DD',
              width: 76,
              palette: _adminPalette,
              onChanged: (v) => setState(() => _selectedDay = v ?? 1),
            ),
            const SizedBox(width: 12),
            if (_dateResult.isNotEmpty)
              Text(
                _dateResult,
                style: TextStyle(
                    fontSize: 13,
                    color: _adminPalette.primary,
                    fontWeight: FontWeight.w500),
              ),
          ],
        ),
      ],
    );
  }

  // ── Genre editor ──────────────────────────────────────────────────────────

  void _addGenre(String value) {
    final genre = value.trim();
    if (genre.isEmpty || _genres.contains(genre)) {
      _genreInputCtrl.clear();
      _genreFocusNode.requestFocus();
      return;
    }
    setState(() => _genres.add(genre));
    _genreInputCtrl.clear();
    _genreFocusNode.requestFocus();
  }

  Widget _buildGenreEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          label: 'Genres',
          subtitle: 'Drag to reorder — first item shows as primary genre',
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _genreInputCtrl,
                focusNode: _genreFocusNode,
                style: TextStyle(fontSize: 13, color: kTextPrimary),
                decoration: InputDecoration(
                  hintText: 'Add a genre…',
                  hintStyle: TextStyle(fontSize: 13, color: kTextMuted),
                  filled: true,
                  fillColor: kSurfaceColor,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: kBorderColor)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: kBorderColor)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: _adminPalette.primary)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onSubmitted: _addGenre,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => _addGenre(_genreInputCtrl.text),
              style: FilledButton.styleFrom(
                backgroundColor: _adminPalette.primary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Add'),
            ),
          ],
        ),
        if (_genres.isNotEmpty) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: _genres.length * 44.0 + 4),
            child: ReorderableListView.builder(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              onReorder: (oldIdx, newIdx) {
                setState(() {
                  if (newIdx > oldIdx) newIdx--;
                  final item = _genres.removeAt(oldIdx);
                  _genres.insert(newIdx, item);
                });
              },
              itemCount: _genres.length,
              itemBuilder: (_, i) => _GenreRow(
                key: ValueKey(_genres[i]),
                genre: _genres[i],
                index: i,
                isPrimary: i == 0,
                onRemove: () => setState(() => _genres.removeAt(i)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── Tags editor ──────────────────────────────────────────────────────────

  void _addTag(String value) {
    final tag = value.trim();
    if (tag.isEmpty || _tags.contains(tag)) {
      _tagInputCtrl.clear();
      _tagFocusNode.requestFocus();
      return;
    }
    setState(() => _tags.add(tag));
    _tagInputCtrl.clear();
    _tagFocusNode.requestFocus();
  }

  Widget _buildTagsEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          label: 'Tags',
          subtitle: 'Franchise / platform tags (Marvel, Disney…)',
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _tagInputCtrl,
                focusNode: _tagFocusNode,
                style: TextStyle(fontSize: 13, color: kTextPrimary),
                decoration: InputDecoration(
                  hintText: 'Add a tag…',
                  hintStyle: TextStyle(fontSize: 13, color: kTextMuted),
                  filled: true,
                  fillColor: kSurfaceColor,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: kBorderColor)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: kBorderColor)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: _adminPalette.primary)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onSubmitted: _addTag,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => _addTag(_tagInputCtrl.text),
              style: FilledButton.styleFrom(
                backgroundColor: _adminPalette.primary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Add'),
            ),
          ],
        ),
        if (_tags.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _tags.map((tag) => _TagEditorChip(
              tag: tag,
              palette: _adminPalette,
              onRemove: () => setState(() => _tags.remove(tag)),
            )).toList(),
          ),
        ],
      ],
    );
  }

  // ── Image picker ──────────────────────────────────────────────────────────

  Widget _buildImagePicker() {
    final selectedSet = _selected.toSet();
    final unselected  = _allImages.where((u) => !selectedSet.contains(u)).toList();
    final top4Count   = _selected.length.clamp(0, 4);

    // Shared thumbnail image widget.
    Widget thumb(String url) => ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox.expand(
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          cacheManager: CatalogCacheManager.instance,
          errorWidget: (_, _, _) => Container(
            color: kSurface2Color,
            child: const Icon(Icons.broken_image_rounded, size: 24, color: kTextMuted),
          ),
        ),
      ),
    );

    // Zoom icon overlay.
    Widget zoomBtn(int displayIdx) => Positioned(
      bottom: 4, left: 0, right: 0,
      child: Center(
        child: GestureDetector(
          onTap: () => _showImagePreview(displayIdx),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Icon(Icons.zoom_in_rounded, size: 12, color: Colors.white70),
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ───────────────────────────────────────────────────────────
        Row(
          children: [
            _SectionHeader(
              label: 'Slide Images',
              subtitle: 'Long-press selected to drag & reorder  •  click pool to add  •  click selected to remove',
            ),
            const SizedBox(width: 12),
            ...List.generate(4, (i) => Container(
              width: 10, height: 10,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < top4Count ? _kTop4Color : kBorderColor,
              ),
            )),
            const SizedBox(width: 6),
            Text('${_selected.length} selected',
                style: TextStyle(fontSize: 11, color: kTextMuted)),
          ],
        ),

        // ── Selected (drag-and-drop reorderable) ─────────────────────────────
        if (_selected.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _selected.asMap().entries.map((e) {
              final idx    = e.key;
              final url    = e.value;
              final isSlide = idx < 4;
              final badgeColor = isSlide ? _kTop4Color : _adminPalette.primary.withValues(alpha: 0.85);
              final badgeSize  = isSlide ? 22.0 : 18.0;
              final badgeFontSize = isSlide ? 11.0 : 9.0;

              final tile = AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 110, height: 82,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: isSlide ? _kTop4Color : _adminPalette.primary,
                    width: 2.5,
                  ),
                ),
                child: Stack(children: [
                  thumb(url),
                  Positioned(
                    top: 5, right: 5,
                    child: Container(
                      width: badgeSize, height: badgeSize,
                      decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
                      child: Center(child: Text(
                        '${idx + 1}',
                        style: TextStyle(fontSize: badgeFontSize, fontWeight: FontWeight.w700, color: Colors.black),
                      )),
                    ),
                  ),
                  zoomBtn(idx),
                ]),
              );

              return LongPressDraggable<String>(
                data: url,
                delay: const Duration(milliseconds: 150),
                feedback: Material(
                  color: Colors.transparent,
                  child: Opacity(opacity: 0.85, child: SizedBox(width: 110, height: 82, child: tile)),
                ),
                childWhenDragging: Opacity(opacity: 0.25, child: tile),
                child: DragTarget<String>(
                  onWillAcceptWithDetails: (d) => d.data != url,
                  onAcceptWithDetails: (d) {
                    setState(() {
                      final from = _selected.indexOf(d.data);
                      final to   = _selected.indexOf(url);
                      _selected.removeAt(from);
                      _selected.insert(to, d.data);
                    });
                  },
                  builder: (context, candidates, _) {
                    final hovering = candidates.isNotEmpty;
                    return GestureDetector(
                      onTap: () => _toggleImage(url),
                      onSecondaryTap: () => _removeImage(url),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: hovering
                            ? Container(
                                width: 110, height: 82,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(7),
                                  border: Border.all(color: Colors.white70, width: 2.5),
                                  color: Colors.white10,
                                ),
                              )
                            : tile,
                      ),
                    );
                  },
                ),
              );
            }).toList(),
          ),
        ],

        // ── Pool ─────────────────────────────────────────────────────────────
        const SizedBox(height: 12),
        if (unselected.isEmpty && _selected.isEmpty)
          Text('No images returned by API',
              style: TextStyle(fontSize: 12, color: kTextMuted))
        else if (unselected.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...unselected.asMap().entries.map((e) {
                final poolIdx    = e.key;
                final url        = e.value;
                final displayIdx = _selected.length + poolIdx;
                final flashing   = _flashUrl == url;
                return GestureDetector(
                  onTap: () => _toggleImage(url),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 110, height: 82,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: flashing
                              ? _adminPalette.primary
                              : kBorderColor,
                          width: flashing ? 2.0 : 1.0,
                        ),
                        boxShadow: flashing
                            ? [BoxShadow(
                                color: _adminPalette.primary.withValues(alpha: 0.4),
                                blurRadius: 8,
                              )]
                            : [],
                      ),
                      child: Stack(children: [
                        thumb(url),
                        zoomBtn(displayIdx),
                      ]),
                    ),
                  ),
                )
                    .animate()
                    .fadeIn(
                        duration: 250.ms,
                        delay: Duration(milliseconds: min(poolIdx, 8) * 25))
                    .slideY(begin: 0.05, duration: 250.ms, curve: Curves.easeOut);
              }),
              // Load more
              if (_nextPageToken != null || _loadingMore)
                GestureDetector(
                  onTap: _loadingMore ? null : _loadMoreImages,
                  child: MouseRegion(
                    cursor: _loadingMore ? SystemMouseCursors.basic : SystemMouseCursors.click,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 110, height: 82,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: kBorderColor),
                        color: kSurface2Color,
                      ),
                      child: _loadingMore
                          ? Center(child: SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: _adminPalette.primary),
                            ))
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_circle_outline_rounded, size: 22, color: kTextSecondary),
                                const SizedBox(height: 4),
                                Text('Load more', style: TextStyle(fontSize: 10, color: kTextSecondary)),
                              ],
                            ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  // ── Episode section (series mode only) ───────────────────────────────────

  Widget _buildEpisodeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          label: 'Episode',
          subtitle: 'Auto-filled from IMDB — edit if needed',
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 90,
              child: _extrasField(controller: _seasonCtrl, hint: 'season #'),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 90,
              child: _extrasField(controller: _episodeCtrl, hint: 'episode #'),
            ),
          ],
        ),
        if (_episodeData != null) ...[
          const SizedBox(height: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: kSurfaceColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: kSeriesPalette.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                if (_episodeData!.posterUrl.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 80,
                      height: 45,
                      child: CachedNetworkImage(
                        imageUrl: _episodeData!.posterUrl,
                        fit: BoxFit.cover,
                        cacheManager: CatalogCacheManager.instance,
                        errorWidget: (_, _, _) =>
                            Container(color: kSurface2Color),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _episodeData!.title,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: kTextPrimary),
                      ),
                      if (_episodeData!.releaseDate != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          _fmtDate(_episodeData!.releaseDate!),
                          style: const TextStyle(
                              fontSize: 11, color: kTextSecondary),
                        ),
                      ],
                      if (_episodeData!.rating != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '★ ${_episodeData!.rating!.toStringAsFixed(1)}',
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFFF5C518)),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static String _fmtDate(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  List<String> get _seriesRowValues {
    final d = _data!;
    return [
      _imdbIdCtrl.text.trim(),                    // series_imdb_id
      d.title,                                    // title
      d.releaseDate?.year.toString() ?? '',       // start_year
      d.endYear?.toString() ?? '',                // end_year
      d.posterUrl,                                // poster_url
      d.plot,                                     // plot
      d.rating?.toStringAsFixed(1) ?? '',         // rating
      _genres.join(', '),                         // genres
      _tags.join(', '),                           // tags
      _show ? 'TRUE' : 'FALSE',                   // show
    ];
  }

  List<String> get _episodeRowValues {
    final ep = _episodeData!;
    return [
      _imdbIdCtrl.text.trim(),                    // episode_imdb_id
      _seriesImdbCtrl.text.trim(),                // series_imdb_id
      _seasonCtrl.text.trim(),                    // season
      _episodeCtrl.text.trim(),                   // episode
      ep.title,                                   // title
      _dateResult,                                // air_date
      ep.posterUrl,                               // thumbnail_url
      ep.plot,                                    // plot
      ep.rating?.toStringAsFixed(1) ?? '',        // rating
      _videoUrlCtrl.text.trim(),                  // video_url
      _sizeMbCtrl.text.trim(),                    // size_mb
      _languageCtrl.text.trim(),                  // language
      _encoded ? 'TRUE' : 'FALSE',                // encoded
      _show    ? 'TRUE' : 'FALSE',                // show
    ];
  }

  // ── Row extras ────────────────────────────────────────────────────────────

  Widget _buildRowExtras() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          label: 'Row extras',
          subtitle: 'Fields not sourced from IMDB',
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            flex: 3,
            child: _extrasField(
                controller: _videoUrlCtrl,
                hint: 'video_url  (Google Photos album link)'),
          ),
          const SizedBox(width: 8),
          Expanded(child: _languageAutocomplete()),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: _extrasField(
                controller: _sizeMbCtrl, hint: 'size_mb'),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _ToggleChip(
            label: 'Encoded',
            value: _encoded,
            onChanged: (v) => setState(() => _encoded = v),
            palette: _adminPalette,
          ),
          const SizedBox(width: 8),
          _ToggleChip(
            label: 'Show',
            value: _show,
            onChanged: (v) => setState(() => _show = v),
            palette: _adminPalette,
          ),
        ]),
      ],
    );
  }

  static const _languageOptions = ['English', 'Hindi', 'Telugu'];

  Widget _languageAutocomplete() => RawAutocomplete<String>(
        textEditingController: _languageCtrl,
        focusNode: _languageFocusNode,
        optionsBuilder: (TextEditingValue v) {
          if (v.text.isEmpty) return _languageOptions;
          return _languageOptions.where(
              (o) => o.toLowerCase().contains(v.text.toLowerCase()));
        },
        optionsViewBuilder: (context, onSelected, options) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: kSurfaceColor,
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 120),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return InkWell(
                    onTap: () => onSelected(option),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      child: Text(option,
                          style:
                              TextStyle(fontSize: 12, color: kTextPrimary)),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
            TextField(
          controller: controller,
          focusNode: focusNode,
          onSubmitted: (_) => onSubmitted(),
          style: TextStyle(fontSize: 12, color: kTextPrimary),
          decoration: InputDecoration(
            hintText: 'language',
            hintStyle: TextStyle(fontSize: 12, color: kTextMuted),
            filled: true,
            fillColor: kSurfaceColor,
            isDense: true,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: kBorderColor)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: kBorderColor)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: _adminPalette.primary)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          ),
        ),
      );

  Widget _extrasField({
    required TextEditingController controller,
    required String hint,
  }) =>
      TextField(
        controller: controller,
        style: TextStyle(fontSize: 12, color: kTextPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(fontSize: 12, color: kTextMuted),
          filled: true,
          fillColor: kSurfaceColor,
          isDense: true,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: kBorderColor)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: kBorderColor)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: _adminPalette.primary)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        ),
      );

  // ── Results ───────────────────────────────────────────────────────────────

  List<String> get _rowValues {
    final data = _data!;
    return [
      data.title,
      _imdbIdCtrl.text.trim(),
      _dateResult,
      _videoUrlCtrl.text.trim(),
      data.posterUrl,
      _sizeMbCtrl.text.trim(),
      _languageCtrl.text.trim(),
      data.plot,
      _genres.join(', '),
      _tags.join(', '),
      _encoded ? 'TRUE' : 'FALSE',
      _show    ? 'TRUE' : 'FALSE',
      _selected.take(4).join(', '),
    ];
  }

  Widget _buildResults() {
    final List<String> values;
    final List<String> columns;
    final String tsvRow;
    switch (_mode) {
      case _AdminMode.movie:
        values  = _rowValues;
        columns = SheetSchema.columns;
        tsvRow  = SheetSchema.buildTsv(values);
      case _AdminMode.series:
        values  = _seriesRowValues;
        columns = SeriesSheetSchema.columns;
        tsvRow  = SeriesSheetSchema.buildTsv(values);
      case _AdminMode.episode:
        values  = _episodeData != null
            ? _episodeRowValues
            : List.filled(EpisodeSheetSchema.columnCount, '');
        columns = EpisodeSheetSchema.columns;
        tsvRow  = EpisodeSheetSchema.buildTsv(values);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _SectionHeader(
                label: 'Results',
                subtitle: 'Copy individual fields or the full row',
              ),
            ),
            FilledButton.icon(
              onPressed: () => _copy(tsvRow),
              icon: const Icon(Icons.table_rows_rounded, size: 14),
              label: const Text('Copy row'),
              style: FilledButton.styleFrom(
                backgroundColor: _adminPalette.primary,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: kSurfaceColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kBorderColor),
          ),
          child: Column(
            children: [
              for (var i = 0; i < columns.length; i++) ...[
                if (i > 0) Divider(height: 1, color: kBorderColor),
                _ResultRow(
                  label: columns[i],
                  value: values[i],
                  onCopy: values[i].isNotEmpty ? () => _copy(values[i]) : null,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _fmtRuntime(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }
}

// ── Image lightbox ────────────────────────────────────────────────────────────

class _ImageLightbox extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  final List<String> selected;

  const _ImageLightbox({
    required this.images,
    required this.initialIndex,
    required this.selected,
  });

  @override
  State<_ImageLightbox> createState() => _ImageLightboxState();
}

class _ImageLightboxState extends State<_ImageLightbox> {
  late int _currentIndex;
  late List<String> _selected;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _selected = List<String>.from(widget.selected);
  }

  bool _isSelected(String url) => _selected.contains(url);
  bool _isTop4(String url) {
    final idx = _selected.indexOf(url);
    return idx >= 0 && idx < 4;
  }

  void _navigate(int delta) {
    setState(() {
      _currentIndex =
          (_currentIndex + delta + widget.images.length) % widget.images.length;
    });
  }

  void _toggle(String url) {
    setState(() {
      if (_selected.contains(url)) {
        _selected.remove(url);
      } else {
        _selected.add(url);
      }
    });
  }

  void _remove(String url) {
    setState(() => _selected.remove(url));
  }

  void _close() => Navigator.pop(context, _selected);

  @override
  Widget build(BuildContext context) {
    final url      = widget.images[_currentIndex];
    final selected = _isSelected(url);
    final top4     = _isTop4(url);

    final borderColor = top4
        ? _kTop4Color
        : selected
            ? _adminPalette.primary
            : Colors.transparent;

    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        final isPress = event is KeyDownEvent || event is KeyRepeatEvent;
        if (!isPress) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft)  { _navigate(-1); return KeyEventResult.handled; }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) { _navigate(1);  return KeyEventResult.handled; }
        if (event.logicalKey == LogicalKeyboardKey.space)      { _toggle(url);  return KeyEventResult.handled; }
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.delete ||
              event.logicalKey == LogicalKeyboardKey.backspace) {
            _remove(url);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            _close();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.75),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    GestureDetector(
                      onTap: () => _toggle(url),
                      onSecondaryTap: () => _remove(url),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderColor, width: 3),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: CachedNetworkImage(
                              key: ValueKey(url),
                              imageUrl: url,
                              fit: BoxFit.contain,
                              cacheManager: CatalogCacheManager.instance,
                              placeholder: (_, _) => const SizedBox(
                                  width: 400, height: 300,
                                  child: Center(child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white38))),
                              errorWidget: (_, _, _) => Container(
                                  width: 400, height: 300,
                                  color: kSurface2Color,
                                  child: const Icon(Icons.broken_image_rounded,
                                      size: 48, color: kTextMuted)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (widget.images.length > 1) ...[
                      Positioned(
                          left: 0,
                          child: _LightboxNavBtn(
                              icon: Icons.chevron_left_rounded,
                              onTap: () => _navigate(-1))),
                      Positioned(
                          right: 0,
                          child: _LightboxNavBtn(
                              icon: Icons.chevron_right_rounded,
                              onTap: () => _navigate(1))),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${_currentIndex + 1} / ${widget.images.length}',
                    style: const TextStyle(fontSize: 13, color: Colors.white54)),
                const SizedBox(width: 16),
                _LightboxActionBtn(isSelected: selected, isTop4: top4, onTap: () => _toggle(url)),
                const SizedBox(width: 16),
                ...List.generate(4, (i) => Container(
                      width: 10, height: 10,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _selected.length.clamp(0, 4)
                            ? _kTop4Color
                            : Colors.white12,
                      ),
                    )),
                const SizedBox(width: 16),
                TextButton(
                  onPressed: _close,
                  style: TextButton.styleFrom(foregroundColor: Colors.white54),
                  child: const Text('Done', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '← → navigate (hold for fast scroll)  •  Space / click to select  •  Del to remove  •  Esc to close',
              style: const TextStyle(fontSize: 11, color: Colors.white30),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

class _LightboxActionBtn extends StatelessWidget {
  final bool isSelected;
  final bool isTop4;
  final VoidCallback onTap;

  const _LightboxActionBtn({required this.isSelected, required this.isTop4, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (icon, label, bg) = isTop4
        ? (Icons.star_rounded, 'Slide pick — click to remove', _kTop4Color)
        : isSelected
            ? (Icons.check_circle_outline_rounded, 'Selected — click to remove', Colors.white24)
            : (Icons.add_circle_outline_rounded, 'Add to selection', Colors.white24);

    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      style: FilledButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _LightboxNavBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _LightboxNavBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44, height: 80,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white70, size: 28),
      ),
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final String? subtitle;
  const _SectionHeader({required this.label, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _adminPalette.primary,
                letterSpacing: 1.0)),
        if (subtitle != null) ...[
          const SizedBox(width: 10),
          Text(subtitle!, style: TextStyle(fontSize: 11, color: kTextMuted)),
        ],
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final Color? color;
  const _MetaChip({required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: kSurface2Color,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: kBorderColor)),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              color: color ?? kTextSecondary,
              fontWeight: color != null ? FontWeight.w600 : FontWeight.normal)),
    );
  }
}

class _DateDropdown<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<T> items;
  final String Function(T) itemLabel;
  final String hint;
  final double width;
  final TabPalette palette;
  final ValueChanged<T?> onChanged;

  const _DateDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.hint,
    required this.width,
    required this.palette,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    return SizedBox(
      width: width,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontSize: 11, color: kTextMuted),
          filled: true,
          fillColor: kSurfaceColor,
          isDense: true,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(7),
              borderSide: BorderSide(color: kBorderColor)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(7),
              borderSide: BorderSide(color: kBorderColor)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(7),
              borderSide: BorderSide(color: palette.primary)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            hint: Text(hint,
                style: TextStyle(fontSize: 13, color: kTextMuted)),
            isExpanded: true,
            isDense: true,
            dropdownColor: kSurfaceColor,
            style: TextStyle(
                fontSize: 13,
                color: hasValue ? kTextPrimary : kTextMuted),
            icon: Icon(Icons.expand_more_rounded,
                size: 16, color: kTextMuted),
            items: items
                .map((item) => DropdownMenuItem<T>(
                      value: item,
                      child: Text(itemLabel(item),
                          style: TextStyle(
                              fontSize: 13, color: kTextPrimary)),
                    ))
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}

class _GenreRow extends StatelessWidget {
  final String genre;
  final int index;
  final bool isPrimary;
  final VoidCallback onRemove;
  const _GenreRow(
      {super.key,
      required this.genre,
      required this.index,
      required this.isPrimary,
      required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isPrimary
            ? _adminPalette.primary.withValues(alpha: 0.08)
            : kSurface2Color,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: isPrimary
              ? _adminPalette.primary.withValues(alpha: 0.35)
              : kBorderColor,
        ),
      ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Icon(Icons.drag_handle_rounded, size: 16, color: kTextMuted),
            ),
          ),
          Expanded(
            child: Text(genre,
                style: TextStyle(
                    fontSize: 13,
                    color: isPrimary ? kTextPrimary : kTextSecondary,
                    fontWeight: isPrimary ? FontWeight.w600 : FontWeight.normal)),
          ),
          if (isPrimary)
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: _adminPalette.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('primary',
                  style: TextStyle(
                      fontSize: 10,
                      color: _adminPalette.primary,
                      fontWeight: FontWeight.w600)),
            ),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Icon(Icons.close_rounded, size: 14, color: kTextMuted),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final TabPalette palette;

  const _ToggleChip({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: value
              ? palette.primary.withValues(alpha: 0.15)
              : kSurface2Color,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: value
                ? palette.primary.withValues(alpha: 0.45)
                : kBorderColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              size: 14,
              color: value ? palette.primary : kTextMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: value ? palette.primary : kTextSecondary,
                fontWeight: value ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagEditorChip extends StatelessWidget {
  final String tag;
  final TabPalette palette;
  final VoidCallback onRemove;

  const _TagEditorChip({
    required this.tag,
    required this.palette,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4, top: 5, bottom: 5),
      decoration: BoxDecoration(
        color: palette.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: palette.primary.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tag, style: TextStyle(fontSize: 12, color: palette.primary)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close_rounded, size: 14, color: palette.primary),
          ),
        ],
      ),
    );
  }
}


class _ResultRow extends StatefulWidget {
  final String label;
  final String value;
  final VoidCallback? onCopy;
  const _ResultRow({required this.label, required this.value, this.onCopy});

  @override
  State<_ResultRow> createState() => _ResultRowState();
}

class _ResultRowState extends State<_ResultRow> {
  bool _copied = false;

  Future<void> _handleCopy() async {
    widget.onCopy?.call();
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final empty = widget.value.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          SizedBox(
            width: 108,
            child: Text(widget.label,
                style: const TextStyle(
                    fontSize: 12,
                    color: kTextMuted,
                    fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(empty ? '—' : widget.value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    color: empty ? kTextMuted : kTextSecondary)),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _copied
                  ? Row(
                      key: const ValueKey('done'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_rounded,
                            size: 14, color: _adminPalette.primary),
                        const SizedBox(width: 4),
                        Text('Copied',
                            style: TextStyle(
                                fontSize: 11, color: _adminPalette.primary)),
                      ],
                    )
                  : TextButton.icon(
                      key: const ValueKey('copy'),
                      onPressed: empty ? null : _handleCopy,
                      icon: const Icon(Icons.copy_rounded, size: 13),
                      label: const Text('Copy', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor:
                            empty ? kTextMuted : _adminPalette.primary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
