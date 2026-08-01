import 'dart:io';
import 'dart:math' show min;
import 'dart:ui' show ImageFilter;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../../core/services/catalog_cache_manager.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:path/path.dart' as p;
import '../../core/providers/decode_request_provider.dart';
import '../../core/providers/player_request_provider.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tab_colors.dart';
import '../../core/util/filename_sanitizer.dart';
import '../shell/app_shell.dart';
import 'catalog_notifier.dart';
import 'config_service.dart';
import 'models/catalog_entry.dart';
import 'models/series_entry.dart';
import 'request_notifier.dart';
import 'screens/series_detail_screen.dart';
import 'series_notifier.dart';
import 'widgets/catalog_card.dart';
import 'widgets/series_card.dart';
import 'widgets/webview_overlay.dart';

enum _SortMode { alpha, date, rating }

const _kBarHeight = 64.0;

class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key});

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen>
    with TickerProviderStateMixin {
  final _urlController = TextEditingController();
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  String _search = '';
  bool _showDownloads = false;
  _SortMode _sortMode = _SortMode.alpha;
  bool _sortAsc = true;
  Set<String> _filterLanguages = {};
  Set<String> _filterGenres = {};
  Set<int> _filterYears = {};
  bool _filterDownloaded = false;

  // Sub-tab (Movies / Series) — plain int, no TabController, no animation delay
  int _subTabIndex = 0;

  // Open series detail (null = show grid)
  SeriesEntry? _openedSeries;

  // Movies expanded card overlay state
  CatalogEntry? _expandedEntry;
  Rect _expandedLocalRect = Rect.zero;
  Rect _bodyLocalRect = Rect.zero;
  final _expandedCardKey = GlobalKey<CatalogCardExpandedState>();
  late final AnimationController _expandAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );


  final _bodyKey = GlobalKey();

  static const _kSortMode = 'catalog_sort_mode';
  static const _kSortAsc  = 'catalog_sort_asc';
  static const _kSubTab   = 'catalog_sub_tab';

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final modeStr = prefs.getString(_kSortMode);
    final asc     = prefs.getBool(_kSortAsc) ?? true;
    final mode = switch (modeStr) {
      'date'   => _SortMode.date,
      'rating' => _SortMode.rating,
      _        => _SortMode.alpha,
    };
    final subTab = prefs.getInt(_kSubTab) ?? 0;
    setState(() { _sortMode = mode; _sortAsc = asc; _subTabIndex = subTab; });
    if (subTab == 1) {
      ref.read(catalogSubPaletteProvider.notifier).state = kSeriesPalette;
    }
  }

  Future<void> _saveSort(_SortMode mode, bool asc) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSortMode, mode.name);
    await prefs.setBool(_kSortAsc, asc);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _urlController.dispose();
    _searchController.dispose();
    _focusNode.dispose();
    ref.read(catalogSubPaletteProvider.notifier).state = null;
    _expandAnim.dispose();
    super.dispose();
  }

  bool _onHardwareKey(KeyEvent event) {
    if (!mounted || event is! KeyDownEvent) return false;
    if (event.logicalKey == LogicalKeyboardKey.keyD) {
      // Don't intercept when a text field has focus (e.g. search bar).
      final ctx = FocusManager.instance.primaryFocus?.context;
      if (ctx != null &&
          (ctx.widget is EditableText ||
           ctx.findAncestorWidgetOfExactType<EditableText>() != null)) {
        return false;
      }
      // Shift+D is Google Photos' in-WebView download shortcut — ignore it here.
      if (HardwareKeyboard.instance.isShiftPressed) return false;
      setState(() => _showDownloads = !_showDownloads);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape && _openedSeries != null) {
      setState(() => _openedSeries = null);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.f5) {
      final url = ref.read(sheetUrlProvider);
      if (url != null) {
        ref.read(catalogProvider.notifier).load(url, forceRefresh: true);
        ref.read(seriesProvider.notifier).load(url, forceRefresh: true);
      }
      return true;
    }
    return false;
  }

  void _onCardExpand(CatalogEntry entry, Rect globalRect) {
    final screenBox = context.findRenderObject() as RenderBox;
    final bodyBox = _bodyKey.currentContext!.findRenderObject() as RenderBox;
    setState(() {
      _expandedEntry = entry;
      // Card rect in screen-local (outer Stack) coords
      _expandedLocalRect =
          screenBox.globalToLocal(globalRect.topLeft) & globalRect.size;
      // Body area rect in screen-local coords — used for card clamping
      _bodyLocalRect = screenBox.globalToLocal(
            bodyBox.localToGlobal(Offset.zero),
          ) &
          bodyBox.size;
    });
    _expandAnim.forward(from: 0);
  }

  void _closeExpanded() {
    _expandAnim.reverse().then((_) {
      if (mounted) {
        setState(() => _expandedEntry = null);
        _focusNode.requestFocus();
      }
    });
  }

  void _switchSubTab(int index) {
    setState(() {
      _subTabIndex = index;
      if (index != 1) _openedSeries = null;
    });
    ref.read(catalogSubPaletteProvider.notifier).state =
        index == 1 ? kSeriesPalette : null;
    SharedPreferences.getInstance().then((p) => p.setInt(_kSubTab, index));
  }

  void _onSeriesCardExpand(SeriesEntry entry) {
    setState(() => _openedSeries = entry);
  }

  void _showRequestDialog(BuildContext context) {
    ref.read(requestProvider.notifier).reset();
    showDialog<void>(
      context: context,
      builder: (_) => const _RequestDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSeriesTab = _subTabIndex == 1;
    final palette = isSeriesTab ? kSeriesPalette : AppTab.catalog.palette;
    final sheetUrl = ref.watch(sheetUrlProvider);
    final config = ref.watch(sheetConfigProvider).valueOrNull ?? const SheetConfig();
    final catalogState = ref.watch(catalogProvider);
    final seriesState = ref.watch(seriesProvider);
    final downloadState = ref.watch(downloadProvider);
    final downloadHistory = ref.watch(downloadHistoryProvider);
    final historyCount = downloadHistory.length;
    final downloadedTitles = downloadHistory.map((r) => r.title).toSet();

    if (sheetUrl != null && catalogState is CatalogIdle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(catalogProvider.notifier).load(sheetUrl);
      });
    }
    if (sheetUrl != null && seriesState is SeriesCatalogIdle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(seriesProvider.notifier).load(sheetUrl);
      });
    }

    final fadeAnim =
        CurvedAnimation(parent: _expandAnim, curve: Curves.easeOut);

    final catalogUi = Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (_expandedEntry != null) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _expandedCardKey.currentState?.navigate(-1);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _expandedCardKey.currentState?.navigate(1);
            return KeyEventResult.handled;
          }
        }
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          if (_expandedEntry != null) {
            _closeExpanded();
            return KeyEventResult.handled;
          }
          if (_showDownloads) {
            setState(() => _showDownloads = false);
            return KeyEventResult.handled;
          }
        }
        if (_showDownloads &&
            event.logicalKey == LogicalKeyboardKey.backspace) {
          setState(() => _showDownloads = false);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, _kBarHeight),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TopBar(
              palette: palette,
              sheetUrl: sheetUrl,
              urlController: _urlController,
              searchController: _searchController,
              showDownloads: _showDownloads,
              historyCount: historyCount,
              hasRequestFeature: config.hasRequestFeature,
              onSearch: (v) => setState(() => _search = v),
              onSubmitUrl: (url) async {
                await ref.read(sheetUrlProvider.notifier).save(url);
                ref.read(catalogProvider.notifier).load(url);
                ref.read(seriesProvider.notifier).load(url, forceRefresh: true);
              },
              onRefresh: _showDownloads
                  ? () =>
                      ref.read(downloadHistoryProvider.notifier).pruneDeleted()
                  : sheetUrl != null
                      ? () {
                          ref.read(catalogProvider.notifier).load(sheetUrl, forceRefresh: true);
                          ref.read(seriesProvider.notifier).load(sheetUrl, forceRefresh: true);
                        }
                      : null,
              onClearUrl: () {
                ref.read(sheetUrlProvider.notifier).clear();
                ref.read(catalogProvider.notifier).reset();
                ref.read(seriesProvider.notifier).reset();
              },
              onToggleDownloads: () =>
                  setState(() => _showDownloads = !_showDownloads),
              onOpenFolder: () {
                final dir = ref.read(settingsProvider).catalogDownloadDirectory;
                Process.run('explorer.exe',
                    [dir.isNotEmpty ? dir : AppDirectories.downloaded]);
              },
              onRequest: config.hasRequestFeature
                  ? () => _showRequestDialog(context)
                  : null,
            ),
            const SizedBox(height: 12),
            if (!isSeriesTab && !_showDownloads && catalogState is CatalogLoaded) ...[
              _SortFilterBar(
                entries: catalogState.entries,
                sortMode: _sortMode,
                sortAsc: _sortAsc,
                filterLanguages: _filterLanguages,
                filterGenres: _filterGenres,
                filterYears: _filterYears,
                filterDownloaded: _filterDownloaded,
                palette: palette,
                onSortChanged: (mode, asc) {
                  setState(() { _sortMode = mode; _sortAsc = asc; });
                  _saveSort(mode, asc);
                },
                onLanguagesChanged: (v) =>
                    setState(() => _filterLanguages = v),
                onGenresChanged: (v) =>
                    setState(() => _filterGenres = v),
                onYearsChanged: (v) =>
                    setState(() => _filterYears = v),
                onToggleDownloaded: () =>
                    setState(() => _filterDownloaded = !_filterDownloaded),
                onClearFilters: () => setState(() {
                  _filterLanguages = {};
                  _filterGenres = {};
                  _filterYears = {};
                  _filterDownloaded = false;
                }),
              ),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: SizedBox.expand(
                key: _bodyKey,
                child: Column(
                  children: [
                    Expanded(
                      child: _showDownloads
                          ? _DownloadsListView(
                              palette: palette,
                              search: _search,
                              onDecodeFile: (path) {
                                ref
                                    .read(decodeOpenRequestProvider.notifier)
                                    .state = path;
                                ref.read(activeTabProvider.notifier).state =
                                    AppTab.decode;
                              },
                              onPlayFile: (path) {
                                ref
                                    .read(playerOpenRequestProvider.notifier)
                                    .state = path;
                                ref.read(activeTabProvider.notifier).state =
                                    AppTab.player;
                              },
                            )
                          : isSeriesTab
                          ? _SeriesBody(
                              state: seriesState,
                              search: _search,
                              downloadedTitles: downloadedTitles,
                              onCardExpand: _onSeriesCardExpand,
                            )
                          : _Body(
                              state: catalogState,
                              search: _search,
                              sortMode: _sortMode,
                              sortAsc: _sortAsc,
                              filterLanguages: _filterLanguages,
                              filterGenres: _filterGenres,
                              filterYears: _filterYears,
                              filterDownloaded: _filterDownloaded,
                              downloadedTitles: downloadedTitles,
                              palette: palette,
                              onOpenInBrowser: _openWebView,
                              onCardExpand: _onCardExpand,
                            ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      transitionBuilder: (child, anim) => SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.18),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(
                            parent: anim, curve: Curves.easeOut)),
                        child: FadeTransition(opacity: anim, child: child),
                      ),
                      child: (downloadState is DownloadActive ||
                              downloadState is DownloadDone ||
                              downloadState is DownloadError)
                          ? _DownloadPanel(
                              key: const ValueKey('panel'),
                              state: downloadState,
                              palette: palette,
                              onDismiss: () =>
                                  ref.read(downloadProvider.notifier).dismiss(),
                              onCancel: () =>
                                  ref.read(downloadProvider.notifier).cancel(),
                              onRetry: () =>
                                  ref.read(downloadProvider.notifier).retryFailed(),
                              onDecodeThis: (path) {
                                ref.read(downloadProvider.notifier).dismiss();
                                ref
                                    .read(decodeOpenRequestProvider.notifier)
                                    .state = path;
                                ref.read(activeTabProvider.notifier).state =
                                    AppTab.decode;
                              },
                            )
                          : const SizedBox.shrink(key: ValueKey('none')),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // Outer Stack: backdrop covers the full catalog area (TopBar included);
    // card is clamped to the body area below the TopBar.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      color: isSeriesTab
          ? kSeriesPalette.surface
          : AppTab.catalog.palette.surface,
      child: _openedSeries != null
          ? SeriesDetailScreen(
              key: ValueKey(_openedSeries!.title),
              entry: _openedSeries!,
              onBack: () => setState(() => _openedSeries = null),
            )
          : Stack(
      children: [
        catalogUi,
        if (!_showDownloads)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _SubTabBar(
              activeIndex: _subTabIndex,
              surfaceColor: isSeriesTab
                  ? kSeriesPalette.surface
                  : AppTab.catalog.palette.surface,
              onChanged: _switchSubTab,
            ),
          ),
        if (_expandedEntry != null) ...[
          FadeTransition(
            opacity: fadeAnim,
            child: GestureDetector(
              onTap: _closeExpanded,
              child:
                  Container(color: Colors.black.withValues(alpha: 0.65)),
            ),
          ),
          _CardDetail(
            entry: _expandedEntry!,
            localCardRect: _expandedLocalRect,
            bodyRect: _bodyLocalRect,
            animation: _expandAnim,
            palette: palette,
            cardKey: _expandedCardKey,
            isDownloaded: downloadedTitles.contains(_expandedEntry!.title),
            onClose: _closeExpanded,
            onOpenInBrowser: () {
              _closeExpanded();
              _openWebView(_expandedEntry!);
            },
          ),
        ],
      ],
    ),
    );
  }

  void _openWebView(CatalogEntry entry) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => WebViewOverlay(
        url: entry.videoUrl,
        title: entry.title,
        onDownloadRequested: (url, filename) {
          final fname = filename ?? '';
          final history = ref.read(downloadHistoryProvider);
          final existing = history
              .where((r) => r.filename == fname && File(r.filePath).existsSync())
              .firstOrNull;
          if (existing != null) {
            // Defer the dialog to the next frame — onDownloadRequested fires
            // synchronously inside _triggerDownload, which has already called
            // Navigator.pop() to close the WebView. Pushing a new route in the
            // same stack frame corrupts the Navigator before the pop completes.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: kDialogColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  title: Text('Already Downloaded',
                      style: TextStyle(color: kTextPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                  content: Text(
                    'This video is already in your downloads. Downloading again will overwrite the existing file.',
                    style: TextStyle(color: kTextSecondary, fontSize: 13),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('Cancel', style: TextStyle(color: kTextMuted)),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        ref.read(downloadProvider.notifier).enqueue(
                              url, fname, entry.title, entry.thumbnailUrl);
                      },
                      child: Text('Download Anyway',
                          style: TextStyle(color: AppTab.catalog.palette.primary, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              );
            });
          } else {
            ref.read(downloadProvider.notifier).enqueue(
                  url, fname, entry.title, entry.thumbnailUrl);
          }
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  final TabPalette palette;
  final String? sheetUrl;
  final TextEditingController urlController;
  final TextEditingController searchController;
  final bool showDownloads;
  final int historyCount;
  final bool hasRequestFeature;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onSubmitUrl;
  final VoidCallback? onRefresh;
  final VoidCallback onClearUrl;
  final VoidCallback onToggleDownloads;
  final VoidCallback onOpenFolder;
  final VoidCallback? onRequest;

  const _TopBar({
    required this.palette,
    required this.sheetUrl,
    required this.urlController,
    required this.searchController,
    required this.showDownloads,
    required this.historyCount,
    required this.hasRequestFeature,
    required this.onSearch,
    required this.onSubmitUrl,
    required this.onRefresh,
    required this.onClearUrl,
    required this.onToggleDownloads,
    required this.onOpenFolder,
    this.onRequest,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: sheetUrl == null
              ? _UrlInput(
                  controller: urlController,
                  palette: palette,
                  onSubmit: onSubmitUrl,
                )
              : _SearchBar(
                  controller: searchController,
                  palette: palette,
                  onChanged: onSearch,
                ),
        ),
        const SizedBox(width: 10),
        if (showDownloads) ...[
          _IconBtn(
            icon: Icons.open_in_new_rounded,
            tooltip: 'Open downloads folder',
            onTap: onOpenFolder,
          ),
          const SizedBox(width: 6),
        ],
        // Downloads history toggle (badge shows count when there are records).
        _DownloadsToggleBtn(
          active: showDownloads,
          count: historyCount,
          palette: palette,
          onTap: onToggleDownloads,
        ),
        if (sheetUrl != null) ...[
          const SizedBox(width: 6),
          _IconBtn(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh catalog',
            onTap: onRefresh,
          ),
          const SizedBox(width: 6),
          _IconBtn(
            icon: Icons.link_off_rounded,
            tooltip: 'Change sheet URL',
            onTap: onClearUrl,
          ),
        ],
        if (hasRequestFeature && onRequest != null) ...[
          const SizedBox(width: 6),
          _IconBtn(
            icon: Icons.add_circle_outline_rounded,
            tooltip: 'Request a movie or series',
            onTap: onRequest,
          ),
        ],
      ],
    );
  }
}

