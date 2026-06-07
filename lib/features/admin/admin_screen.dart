import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/catalog_cache_manager.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tab_colors.dart';
import '../catalog/imdb_service.dart';
import '../catalog/models/imdb_data.dart';

final _adminPalette = AppTab.admin.palette;

// Amber badge for top-4 slide picks.
const _kTop4Color = Color(0xFFF59E0B);

// none = not in queue; inQueue = selected pos 5+; top4 = positions 1-4.
enum _ImgState { none, inQueue, top4 }

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _imdbIdCtrl = TextEditingController();

  bool _fetching = false;
  bool _loadingMore = false;
  String? _error;
  ImdbData? _data;

  List<String> _genres = [];
  List<String> _tags = [];
  final _tagInputCtrl = TextEditingController();
  final _tagFocusNode = FocusNode();

  // All images in API order.
  List<String> _allImages = [];

  // Ordered preference queue — front = highest priority.
  // Positions 0-3 are slide_images (amber star); 4+ are cyan border.
  List<String> _selected = [];

  int _imagePage = 0;
  bool _hasMoreImages = false;

  late final TextEditingController _yearCtrl;
  late final TextEditingController _monthCtrl;
  late final TextEditingController _dayCtrl;

  @override
  void initState() {
    super.initState();
    _yearCtrl  = TextEditingController();
    _monthCtrl = TextEditingController(text: '01');
    _dayCtrl   = TextEditingController(text: '01');
    for (final c in [_yearCtrl, _monthCtrl, _dayCtrl]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _imdbIdCtrl.dispose();
    _tagInputCtrl.dispose();
    _tagFocusNode.dispose();
    _yearCtrl.dispose();
    _monthCtrl.dispose();
    _dayCtrl.dispose();
    super.dispose();
  }

  // ── Selection helpers ─────────────────────────────────────────────────────

  _ImgState _stateOf(String url) {
    final idx = _selected.indexOf(url);
    if (idx == -1) return _ImgState.none;
    return idx < 4 ? _ImgState.top4 : _ImgState.inQueue;
  }

  // Left click: unselected → add to front (becomes top pick); selected → remove.
  void _toggleImage(String url) {
    setState(() {
      if (_selected.contains(url)) {
        _selected.remove(url);
      } else {
        _selected.insert(0, url);
      }
    });
  }

  // Right-click: always remove from queue.
  void _removeImage(String url) {
    setState(() => _selected.remove(url));
  }

  // Display order: selected first (queue order), then unselected API images.
  List<String> get _displayImages {
    final selectedSet = _selected.toSet();
    return [
      ..._selected,
      ..._allImages.where((u) => !selectedSet.contains(u)),
    ];
  }

  // ── Data fetching ─────────────────────────────────────────────────────────

  Future<void> _fetch() async {
    final id = _imdbIdCtrl.text.trim();
    if (id.isEmpty) return;
    setState(() {
      _fetching = true;
      _error = null;
      _data = null;
      _genres = [];
      _tags = [];
      _allImages = [];
      _selected = [];
      _imagePage = 0;
      _hasMoreImages = false;
    });

    try {
      final results = await ImdbService().resolve([id]);
      final data = results[id];
      if (!mounted) return;
      if (data == null) {
        setState(() {
          _error = 'No data found for "$id". Check the IMDB ID.';
          _fetching = false;
        });
        return;
      }

      final images = await ImdbService().fetchImagesUncached(id, count: 20);
      if (!mounted) return;

      _yearCtrl.text  = data.releaseDate?.year != null ? '${data.releaseDate!.year}' : '';
      _monthCtrl.text = '01';
      _dayCtrl.text   = '01';

      setState(() {
        _data = data;
        _genres = List<String>.from(data.genres);
        _allImages = images;
        // Pre-select first 4 (or all if fewer than 4).
        _selected = images.take(4).toList();
        _hasMoreImages = images.length >= 20;
        _fetching = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _fetching = false; });
    }
  }

  Future<void> _loadMoreImages() async {
    final id = _imdbIdCtrl.text.trim();
    setState(() => _loadingMore = true);
    _imagePage++;
    final images = await ImdbService()
        .fetchImagesUncached(id, count: 20, page: _imagePage);
    if (!mounted) return;
    final existing = _allImages.toSet();
    final fresh = images.where((u) => !existing.contains(u)).toList();
    setState(() {
      if (fresh.isNotEmpty) _allImages = [..._allImages, ...fresh];
      _hasMoreImages = images.length >= 20 && fresh.isNotEmpty;
      _loadingMore = false;
    });
  }

  // ── Lightbox ──────────────────────────────────────────────────────────────

  void _showImagePreview(int displayIndex) {
    showDialog<List<String>>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (_) => _ImageLightbox(
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
    final y = _yearCtrl.text.trim();
    if (y.isEmpty) return '';
    final m = _monthCtrl.text.trim().padLeft(2, '0');
    final d = _dayCtrl.text.trim().padLeft(2, '0');
    return '$y-$m-$d';
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
                    _buildDateEditor(),
                    const SizedBox(height: 24),
                    _buildGenreEditor(),
                    const SizedBox(height: 24),
                    _buildTagsEditor(),
                    const SizedBox(height: 24),
                    _buildImagePicker(),
                    const SizedBox(height: 24),
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
        const SizedBox(width: 6),
        Text('— Catalog entry editor',
            style: TextStyle(fontSize: 14, color: kTextMuted)),
        const SizedBox(width: 24),
        Expanded(
          child: TextField(
            controller: _imdbIdCtrl,
            style: TextStyle(fontSize: 13, color: kTextPrimary),
            decoration: InputDecoration(
              hintText: 'IMDB ID  (e.g. tt30825738)',
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

  Widget _buildDateEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          label: 'Date',
          subtitle: 'API provides year only — fill in month and day if known',
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _DateField(controller: _yearCtrl,  label: 'Year',  width: 80, hint: 'YYYY', maxLength: 4),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text('–', style: TextStyle(color: kTextMuted))),
            _DateField(controller: _monthCtrl, label: 'Month', width: 58, hint: 'MM',   maxLength: 2),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text('–', style: TextStyle(color: kTextMuted))),
            _DateField(controller: _dayCtrl,   label: 'Day',   width: 58, hint: 'DD',   maxLength: 2),
            const SizedBox(width: 12),
            if (_dateResult.isNotEmpty)
              Text(_dateResult,
                  style: TextStyle(
                      fontSize: 13,
                      color: _adminPalette.primary,
                      fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }

  // ── Genre editor ──────────────────────────────────────────────────────────

  Widget _buildGenreEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          label: 'Genres',
          subtitle: 'Drag to reorder — first item shows as primary genre',
        ),
        const SizedBox(height: 8),
        if (_genres.isEmpty)
          Text('No genres returned by API',
              style: TextStyle(fontSize: 12, color: kTextMuted))
        else
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
              ),
            ),
          ),
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
    final display = _displayImages;
    final top4Count = _selected.length.clamp(0, 4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _SectionHeader(
              label: 'Slide Images',
              subtitle: 'Click to select/deselect  •  zoom to preview',
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
        const SizedBox(height: 4),
        Text(
          'Click → add to top of queue  •  amber ★ = top 4 slide picks  •  '
          'cyan = in queue  •  click again to remove  •  right-click → remove',
          style: TextStyle(fontSize: 11, color: kTextMuted),
        ),
        const SizedBox(height: 12),
        if (display.isEmpty && !_loadingMore)
          Text('No images returned by API',
              style: TextStyle(fontSize: 12, color: kTextMuted))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...display.asMap().entries.map((e) {
                final i       = e.key;
                final url     = e.value;
                final state   = _stateOf(url);
                final isTop4  = state == _ImgState.top4;
                final isQueue = state == _ImgState.inQueue;
                final borderColor = isTop4
                    ? _kTop4Color
                    : isQueue
                        ? _adminPalette.primary
                        : kBorderColor;
                final borderWidth = (isTop4 || isQueue) ? 2.5 : 1.0;
                final queueIdx   = _selected.indexOf(url);
                final badgeLabel = queueIdx < 4 ? top4Count - queueIdx : queueIdx + 1;

                return GestureDetector(
                  onTap: () => _toggleImage(url),
                  onSecondaryTap: () => _removeImage(url),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 110,
                      height: 82,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: borderColor, width: borderWidth),
                      ),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox.expand(
                              child: CachedNetworkImage(
                                imageUrl: url,
                                fit: BoxFit.cover,
                                cacheManager: CatalogCacheManager.instance,
                                errorWidget: (_, _, _) => Container(
                                  color: kSurface2Color,
                                  child: const Icon(Icons.broken_image_rounded,
                                      size: 24, color: kTextMuted),
                                ),
                              ),
                            ),
                          ),
                          // Top-4 badge: amber circle with position number
                          if (isTop4)
                            Positioned(
                              top: 5, right: 5,
                              child: Container(
                                width: 22, height: 22,
                                decoration: const BoxDecoration(
                                  color: _kTop4Color,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '$badgeLabel',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.black),
                                  ),
                                ),
                              ),
                            ),
                          // Queue badge: small cyan circle with position number
                          if (isQueue)
                            Positioned(
                              top: 5, right: 5,
                              child: Container(
                                width: 18, height: 18,
                                decoration: BoxDecoration(
                                  color: _adminPalette.primary
                                      .withValues(alpha: 0.85),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '$badgeLabel',
                                    style: const TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.black),
                                  ),
                                ),
                              ),
                            ),
                          // Zoom button
                          Positioned(
                            bottom: 4, left: 0, right: 0,
                            child: Center(
                              child: GestureDetector(
                                onTap: () => _showImagePreview(i),
                                behavior: HitTestBehavior.opaque,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: const Icon(Icons.zoom_in_rounded,
                                      size: 12, color: Colors.white70),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              // Load more button
              if (_hasMoreImages || _loadingMore)
                GestureDetector(
                  onTap: _loadingMore ? null : _loadMoreImages,
                  child: MouseRegion(
                    cursor: _loadingMore
                        ? SystemMouseCursors.basic
                        : SystemMouseCursors.click,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 110, height: 82,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: kBorderColor),
                        color: kSurface2Color,
                      ),
                      child: _loadingMore
                          ? Center(
                              child: SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: _adminPalette.primary),
                              ),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_circle_outline_rounded,
                                    size: 22, color: kTextSecondary),
                                const SizedBox(height: 4),
                                Text('Load 20 more',
                                    style: TextStyle(
                                        fontSize: 10, color: kTextSecondary)),
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

  // ── Results ───────────────────────────────────────────────────────────────

  Widget _buildResults() {
    final data = _data!;
    final fields = [
      ('title',        data.title),
      ('imdb_id',      _imdbIdCtrl.text.trim()),
      ('date',         _dateResult),
      ('plot',         data.plot),
      ('genres',       _genres.join(', ')),
      ('tags',         _tags.join(', ')),
      ('poster_url',   data.posterUrl),
      ('slide_images', _selected.take(4).toList().reversed.join(', ')),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          label: 'Results',
          subtitle: 'Copy each field to paste into the sheet',
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
              for (var i = 0; i < fields.length; i++) ...[
                if (i > 0) Divider(height: 1, color: kBorderColor),
                _ResultRow(
                  label: fields[i].$1,
                  value: fields[i].$2,
                  onCopy: fields[i].$2.isNotEmpty
                      ? () => _copy(fields[i].$2)
                      : null,
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

  _ImgState _stateOf(String url) {
    final idx = _selected.indexOf(url);
    if (idx == -1) return _ImgState.none;
    return idx < 4 ? _ImgState.top4 : _ImgState.inQueue;
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
        _selected.insert(0, url);
      }
    });
  }

  void _remove(String url) {
    setState(() => _selected.remove(url));
  }

  void _close() => Navigator.pop(context, _selected);

  @override
  Widget build(BuildContext context) {
    final url   = widget.images[_currentIndex];
    final state = _stateOf(url);

    final borderColor = state == _ImgState.top4
        ? _kTop4Color
        : state == _ImgState.inQueue
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
                _LightboxActionBtn(state: state, onTap: () => _toggle(url)),
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
  final _ImgState state;
  final VoidCallback onTap;

  const _LightboxActionBtn({required this.state, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (icon, label, bg) = switch (state) {
      _ImgState.none    => (Icons.add_circle_outline_rounded, 'Add to queue', Colors.white24),
      _ImgState.inQueue => (Icons.check_circle_outline_rounded, 'In queue — click to remove', Colors.white24),
      _ImgState.top4    => (Icons.star_rounded, 'Top 4 slide pick — click to remove', _kTop4Color),
    };

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

class _DateField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final double width;
  final String hint;
  final int maxLength;
  const _DateField({
    required this.controller,
    required this.label,
    required this.width,
    required this.hint,
    required this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        maxLength: maxLength,
        style: TextStyle(fontSize: 13, color: kTextPrimary),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontSize: 11, color: kTextMuted),
          hintText: hint,
          hintStyle: TextStyle(fontSize: 12, color: kTextMuted),
          counterText: '',
          filled: true,
          fillColor: kSurfaceColor,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(7),
              borderSide: BorderSide(color: kBorderColor)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(7),
              borderSide: BorderSide(color: kBorderColor)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(7),
              borderSide: BorderSide(color: _adminPalette.primary)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
      ),
    );
  }
}

class _GenreRow extends StatelessWidget {
  final String genre;
  final int index;
  final bool isPrimary;
  const _GenreRow(
      {super.key,
      required this.genre,
      required this.index,
      required this.isPrimary});

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
              margin: const EdgeInsets.only(right: 10),
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
            )
          else
            const SizedBox(width: 10),
        ],
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
