import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:path/path.dart' as p;
import '../../core/providers/decode_request_provider.dart';
import '../../core/providers/player_request_provider.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tab_colors.dart';
import '../shell/app_shell.dart';
import 'catalog_notifier.dart';
import 'models/catalog_entry.dart';
import 'widgets/catalog_card.dart';
import 'widgets/webview_overlay.dart';

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

  // Expanded card overlay state
  CatalogEntry? _expandedEntry;
  Rect _expandedLocalRect = Rect.zero;
  Rect _bodyLocalRect = Rect.zero;
  late final AnimationController _expandAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  final _bodyKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _urlController.dispose();
    _searchController.dispose();
    _focusNode.dispose();
    _expandAnim.dispose();
    super.dispose();
  }

  bool _onHardwareKey(KeyEvent event) {
    if (!mounted || event is! KeyDownEvent) return false;
    if (event.logicalKey == LogicalKeyboardKey.keyD) {
      setState(() => _showDownloads = !_showDownloads);
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

  @override
  Widget build(BuildContext context) {
    final palette = AppTab.catalog.palette;
    final sheetUrl = ref.watch(sheetUrlProvider);
    final catalogState = ref.watch(catalogProvider);
    final downloadState = ref.watch(downloadProvider);
    final historyCount = ref.watch(downloadHistoryProvider).length;

    if (sheetUrl != null && catalogState is CatalogIdle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(catalogProvider.notifier).load(sheetUrl);
      });
    }

    final fadeAnim =
        CurvedAnimation(parent: _expandAnim, curve: Curves.easeOut);

    final catalogUi = Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
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
        padding: const EdgeInsets.all(24),
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
              onSearch: (v) => setState(() => _search = v),
              onSubmitUrl: (url) async {
                await ref.read(sheetUrlProvider.notifier).save(url);
                ref.read(catalogProvider.notifier).load(url);
              },
              onRefresh: _showDownloads
                  ? () =>
                      ref.read(downloadHistoryProvider.notifier).pruneDeleted()
                  : sheetUrl != null
                      ? () => ref.read(catalogProvider.notifier).load(sheetUrl)
                      : null,
              onClearUrl: () {
                ref.read(sheetUrlProvider.notifier).clear();
                ref.read(catalogProvider.notifier).reset();
              },
              onToggleDownloads: () =>
                  setState(() => _showDownloads = !_showDownloads),
            ),
            const SizedBox(height: 20),
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
                          : _Body(
                              state: catalogState,
                              search: _search,
                              palette: palette,
                              onOpenInBrowser: _openWebView,
                              onCardExpand: _onCardExpand,
                            ),
                    ),
                    if (downloadState is DownloadActive ||
                        downloadState is DownloadDone ||
                        downloadState is DownloadError)
                      _DownloadPanel(
                        state: downloadState,
                        palette: palette,
                        onDismiss: () =>
                            ref.read(downloadProvider.notifier).dismiss(),
                        onCancel: () =>
                            ref.read(downloadProvider.notifier).cancel(),
                        onDecodeThis: (path) {
                          ref
                              .read(decodeOpenRequestProvider.notifier)
                              .state = path;
                          ref.read(activeTabProvider.notifier).state =
                              AppTab.decode;
                        },
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
    return Stack(
      children: [
        catalogUi,
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
            onClose: _closeExpanded,
            onOpenInBrowser: () {
              _closeExpanded();
              _openWebView(_expandedEntry!);
            },
          ),
        ],
      ],
    );
  }

  void _openWebView(CatalogEntry entry) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => WebViewOverlay(
        url: entry.photosUrl,
        title: entry.title,
        onDownloadRequested: (url, filename) {
          ref.read(downloadProvider.notifier).enqueue(
                url,
                filename ?? '',
                entry.title,
                entry.thumbnailUrl,
              );
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
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onSubmitUrl;
  final VoidCallback? onRefresh;
  final VoidCallback onClearUrl;
  final VoidCallback onToggleDownloads;

  const _TopBar({
    required this.palette,
    required this.sheetUrl,
    required this.urlController,
    required this.searchController,
    required this.showDownloads,
    required this.historyCount,
    required this.onSearch,
    required this.onSubmitUrl,
    required this.onRefresh,
    required this.onClearUrl,
    required this.onToggleDownloads,
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
  final TabPalette palette;
  final ValueChanged<CatalogEntry> onOpenInBrowser;
  final void Function(CatalogEntry, Rect) onCardExpand;

  const _Body({
    required this.state,
    required this.search,
    required this.palette,
    required this.onOpenInBrowser,
    required this.onCardExpand,
  });

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      CatalogIdle() => _EmptyState(palette: palette),
      CatalogLoading() => Center(
          child: CircularProgressIndicator(color: palette.primary)),
      CatalogError(:final message) => _ErrorState(message: message),
      CatalogLoaded(:final entries) => _Grid(
          entries: _filter(entries),
          palette: palette,
          onOpenInBrowser: onOpenInBrowser,
          onCardExpand: onCardExpand,
        ),
    };
  }

  List<CatalogEntry> _filter(List<CatalogEntry> entries) {
    if (search.isEmpty) return entries;
    final q = search.toLowerCase();
    return entries.where((e) {
      return e.title.toLowerCase().contains(q) ||
          e.description.toLowerCase().contains(q) ||
          e.tags.any((t) => t.toLowerCase().contains(q));
    }).toList();
  }
}

class _Grid extends StatefulWidget {
  final List<CatalogEntry> entries;
  final TabPalette palette;
  final ValueChanged<CatalogEntry> onOpenInBrowser;
  final void Function(CatalogEntry, Rect) onCardExpand;

  const _Grid({
    required this.entries,
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
    _resolveRatios(widget.entries);
  }

  @override
  void didUpdateWidget(_Grid old) {
    super.didUpdateWidget(old);
    if (old.entries != widget.entries) {
      _ratios.clear();
      _resolveRatios(widget.entries);
    }
  }

  void _resolveRatios(List<CatalogEntry> entries) {
    final urls = entries
        .map((e) => e.thumbnailUrl)
        .where((u) => u.isNotEmpty)
        .toSet();
    for (final url in urls) {
      final provider = CachedNetworkImageProvider(url);
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
    // Prefer portrait thumbnails (ratio < 1) — most movie posters are tall.
    final candidates = _ratios.where((r) => r < 1.0).toList();
    final pool = candidates.isNotEmpty ? candidates : _ratios;
    final sorted = List<double>.from(pool)..sort();
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
      itemBuilder: (_, i) => CatalogCard(
        entry: widget.entries[i],
        aspectRatio: _aspectRatio,
        onOpenInBrowser: () => widget.onOpenInBrowser(widget.entries[i]),
        onExpand: (rect) => widget.onCardExpand(widget.entries[i], rect),
      ),
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
  final VoidCallback onClose;
  final VoidCallback onOpenInBrowser;

  const _CardDetail({
    required this.entry,
    required this.localCardRect,
    required this.bodyRect,
    required this.animation,
    required this.palette,
    required this.onClose,
    required this.onOpenInBrowser,
  });

  @override
  Widget build(BuildContext context) {
    const expandedW = 360.0;
    const edgePad = 16.0;

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
              entry: entry,
              palette: palette,
              onClose: onClose,
              onOpenInBrowser: onOpenInBrowser,
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
  final void Function(String filePath) onDecodeThis;

  const _DownloadPanel({
    required this.state,
    required this.palette,
    required this.onDismiss,
    required this.onCancel,
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
        LinearProgressIndicator(
          value: progress,
          color: palette.primary,
          backgroundColor: kSurface2Color,
          minHeight: 4,
          borderRadius: BorderRadius.circular(2),
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
                  style: const TextStyle(fontSize: 12, color: kTextSecondary),
                ),
                Text(
                  folder,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: kTextMuted),
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

  const _ErrorDownload({required this.message, required this.onDismiss});

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
          Icon(Icons.photo_library_outlined, size: 48, color: kTextMuted),
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
    final folder = Directory(p.join(decodeDir, record.title));
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
          onOpenFolder: () =>
              Process.run('explorer.exe', [p.dirname(rec.filePath)]),
          onDecode: () => onDecodeFile(rec.filePath),
          onPlay: decodedPath != null ? () => onPlayFile(decodedPath) : null,
          onDelete: () =>
              ref.read(downloadHistoryProvider.notifier).remove(rec.filePath),
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
            if (!fileExists)
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
              icon: const Icon(Icons.delete_outline_rounded, color: kTextMuted),
              iconSize: iconSize,
              tooltip: 'Remove from history',
              onPressed: onDelete,
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