class _DownloadsToggleBtn extends StatelessWidget {
  final bool active;
  final int count;
  final TabPalette palette;
  final VoidCallback onTap;

  const _DownloadsToggleBtn({
    required this.active,
    required this.count,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: active ? 'Back to catalog' : 'Downloaded videos',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: active ? palette.primary.withValues(alpha: 0.15) : kSurfaceColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? palette.primary : kBorderColor,
              width: active ? 1.5 : 1,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Icon(
                  Icons.folder_rounded,
                  size: 18,
                  color: active ? palette.primary : kTextSecondary,
                ),
              ),
              if (count > 0)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(
                      color: palette.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      style: const TextStyle(
                          fontSize: 8,
                          color: Colors.white,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UrlInput extends StatelessWidget {
  final TextEditingController controller;
  final TabPalette palette;
  final ValueChanged<String> onSubmit;

  const _UrlInput({
    required this.controller,
    required this.palette,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: TextStyle(fontSize: 13, color: kTextPrimary),
      decoration: InputDecoration(
        hintText: 'Paste Google Sheets URL to load catalog…',
        hintStyle: TextStyle(fontSize: 13, color: kTextMuted),
        prefixIcon: Icon(Icons.table_chart_rounded, color: kTextMuted, size: 18),
        suffixIcon: IconButton(
          icon: Icon(Icons.arrow_forward_rounded, color: palette.primary, size: 18),
          tooltip: 'Load',
          onPressed: () => onSubmit(controller.text.trim()),
        ),
        filled: true,
        fillColor: kSurfaceColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: kBorderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: kBorderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: palette.primary),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      onSubmitted: (v) => onSubmit(v.trim()),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final TabPalette palette;
  final ValueChanged<String> onChanged;

  const _SearchBar({
    required this.controller,
    required this.palette,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: TextStyle(fontSize: 13, color: kTextPrimary),
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Search by title, tag or description…',
        hintStyle: TextStyle(fontSize: 13, color: kTextMuted),
        prefixIcon: Icon(Icons.search_rounded, color: kTextMuted, size: 18),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
                icon: Icon(Icons.clear_rounded, color: kTextMuted, size: 16),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              )
            : null,
        filled: true,
        fillColor: kSurfaceColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: kBorderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: kBorderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: palette.primary),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _IconBtn({required this.icon, required this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: kSurfaceColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: kBorderColor),
          ),
          child: Icon(icon, size: 18, color: onTap != null ? kTextSecondary : kTextMuted),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _Body extends StatelessWidget {
  final CatalogState state;
  final String search;
  final _SortMode sortMode;
  final bool sortAsc;
  final Set<String> filterLanguages;
  final Set<String> filterGenres;
  final Set<int> filterYears;
  final bool filterDownloaded;
  final Set<String> downloadedTitles;
  final TabPalette palette;
  final ValueChanged<CatalogEntry> onOpenInBrowser;
  final void Function(CatalogEntry, Rect) onCardExpand;

  const _Body({
    required this.state,
    required this.search,
    required this.sortMode,
    required this.sortAsc,
    required this.filterLanguages,
    required this.filterGenres,
    required this.filterYears,
    this.filterDownloaded = false,
    this.downloadedTitles = const {},
    required this.palette,
    required this.onOpenInBrowser,
    required this.onCardExpand,
  });

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      CatalogIdle()                  => _EmptyState(palette: palette),
      CatalogLoading()               => Center(child: CircularProgressIndicator(color: palette.primary)),
      CatalogError(:final message)   => _ErrorState(message: message),
      CatalogLoaded(:final entries)  => _Grid(
          entries: _filterAndSort(entries),
          allEntries: entries,
          downloadedTitles: downloadedTitles,
          palette: palette,
          onOpenInBrowser: onOpenInBrowser,
          onCardExpand: onCardExpand,
        ),
    };
  }

  List<CatalogEntry> _filterAndSort(List<CatalogEntry> entries) {
    var result = entries.where((e) {
      if (search.isNotEmpty) {
        final q = search.toLowerCase();
        if (!e.title.toLowerCase().contains(q) &&
            !e.plot.toLowerCase().contains(q) &&
            !e.genres.any((t) => t.toLowerCase().contains(q)) &&
            !e.tags.any((t) => t.toLowerCase().contains(q))) { return false; }
      }
      if (filterLanguages.isNotEmpty && !filterLanguages.contains(e.language)) return false;
      if (filterGenres.isNotEmpty && !e.genres.any(filterGenres.contains)) return false;
      if (filterYears.isNotEmpty && !filterYears.contains(e.date?.year)) return false;
      if (filterDownloaded && !downloadedTitles.contains(e.title)) return false;
      return true;
    }).toList();

    result.sort((a, b) {
      final cmp = switch (sortMode) {
        _SortMode.alpha  => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        _SortMode.date   => (a.date ?? DateTime(0)).compareTo(b.date ?? DateTime(0)),
        _SortMode.rating => (a.imdbRating ?? 0).compareTo(b.imdbRating ?? 0),
      };
      return sortAsc ? cmp : -cmp;
    });
    return result;
  }
}

class _Grid extends StatefulWidget {
  final List<CatalogEntry> entries;
  final List<CatalogEntry> allEntries;
  final Set<String> downloadedTitles;
  final TabPalette palette;
  final ValueChanged<CatalogEntry> onOpenInBrowser;
  final void Function(CatalogEntry, Rect) onCardExpand;

  const _Grid({
    required this.entries,
    required this.allEntries,
    this.downloadedTitles = const {},
    required this.palette,
    required this.onOpenInBrowser,
    required this.onCardExpand,
  });

  @override
  State<_Grid> createState() => _GridState();
}

class _GridState extends State<_Grid> {
  double _aspectRatio = 2 / 3;
  final _ratios = <double>[];

  @override
  void initState() {
    super.initState();
    _resolveRatios(widget.allEntries);
  }

  @override
  void didUpdateWidget(_Grid old) {
    super.didUpdateWidget(old);
    if (old.allEntries != widget.allEntries) {
      // Only resolve genuinely new URLs — never wipe the existing pool so the
      // median stays stable when one landscape image resolves before the rest.
      final oldUrls = old.allEntries.map((e) => e.thumbnailUrl).toSet();
      final newEntries = widget.allEntries
          .where((e) => e.thumbnailUrl.isNotEmpty && !oldUrls.contains(e.thumbnailUrl))
          .toList();
      if (newEntries.isNotEmpty) _resolveRatios(newEntries);
    }
  }

  void _resolveRatios(List<CatalogEntry> entries) {
    final urls = entries
        .map((e) => e.thumbnailUrl)
        .where((u) => u.isNotEmpty)
        .toSet();
    for (final url in urls) {
      final provider = CachedNetworkImageProvider(url,
          cacheManager: CatalogCacheManager.instance);
      final stream = provider.resolve(const ImageConfiguration());
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (ImageInfo info, _) {
          stream.removeListener(listener);
          final w = info.image.width;
          final h = info.image.height;
          if (h > 0) _onRatio(w / h);
        },
        onError: (_, _) => stream.removeListener(listener),
      );
      stream.addListener(listener);
    }
  }

  void _onRatio(double ratio) {
    _ratios.add(ratio);
    // Only use portrait images (ratio < 1) to set the grid aspect ratio.
    // Skip the update entirely until at least one portrait image resolves so
    // a landscape thumbnail that decodes first never sets a landscape ratio.
    final portraits = _ratios.where((r) => r < 1.0).toList();
    if (portraits.isEmpty) return;
    final sorted = List<double>.from(portraits)..sort();
    final median = sorted[sorted.length ~/ 2];
    if ((median - _aspectRatio).abs() > 0.02 && mounted) {
      setState(() => _aspectRatio = median);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) {
      return Center(
        child: Text('No results.', style: TextStyle(color: kTextMuted, fontSize: 14)),
      );
    }

    return MasonryGridView.builder(
      gridDelegate: const SliverSimpleGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
      ),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      itemCount: widget.entries.length,
      itemBuilder: (_, i) {
        final entry = widget.entries[i];
        return CatalogCard(
          key: ValueKey(entry.imdbId.isNotEmpty ? entry.imdbId : entry.title),
          entry: entry,
          aspectRatio: _aspectRatio,
          isDownloaded: widget.downloadedTitles.contains(entry.title),
          onOpenInBrowser: () => widget.onOpenInBrowser(entry),
          onExpand: (rect) => widget.onCardExpand(entry, rect),
        )
            .animate()
            .fadeIn(duration: 280.ms, delay: Duration(milliseconds: min(i, 9) * 35))
            .slideY(begin: 0.06, duration: 280.ms, curve: Curves.easeOut);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Expanded card — positioned in the outer Stack, clamped to the body area
// ---------------------------------------------------------------------------

class _CardDetail extends StatelessWidget {
  final CatalogEntry entry;
  final Rect localCardRect; // card rect in screen-local (outer Stack) coords
  final Rect bodyRect;      // body area rect in same coords — for clamping
  final AnimationController animation;
  final TabPalette palette;
  final GlobalKey<CatalogCardExpandedState> cardKey;
  final bool isDownloaded;
  final VoidCallback onClose;
  final VoidCallback onOpenInBrowser;

  const _CardDetail({
    required this.entry,
    required this.localCardRect,
    required this.bodyRect,
    required this.animation,
    required this.palette,
    required this.cardKey,
    this.isDownloaded = false,
    required this.onClose,
    required this.onOpenInBrowser,
  });

  @override
  Widget build(BuildContext context) {
    const expandedW = 360.0;
    const edgePad = 0.0;

    final expandedMaxH = (bodyRect.height - edgePad * 2).clamp(0.0, 640.0);

    final left = (localCardRect.center.dx - expandedW / 2).clamp(
      bodyRect.left + edgePad,
      bodyRect.right - expandedW - edgePad,
    );
    final top = (localCardRect.center.dy - expandedMaxH / 2).clamp(
      bodyRect.top + edgePad,
      bodyRect.bottom - expandedMaxH - edgePad,
    );

    final scaleAnim = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
    );

    return Positioned(
      left: left,
      top: top,
      width: expandedW,
      child: FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: scaleAnim,
          child: GestureDetector(
            onTap: onClose,
            child: CatalogCardExpanded(
              key: cardKey,
              entry: entry,
              palette: palette,
              isDownloaded: isDownloaded,
              onClose: onClose,
              onOpenInBrowser: onOpenInBrowser,
              maxHeight: expandedMaxH,
            ),
          ),
        ),
      ),
    );
  }
}

class _DownloadPanel extends StatelessWidget {
  final DownloadState state;
  final TabPalette palette;
  final VoidCallback onDismiss;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final void Function(String filePath) onDecodeThis;

  const _DownloadPanel({
    super.key,
    required this.state,
    required this.palette,
    required this.onDismiss,
    required this.onCancel,
    required this.onRetry,
    required this.onDecodeThis,
  });

  @override
  Widget build(BuildContext context) {
    // DownloadDone uses its own full banner decoration — skip the shared card.
    if (state case DownloadDone(:final filePath)) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: _DoneDownload(
          filePath: filePath,
          palette: palette,
          onDismiss: onDismiss,
          onOpenFolder: () =>
              Process.run('explorer.exe', [p.dirname(filePath)]),
          onDecodeThis: () => onDecodeThis(filePath),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: kSurfaceColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorderColor),
      ),
      child: switch (state) {
        DownloadActive(
          :final filename,
          :final receivedBytes,
          :final totalBytes,
          :final speedBytesPerSec,
          :final queueRemaining
        ) =>
          _ActiveDownload(
            filename: filename,
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
            speedBytesPerSec: speedBytesPerSec,
            queueRemaining: queueRemaining,
            palette: palette,
            onCancel: onCancel,
          ),
        DownloadError(:final message) => _ErrorDownload(
            message: message,
            onDismiss: onDismiss,
            onRetry: onRetry,
          ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

class _ActiveDownload extends StatelessWidget {
  final String filename;
  final int receivedBytes;
  final int totalBytes;
  final double speedBytesPerSec;
  final int queueRemaining;
  final TabPalette palette;
  final VoidCallback onCancel;

  const _ActiveDownload({
    required this.filename,
    required this.receivedBytes,
    required this.totalBytes,
    required this.speedBytesPerSec,
    required this.queueRemaining,
    required this.palette,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final progress = totalBytes > 0 ? receivedBytes / totalBytes : null;
    final percent = progress != null ? ' — ${(progress * 100).toStringAsFixed(1)}%' : '';
    final speed = speedBytesPerSec > 0 ? '  •  ${_fmt(speedBytesPerSec.toInt())}/s' : '';
    final sizeLabel = totalBytes > 0
        ? '${_fmt(receivedBytes)} / ${_fmt(totalBytes)}$speed$percent'
        : _fmt(receivedBytes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.download_rounded, size: 15, color: palette.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kTextPrimary),
                  ),
                  if (queueRemaining > 0)
                    Text(
                      '$queueRemaining more in queue',
                      style: TextStyle(fontSize: 10, color: kTextMuted),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(sizeLabel, style: TextStyle(fontSize: 12, color: kTextSecondary)),
            const SizedBox(width: 4),
            Tooltip(
              message: 'Cancel all downloads',
              child: InkWell(
                onTap: onCancel,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.stop_circle_outlined, size: 16, color: kTextMuted),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: progress ?? 0),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          builder: (_, val, _) => LinearProgressIndicator(
            value: progress != null ? val : null,
            color: palette.primary,
            backgroundColor: kSurface2Color,
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }

  String _fmt(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class _DoneDownload extends StatelessWidget {
  final String filePath;
  final TabPalette palette;
  final VoidCallback onDismiss;
  final VoidCallback onOpenFolder;
  final VoidCallback onDecodeThis;

  const _DoneDownload({
    required this.filePath,
    required this.palette,
    required this.onDismiss,
    required this.onOpenFolder,
    required this.onDecodeThis,
  });

  @override
  Widget build(BuildContext context) {
    final filename = filePath.split(RegExp(r'[/\\]')).last;
    final folder = filePath.substring(0, filePath.length - filename.length - 1);
    final accent = palette.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: accent, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Downloaded successfully!',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: accent, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: kTextSecondary),
                ),
                Text(
                  folder,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: kTextMuted),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.folder_open_rounded, color: accent),
            tooltip: 'Open folder',
            onPressed: onOpenFolder,
          ),
          TextButton.icon(
            onPressed: onDecodeThis,
            icon: Icon(Icons.lock_open_rounded, size: 16, color: accent),
            label: const Text('Decode'),
            style: TextButton.styleFrom(foregroundColor: accent),
          ),
          TextButton(
            onPressed: onDismiss,
            style: TextButton.styleFrom(foregroundColor: accent),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class _ErrorDownload extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;
  final VoidCallback onRetry;

  const _ErrorDownload({
    required this.message,
    required this.onDismiss,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.error_outline_rounded, size: 18, color: Colors.redAccent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message, maxLines: 2, style: TextStyle(fontSize: 12, color: kTextSecondary)),
        ),
        const SizedBox(width: 12),
        TextButton(
          onPressed: onRetry,
          style: TextButton.styleFrom(foregroundColor: Colors.redAccent, padding: EdgeInsets.zero),
          child: const Text('Retry', style: TextStyle(fontSize: 12)),
        ),
        const SizedBox(width: 4),
        TextButton(
          onPressed: onDismiss,
          style: TextButton.styleFrom(foregroundColor: kTextMuted, padding: EdgeInsets.zero),
          child: const Text('Dismiss', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final TabPalette palette;
  const _EmptyState({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.video_library_outlined, size: 48, color: kTextMuted)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(begin: 0.92, end: 1.0, duration: 1800.ms, curve: Curves.easeInOut),
          const SizedBox(height: 16),
          Text(
            'No catalog loaded',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: kTextPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            'Paste a Google Sheets URL above to get started.',
            style: TextStyle(fontSize: 13, color: kTextMuted),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 40, color: Colors.redAccent),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: kTextSecondary),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Downloads history list
// ---------------------------------------------------------------------------

class _DownloadsListView extends ConsumerWidget {
  final TabPalette palette;
  final String search;
  final void Function(String filePath) onDecodeFile;
  final void Function(String filePath) onPlayFile;

  const _DownloadsListView({
    required this.palette,
    required this.search,
    required this.onDecodeFile,
    required this.onPlayFile,
  });

  static const _videoExts = {'mp4', 'mkv', 'avi', 'mov', 'webm'};

  /// Returns the path of the first video file found in the decoded folder for
  /// this record, or null if not yet decoded.
  String? _decodedVideoPath(String decodeDir, DownloadRecord record) {
    final folder = Directory(p.join(decodeDir, sanitizeFilename(record.title)));
    if (!folder.existsSync()) return null;
    try {
      for (final entry in folder.listSync()) {
        if (entry is File) {
          final ext = p.extension(entry.path).replaceFirst('.', '').toLowerCase();
          if (_videoExts.contains(ext)) return entry.path;
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allRecords = ref.watch(downloadHistoryProvider);
    final settings = ref.watch(settingsProvider);
    final decodeDir = settings.decodeOutputDirectory.isEmpty
        ? AppDirectories.decoded
        : settings.decodeOutputDirectory;

    final records = search.isEmpty
        ? allRecords
        : allRecords.where((r) {
            final q = search.toLowerCase();
            return r.title.toLowerCase().contains(q) ||
                r.filename.toLowerCase().contains(q);
          }).toList();

    if (records.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open_rounded, size: 48, color: kTextMuted),
            const SizedBox(height: 16),
            Text(
              search.isEmpty ? 'No downloads yet' : 'No results',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: kTextPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              search.isEmpty
                  ? 'Videos downloaded from the catalog will appear here.'
                  : 'No downloads match "$search".',
              style: TextStyle(fontSize: 13, color: kTextMuted),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: records.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: kBorderColor),
      itemBuilder: (_, i) {
        final rec = records[i];
        final decodedPath = _decodedVideoPath(decodeDir, rec);
        return _DownloadRecordRow(
          record: rec,
          palette: palette,
          decodedVideoPath: decodedPath,
          onOpenFolder: () {
            final folder = decodedPath != null
                ? p.dirname(decodedPath)
                : p.dirname(rec.filePath);
            Process.run('explorer.exe', [folder]);
          },
          onDecode: () => onDecodeFile(rec.filePath),
          onPlay: decodedPath != null ? () => onPlayFile(decodedPath) : null,
          onDelete: () {
            try {
              final f = File(rec.filePath);
              if (f.existsSync()) f.deleteSync();
            } catch (_) {}
            if (decodedPath != null) {
              try {
                final dir = Directory(p.dirname(decodedPath));
                if (dir.existsSync()) dir.deleteSync(recursive: true);
              } catch (_) {}
            }
            ref.read(downloadHistoryProvider.notifier).remove(rec.filePath);
          },
        );
      },
    );
  }
}


class _DownloadRecordRow extends StatelessWidget {
  final DownloadRecord record;
  final TabPalette palette;
  final String? decodedVideoPath;
  final VoidCallback onOpenFolder;
  final VoidCallback onDecode;
  final VoidCallback? onPlay;
  final VoidCallback onDelete;

  const _DownloadRecordRow({
    required this.record,
    required this.palette,
    required this.onOpenFolder,
    required this.onDecode,
    required this.onDelete,
    this.decodedVideoPath,
    this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final fileExists = File(record.filePath).existsSync();
    final dateStr = _fmtDate(record.downloadedAt);
    final sizeStr = _fmtSize(record.fileSizeBytes);

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth > 900;
      final thumbSize = wide ? 76.0 : 56.0;
      final hPad = wide ? 16.0 : 4.0;
      final vPad = wide ? 14.0 : 8.0;
      final titleSize = wide ? 15.0 : 13.0;
      final metaSize = wide ? 12.0 : 11.0;
      final iconSize = wide ? 22.0 : 20.0;

      return Padding(
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(wide ? 8 : 6),
              child: SizedBox(
                width: thumbSize,
                height: thumbSize,
                child: record.thumbnailUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: record.thumbnailUrl,
                        cacheManager: CatalogCacheManager.instance,
                        memCacheWidth: 200,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => Container(
                          color: kSurface2Color,
                          child: Icon(Icons.movie_rounded,
                              size: wide ? 32 : 24, color: kTextMuted),
                        ),
                      )
                    : Container(
                        color: kSurface2Color,
                        child: Icon(Icons.movie_rounded,
                            size: wide ? 32 : 24, color: kTextMuted),
                      ),
              ),
            ),
            SizedBox(width: wide ? 16 : 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(record.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: titleSize,
                          fontWeight: FontWeight.w500,
                          color: fileExists ? kTextPrimary : kTextMuted)),
                  if (record.subtitle != null) ...[
                    const SizedBox(height: 1),
                    Text(record.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: metaSize,
                            color: kSeriesPalette.primary.withValues(alpha: 0.8),
                            fontWeight: FontWeight.w500)),
                  ],
                  const SizedBox(height: 2),
                  Text(record.filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: metaSize, color: kTextMuted)),
                  const SizedBox(height: 2),
                  Text('$dateStr  •  $sizeStr',
                      style: TextStyle(fontSize: metaSize, color: kTextMuted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!fileExists && decodedVideoPath == null)
              Tooltip(
                message: 'File no longer exists on disk',
                child: Icon(Icons.warning_amber_rounded,
                    size: wide ? 16 : 14, color: Colors.amber),
              ),
            IconButton(
              icon: Icon(Icons.folder_open_rounded, color: kTextSecondary),
              iconSize: iconSize,
              tooltip: 'Open folder',
              onPressed: onOpenFolder,
            ),
            TextButton.icon(
              onPressed: decodedVideoPath != null
                  ? onPlay
                  : fileExists
                      ? onDecode
                      : null,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 48),
                padding: EdgeInsets.symmetric(horizontal: wide ? 12 : 8),
                foregroundColor: palette.primary,
                disabledForegroundColor: kTextMuted,
              ),
              icon: Icon(
                decodedVideoPath != null
                    ? Icons.play_circle_rounded
                    : Icons.lock_open_rounded,
                size: wide ? 17 : 15,
              ),
              label: Text(
                decodedVideoPath != null ? 'Play' : 'Decode',
                style: TextStyle(fontSize: wide ? 13 : 12),
              ),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline_rounded, color: kTextMuted),
              iconSize: iconSize,
              tooltip: 'Delete file',
              onPressed: () => showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: kDialogColor,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  title: Text('Delete download?',
                      style: TextStyle(
                          color: kTextPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  content: Text(
                    decodedVideoPath != null
                        ? 'This will permanently delete the decoded video folder and remove this entry from your download history.'
                        : 'This will permanently delete the file from disk and remove it from your download history.',
                    style: TextStyle(
                        color: kTextSecondary, fontSize: 13),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('Cancel',
                          style: TextStyle(color: kTextMuted)),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        onDelete();
                      },
                      child: const Text('Delete',
                          style: TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  String _fmtDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String _fmtSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

// ---------------------------------------------------------------------------
// Sort + Filter bar
// ---------------------------------------------------------------------------

class _SortFilterBar extends StatelessWidget {
  final List<CatalogEntry> entries;
  final _SortMode sortMode;
  final bool sortAsc;
  final Set<String> filterLanguages;
  final Set<String> filterGenres;
  final Set<int> filterYears;
  final bool filterDownloaded;
  final TabPalette palette;
  final void Function(_SortMode, bool) onSortChanged;
  final void Function(Set<String>) onLanguagesChanged;
  final void Function(Set<String>) onGenresChanged;
  final void Function(Set<int>) onYearsChanged;
  final VoidCallback onToggleDownloaded;
  final VoidCallback onClearFilters;

  const _SortFilterBar({
    required this.entries,
    required this.sortMode,
    required this.sortAsc,
    required this.filterLanguages,
    required this.filterGenres,
    required this.filterYears,
    this.filterDownloaded = false,
    required this.palette,
    required this.onSortChanged,
    required this.onLanguagesChanged,
    required this.onGenresChanged,
    required this.onYearsChanged,
    required this.onToggleDownloaded,
    required this.onClearFilters,
  });

  @override
  Widget build(BuildContext context) {
    final languages = entries
        .map((e) => e.language).whereType<String>().toSet().toList()..sort();
    final genres = entries
        .expand((e) => e.genres).toSet().toList()..sort();
    final years = entries
        .map((e) => e.date?.year).whereType<int>().toSet().toList()
        ..sort((a, b) => b.compareTo(a));

    final hasFilters = filterLanguages.isNotEmpty ||
        filterGenres.isNotEmpty || filterYears.isNotEmpty || filterDownloaded;

    return Row(
      children: [
        // ── Sort buttons ────────────────────────────────────────────────────
        _SortBtn(label: 'A–Z',    mode: _SortMode.alpha,  current: sortMode, asc: sortAsc, palette: palette, onTap: onSortChanged),
        const SizedBox(width: 4),
        _SortBtn(label: 'Date',   mode: _SortMode.date,   current: sortMode, asc: sortAsc, palette: palette, onTap: onSortChanged),
        const SizedBox(width: 4),
        _SortBtn(label: 'Rating', mode: _SortMode.rating, current: sortMode, asc: sortAsc, palette: palette, onTap: onSortChanged),
        const Spacer(),
        // ── Filter dropdowns ────────────────────────────────────────────────
        if (hasFilters) ...[
          _ClearBtn(onTap: onClearFilters),
          const SizedBox(width: 6),
        ],
        if (languages.isNotEmpty) ...[
          _FilterBtn(
            label: 'Language',
            options: languages,
            selected: filterLanguages,
            palette: palette,
            onChanged: onLanguagesChanged,
          ),
          const SizedBox(width: 6),
        ],
        if (genres.isNotEmpty) ...[
          _FilterBtn(
            label: 'Genre',
            options: genres,
            selected: filterGenres,
            palette: palette,
            onChanged: onGenresChanged,
          ),
          const SizedBox(width: 6),
        ],
        if (years.isNotEmpty) ...[
          _FilterBtn(
            label: 'Year',
            options: years.map((y) => '$y').toList(),
            selected: filterYears.map((y) => '$y').toSet(),
            palette: palette,
            onChanged: (s) => onYearsChanged(s.map(int.parse).toSet()),
          ),
          const SizedBox(width: 6),
        ],
        _ToggleFilterBtn(
          label: 'Downloaded',
          active: filterDownloaded,
          palette: palette,
          onTap: onToggleDownloaded,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _SortBtn extends StatelessWidget {
  final String label;
  final _SortMode mode;
  final _SortMode current;
  final bool asc;
  final TabPalette palette;
  final void Function(_SortMode, bool) onTap;

  const _SortBtn({
    required this.label,
    required this.mode,
    required this.current,
    required this.asc,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = current == mode;
    final color = active ? palette.primary : kTextSecondary;
    return GestureDetector(
      onTap: () => onTap(mode, active ? !asc : true),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? palette.primary.withValues(alpha: 0.1) : kSurfaceColor,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: active ? palette.primary.withValues(alpha: 0.45) : kBorderColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: color)),
            if (active) ...[
              const SizedBox(width: 3),
              Icon(
                asc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                size: 11, color: color,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ToggleFilterBtn extends StatelessWidget {
  final String label;
  final bool active;
  final TabPalette palette;
  final VoidCallback onTap;

  const _ToggleFilterBtn({
    required this.label,
    required this.active,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? palette.primary : kTextSecondary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? palette.primary.withValues(alpha: 0.1) : kSurfaceColor,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: active ? palette.primary.withValues(alpha: 0.45) : kBorderColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (active) ...[
              Icon(Icons.download_done_rounded, size: 11, color: color),
              const SizedBox(width: 4),
            ],
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _FilterBtn extends StatefulWidget {
  final String label;
  final List<String> options;
  final Set<String> selected;
  final TabPalette palette;
  final void Function(Set<String>) onChanged;

  const _FilterBtn({
    required this.label,
    required this.options,
    required this.selected,
    required this.palette,
    required this.onChanged,
  });

  @override
  State<_FilterBtn> createState() => _FilterBtnState();
}

class _FilterBtnState extends State<_FilterBtn> {
  final _link = LayerLink();
  final _overlay = OverlayPortalController();

  @override
  Widget build(BuildContext context) {
    final active = widget.selected.isNotEmpty;
    final labelText = active
        ? '${widget.label} (${widget.selected.length})'
        : widget.label;
    final color = active ? widget.palette.primary : kTextSecondary;

    return CompositedTransformTarget(
      link: _link,
      child: TapRegion(
        groupId: _overlay,
        onTapOutside: (_) => _overlay.hide(),
        child: OverlayPortal(
          controller: _overlay,
          overlayChildBuilder: (_) => CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 4),
            showWhenUnlinked: false,
            child: Align(
              alignment: Alignment.topRight,
              child: TapRegion(
                groupId: _overlay,
                child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(
                      minWidth: 150, maxWidth: 220, maxHeight: 280),
                    decoration: BoxDecoration(
                      color: kSurfaceColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: kBorderColor),
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 16)
                      ],
                    ),
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      shrinkWrap: true,
                      children: widget.options.map((opt) {
                        final checked = widget.selected.contains(opt);
                        return InkWell(
                          onTap: () {
                            final next = Set<String>.from(widget.selected);
                            if (checked) { next.remove(opt); } else { next.add(opt); }
                            widget.onChanged(next);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            child: Row(
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 100),
                                  width: 15, height: 15,
                                  decoration: BoxDecoration(
                                    color: checked
                                        ? widget.palette.primary
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(
                                      color: checked
                                          ? widget.palette.primary
                                          : kBorderColor,
                                    ),
                                  ),
                                  child: checked
                                      ? const Icon(Icons.check_rounded,
                                          size: 11, color: Colors.black)
                                      : null,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(opt,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: checked
                                              ? kTextPrimary
                                              : kTextSecondary)),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          child: GestureDetector(
            onTap: _overlay.toggle,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: active
                    ? widget.palette.primary.withValues(alpha: 0.1)
                    : kSurfaceColor,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: active
                      ? widget.palette.primary.withValues(alpha: 0.45)
                      : kBorderColor,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(labelText,
                      style: TextStyle(fontSize: 12, color: color)),
                  const SizedBox(width: 3),
                  Icon(Icons.keyboard_arrow_down_rounded,
                      size: 13, color: color),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ClearBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _ClearBtn({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: kSurfaceColor,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: kBorderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.close_rounded, size: 11, color: kTextMuted),
            const SizedBox(width: 4),
            Text('Clear', style: TextStyle(fontSize: 12, color: kTextMuted)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-tab bottom bar — Movies / Series
// ---------------------------------------------------------------------------

class _SubTabBar extends StatelessWidget {
  final int activeIndex;
  final Color surfaceColor;
  final ValueChanged<int> onChanged;

  const _SubTabBar({
    required this.activeIndex,
    required this.surfaceColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Themes with a gradient backdrop use a transparent page surface; forcing an
    // alpha onto it would fade to pure black. Fall back to the theme bg instead.
    final base = surfaceColor.a == 0 ? kBgColor : surfaceColor;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                base.withValues(alpha: 0.0),
                base.withValues(alpha: 0.92),
              ],
              stops: const [0.0, 0.38],
            ),
          ),
          alignment: Alignment.bottomCenter,
          padding: const EdgeInsets.only(bottom: 6),
          child: Stack(
            children: [
              Row(
                children: [
                  _SubTabItem(
                    icon: Icons.movie_rounded,
                    label: 'Movies',
                    active: activeIndex == 0,
                    palette: AppTab.catalog.palette,
                    onTap: () => onChanged(0),
                  ),
                  _SubTabItem(
                    icon: Icons.live_tv_rounded,
                    label: 'Series',
                    active: activeIndex == 1,
                    palette: kSeriesPalette,
                    onTap: () => onChanged(1),
                  ),
                ],
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 2,
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeInOut,
                  alignment: activeIndex == 0
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: FractionallySizedBox(
                    widthFactor: 0.5,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      color: activeIndex == 0
                          ? AppTab.catalog.palette.primary
                          : kSeriesPalette.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubTabItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final TabPalette palette;
  final VoidCallback onTap;

  const _SubTabItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? palette.primary : kTextMuted;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  color: color,
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
// Series body — handles the four catalog states
// ---------------------------------------------------------------------------

class _SeriesBody extends StatelessWidget {
  final SeriesCatalogState state;
  final String search;
  final Set<String> downloadedTitles;
  final void Function(SeriesEntry) onCardExpand;

  const _SeriesBody({
    required this.state,
    required this.search,
    required this.downloadedTitles,
    required this.onCardExpand,
  });

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      SeriesCatalogIdle()    => _SeriesEmptyState(),
      SeriesCatalogLoading() => Center(
          child: CircularProgressIndicator(color: kSeriesPalette.primary)),
      SeriesCatalogError(:final message) => _ErrorState(message: message),
      SeriesCatalogLoaded(:final series) => series.isEmpty
          ? _SeriesEmptyState()
          : _SeriesGrid(
              all: series,
              filtered: _filter(series),
              downloadedTitles: downloadedTitles,
              onCardExpand: onCardExpand,
            ),
    };
  }

  List<SeriesEntry> _filter(List<SeriesEntry> all) {
    if (search.isEmpty) return all;
    final q = search.toLowerCase();
    return all.where((e) {
      return e.title.toLowerCase().contains(q) ||
          e.plot.toLowerCase().contains(q) ||
          e.genres.any((g) => g.toLowerCase().contains(q)) ||
          e.tags.any((t) => t.toLowerCase().contains(q));
    }).toList();
  }
}

class _SeriesEmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.live_tv_outlined, size: 48, color: kTextMuted)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(
                  begin: 0.92,
                  end: 1.0,
                  duration: 1800.ms,
                  curve: Curves.easeInOut),
          const SizedBox(height: 16),
          Text(
            'No series yet',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600, color: kTextPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            'Add a "Series" tab to your spreadsheet to get started.',
            style: TextStyle(fontSize: 13, color: kTextMuted),
          ),
        ],
      ),
    );
  }
}

class _SeriesGrid extends StatefulWidget {
  final List<SeriesEntry> all;
  final List<SeriesEntry> filtered;
  final Set<String> downloadedTitles;
  final void Function(SeriesEntry) onCardExpand;

  const _SeriesGrid({
    required this.all,
    required this.filtered,
    required this.downloadedTitles,
    required this.onCardExpand,
  });

  @override
  State<_SeriesGrid> createState() => _SeriesGridState();
}

class _SeriesGridState extends State<_SeriesGrid> {
  double _aspectRatio = 2 / 3;
  final _ratios = <double>[];

  @override
  void initState() {
    super.initState();
    _resolveRatios(widget.all);
  }

  @override
  void didUpdateWidget(_SeriesGrid old) {
    super.didUpdateWidget(old);
    if (old.all != widget.all) {
      final oldUrls = old.all.map((e) => e.posterUrl).toSet();
      final newEntries = widget.all
          .where((e) =>
              e.posterUrl.isNotEmpty && !oldUrls.contains(e.posterUrl))
          .toList();
      if (newEntries.isNotEmpty) _resolveRatios(newEntries);
    }
  }

  void _resolveRatios(List<SeriesEntry> entries) {
    final urls =
        entries.map((e) => e.posterUrl).where((u) => u.isNotEmpty).toSet();
    for (final url in urls) {
      final provider = CachedNetworkImageProvider(url,
          cacheManager: CatalogCacheManager.instance);
      final stream = provider.resolve(const ImageConfiguration());
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (ImageInfo info, _) {
          stream.removeListener(listener);
          final w = info.image.width;
          final h = info.image.height;
          if (h > 0) _onRatio(w / h);
        },
        onError: (_, _) => stream.removeListener(listener),
      );
      stream.addListener(listener);
    }
  }

  void _onRatio(double ratio) {
    _ratios.add(ratio);
    final portraits = _ratios.where((r) => r < 1.0).toList();
    if (portraits.isEmpty) return;
    final sorted = List<double>.from(portraits)..sort();
    final median = sorted[sorted.length ~/ 2];
    if ((median - _aspectRatio).abs() > 0.02 && mounted) {
      setState(() => _aspectRatio = median);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.filtered.isEmpty) {
      return Center(
        child: Text('No results.',
            style: TextStyle(color: kTextMuted, fontSize: 14)),
      );
    }
    return MasonryGridView.builder(
      gridDelegate: const SliverSimpleGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
      ),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      itemCount: widget.filtered.length,
      itemBuilder: (_, i) {
        final entry = widget.filtered[i];
        return SeriesCard(
          key: ValueKey(entry.title),
          entry: entry,
          aspectRatio: _aspectRatio,
          isDownloaded:
              widget.downloadedTitles.any((t) => t.startsWith(entry.title)),
          onExpand: () => widget.onCardExpand(entry),
        )
            .animate()
            .fadeIn(
                duration: 280.ms,
                delay: Duration(milliseconds: min(i, 9) * 35))
            .slideY(begin: 0.06, duration: 280.ms, curve: Curves.easeOut);
      },
    );
  }
}

// ── Request Dialog ─────────────────────────────────────────────────────────────

class _RequestDialog extends ConsumerStatefulWidget {
  const _RequestDialog();

  @override
  ConsumerState<_RequestDialog> createState() => _RequestDialogState();
}

class _RequestDialogState extends ConsumerState<_RequestDialog> {
  final _ctrl = TextEditingController();
  final _palette = AppTab.catalog.palette;
  RequestReady? _lastReady;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    // Auto-validate once a plausible IMDB URL is pasted.
    if (value.contains('imdb.com/title/tt')) {
      ref.read(requestProvider.notifier).validate(value);
    } else {
      ref.read(requestProvider.notifier).reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(requestProvider);

    return Dialog(
      backgroundColor: kDialogColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(children: [
                Icon(Icons.add_circle_outline_rounded,
                    color: _palette.primary, size: 18),
                const SizedBox(width: 8),
                Text('Request',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _palette.primary)),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Icon(Icons.close_rounded,
                      size: 18, color: kTextMuted),
                ),
              ]),
              const SizedBox(height: 16),

              // URL input
              TextField(
                controller: _ctrl,
                autofocus: true,
                enabled: state is! RequestSubmitting && state is! RequestSuccess,
                onChanged: _onChanged,
                style: TextStyle(fontSize: 13, color: kTextPrimary),
                decoration: InputDecoration(
                  hintText: 'Paste IMDB URL  (imdb.com/title/tt…)',
                  hintStyle: TextStyle(fontSize: 13, color: kTextMuted),
                  filled: true,
                  fillColor: kSurface2Color,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: kBorderColor)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: kBorderColor)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: _palette.primary)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  suffixIcon: state is RequestValidating
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: _palette.primary),
                          ),
                        )
                      : null,
                ),
              ),

              // State-driven content
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                child: _buildStateContent(state),
              ),

              const SizedBox(height: 20),

              // Footer actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                        foregroundColor: kTextSecondary),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: state is RequestReady
                        ? () => ref.read(requestProvider.notifier).submit()
                        : state is RequestSuccess
                            ? () => Navigator.pop(context)
                            : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: _palette.primary,
                      foregroundColor: onAccentColor(_palette.primary),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: state is RequestSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black54),
                          )
                        : Text(state is RequestSuccess ? 'Done' : 'Submit'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStateContent(RequestState state) {
    if (state is RequestReady) {
      _lastReady = state;
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: _PreviewCard(state: state, palette: _palette),
      );
    }
    if (state is RequestSubmitting) {
      return _lastReady != null
          ? Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _PreviewCard(state: _lastReady!, palette: _palette),
            )
          : const SizedBox.shrink();
    }
    if (state is RequestSuccess) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_lastReady != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _PreviewCard(state: _lastReady!, palette: _palette),
            ),
          _StatusBanner(
            icon: Icons.check_circle_outline_rounded,
            color: const Color(0xFF4ADE80),
            message: 'Request submitted! The admin will review it shortly.',
          ),
        ],
      );
    }
    if (state is RequestDuplicate) {
      final preview = RequestReady(
        imdbId: state.imdbId,
        imdbUrl: state.imdbUrl,
        title: state.title,
        year: state.year,
        type: state.type,
        posterUrl: state.posterUrl,
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: _PreviewCard(state: preview, palette: _palette),
          ),
          _StatusBanner(
            icon: Icons.info_outline_rounded,
            color: const Color(0xFFF59E0B),
            message: '"${state.title}" has already been requested.',
          ),
        ],
      );
    }
    if (state is RequestError) {
      return _StatusBanner(
        icon: Icons.error_outline_rounded,
        color: Colors.redAccent,
        message: state.message,
      );
    }
    return const SizedBox.shrink();
  }
}

class _PreviewCard extends StatelessWidget {
  final RequestReady state;
  final TabPalette palette;

  const _PreviewCard({required this.state, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kSurface2Color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.posterUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: state.posterUrl,
                width: 56,
                height: 84,
                fit: BoxFit.cover,
                cacheManager: CatalogCacheManager.instance,
                errorWidget: (_, _, _) => _posterPlaceholder(),
              ),
            )
          else
            _posterPlaceholder(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: kTextPrimary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Wrap(spacing: 6, children: [
                  if (state.year != null)
                    _Chip(label: '${state.year}'),
                  _Chip(label: state.type),
                  _Chip(label: state.imdbId),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _posterPlaceholder() => Container(
        width: 56,
        height: 84,
        decoration: BoxDecoration(
          color: kSurface2Color,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: kBorderColor),
        ),
        child: Icon(Icons.movie_rounded, size: 24, color: kTextMuted),
      );
}

class _StatusBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;

  const _StatusBanner({
    required this.icon,
    required this.color,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(fontSize: 12, color: kTextSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;

  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: kSurface2Color,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: kBorderColor),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 10, color: kTextSecondary)),
    );
  }
}
