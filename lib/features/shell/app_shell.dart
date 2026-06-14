import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../core/providers/player_request_provider.dart';
import '../../core/services/gh_auth_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tab_colors.dart';
import '../../core/theme/theme_spec.dart';
import '../updater/update_model.dart';
import '../updater/update_notifier.dart';
import '../admin/admin_screen.dart';
import '../decode/decode_notifier.dart';
import '../encode/encode_notifier.dart';
import '../encode/encode_screen.dart';
import '../decode/decode_screen.dart';
import '../player/player_screen.dart';
import '../catalog/catalog_screen.dart';
import '../catalog/catalog_notifier.dart';
import '../catalog/series_notifier.dart' show catalogSubPaletteProvider;
import '../settings/settings_screen.dart';

// Startup tab = first item in the effective page order.
// ref.read (not watch) so user navigation doesn't get overridden on rebuilds.
final activeTabProvider = StateProvider<AppTab>((ref) {
  final settings = ref.read(settingsProvider);
  if (settings.tabOrder != null && settings.tabOrder!.isNotEmpty) {
    return AppTab.values[settings.tabOrder!.first.clamp(
      0,
      AppTab.settings.index,
    )];
  }
  return AppTab.catalog;
});

final ghAuthProvider = FutureProvider<bool>(
  (ref) => GhAuthService().isAuthorized(),
);

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with SingleTickerProviderStateMixin
    implements WindowListener {
  late final AnimationController _ctrl;
  late final Animation<double> _enterFade;
  late final Animation<Offset> _enterSlide;
  late final Animation<double> _exitFade;

  AppTab? _exitingTab;
  bool _isMaximized = false;
  final List<_ToastEntry> _toasts = [];

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initWindowState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..value = 1.0;

    final curved = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _enterFade = curved;
    _enterSlide = Tween<Offset>(
      begin: const Offset(0, 0.055),
      end: Offset.zero,
    ).animate(curved);
    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(curved);

    _ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _exitingTab = null);
      }
    });
  }

  Future<void> _initWindowState() async {
    _isMaximized = await windowManager.isMaximized();
    if (mounted) setState(() {});
  }

  void _addToast(String message, TabPalette palette, AppTab target) {
    final id = DateTime.now().microsecondsSinceEpoch;
    final entry = _ToastEntry(
      id: id,
      message: message,
      palette: palette,
      target: target,
      timer: Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _toasts.removeWhere((t) => t.id == id));
      }),
    );
    if (mounted) setState(() => _toasts.add(entry));
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _ctrl.dispose();
    for (final t in _toasts) {
      t.timer.cancel();
    }
    super.dispose();
  }

  // ── WindowListener ─────────────────────────────────────────────────────

  @override
  void onWindowMaximize() => setState(() => _isMaximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _isMaximized = false);

  // ── WindowListener no-ops ───────────────────────────────────────────────

  @override
  void onWindowResize() {}
  @override
  void onWindowResized() {}
  @override
  void onWindowMove() {}
  @override
  void onWindowMoved() {}
  @override
  void onWindowEvent(String eventName) {}
  @override
  void onWindowFocus() {}
  @override
  void onWindowBlur() {}
  @override
  void onWindowMinimize() {}
  @override
  void onWindowRestore() {}
  @override
  void onWindowEnterFullScreen() {}
  @override
  void onWindowLeaveFullScreen() {}
  @override
  void onWindowClose() {}
  @override
  void onWindowDocked() {}
  @override
  void onWindowUndocked() {}

  // ── Dialog & styles ─────────────────────────────────────────────────────

  void _showUpdateDialog(
    BuildContext context,
    UpdateInfo info,
    TabPalette palette,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: kDialogColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: palette.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.system_update_rounded,
                color: palette.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Update available',
                  style: TextStyle(
                    color: kTextPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'v${info.version} is ready to download',
                  style: TextStyle(
                    color: kTextSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ],
        ),
        content: info.releaseNotes.isNotEmpty
            ? SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "What's new",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: palette.primary,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: Markdown(
                        data: info.releaseNotes,
                        shrinkWrap: true,
                        padding: const EdgeInsets.only(top: 4),
                        styleSheet: _mdStyle(palette),
                      ),
                    ),
                  ],
                ),
              )
            : null,
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(updateProvider.notifier).dismiss();
            },
            child: Text('Later', style: TextStyle(color: kTextMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(activeTabProvider.notifier).state = AppTab.settings;
              ref.read(updateProvider.notifier).downloadUpdate();
            },
            style: TextButton.styleFrom(foregroundColor: palette.primary),
            child: Text(
              'Update Now',
              style: TextStyle(
                color: palette.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  MarkdownStyleSheet _mdStyle(TabPalette palette) => MarkdownStyleSheet(
    p: TextStyle(fontSize: 12, color: kTextSecondary, height: 1.6),
    h1: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: palette.primary,
    ),
    h2: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: palette.primary,
    ),
    h3: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: kTextPrimary,
    ),
    strong: TextStyle(fontWeight: FontWeight.w600, color: kTextPrimary),
    em: TextStyle(fontStyle: FontStyle.italic, color: kTextSecondary),
    code: TextStyle(fontSize: 11, color: kTextPrimary, fontFamily: 'monospace'),
    codeblockDecoration: BoxDecoration(
      color: kSurface2Color,
      borderRadius: BorderRadius.circular(6),
    ),
    blockquoteDecoration: BoxDecoration(
      border: Border(left: BorderSide(color: palette.primary, width: 3)),
    ),
    listBullet: TextStyle(fontSize: 12, color: kTextSecondary),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: kBorderColor)),
    ),
  );

  Widget _screenFor(AppTab tab) => switch (tab) {
    AppTab.encode => const EncodeScreen(),
    AppTab.decode => const DecodeScreen(),
    AppTab.player => const PlayerScreen(),
    AppTab.catalog => const CatalogScreen(),
    AppTab.settings => const SettingsScreen(),
    AppTab.admin => const AdminScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final activeTab = ref.watch(activeTabProvider);
    final isFullscreen = ref.watch(playerFullscreenProvider);
    final subPalette = ref.watch(catalogSubPaletteProvider);
    final palette = (activeTab == AppTab.catalog && subPalette != null)
        ? subPalette
        : activeTab.palette;

    ref.listen(activeTabProvider, (prev, next) {
      if (prev != null && prev != next) {
        setState(() => _exitingTab = prev);
        _ctrl.forward(from: 0);
      }
    });

    ref.listen(updateProvider, (prev, next) {
      if (prev?.status != UpdateStatus.available &&
          next.status == UpdateStatus.available) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showUpdateDialog(context, next.info!, palette);
        });
      }
    });

    ref.listen(encodeProvider, (prev, next) {
      if (prev?.step != EncodeStep.done && next.step == EncodeStep.done) {
        if (ref.read(activeTabProvider) != AppTab.encode) {
          _addToast('Encode complete', AppTab.encode.palette, AppTab.encode);
        }
      }
    });

    ref.listen(decodeProvider, (prev, next) {
      if (prev?.step != DecodeStep.done && next.step == DecodeStep.done) {
        if (ref.read(activeTabProvider) != AppTab.decode) {
          _addToast('Decode complete', AppTab.decode.palette, AppTab.decode);
        }
      }
    });

    ref.listen(downloadProvider, (prev, next) {
      if (prev is! DownloadDone && next is DownloadDone) {
        if (ref.read(activeTabProvider) != AppTab.catalog) {
          _addToast(
            'Download complete',
            AppTab.catalog.palette,
            AppTab.catalog,
          );
        }
      }
    });

    return AnimatedTheme(
      duration: const Duration(milliseconds: 300),
      data: Theme.of(context),
      child: Scaffold(
        backgroundColor: kBgColor,
        body: Stack(
          children: [
            Column(
              children: [
                if (!isFullscreen)
                  _TitleBar(
                    activeTab: activeTab,
                    palette: palette,
                    isMaximized: _isMaximized,
                  ),
                Expanded(
                  child: Row(
                    children: [
                      if (!isFullscreen)
                        _Sidebar(activeTab: activeTab, palette: palette),
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              decoration: BoxDecoration(
                                color: activeSpec.gradientBg == null
                                    ? palette.surface
                                    : null,
                                gradient: activeSpec.gradientBg == null
                                    ? null
                                    : LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: activeSpec.gradientBg!,
                                      ),
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                children: AppTab.values.map((tab) {
                                  final isActive = tab == activeTab;
                                  final isExiting = tab == _exitingTab;

                                  if (!isActive && !isExiting) {
                                    // Player keeps tickers so audio continues off-tab;
                                    // all other tabs are fully frozen.
                                    return Offstage(
                                      offstage: true,
                                      child: tab == AppTab.player
                                          ? _screenFor(tab)
                                          : TickerMode(
                                              enabled: false,
                                              child: _screenFor(tab),
                                            ),
                                    );
                                  }

                                  if (isActive) {
                                    return AnimatedBuilder(
                                      animation: _ctrl,
                                      builder: (_, child) => FadeTransition(
                                        opacity: _enterFade,
                                        child: SlideTransition(
                                          position: _enterSlide,
                                          child: child,
                                        ),
                                      ),
                                      child: _screenFor(tab),
                                    );
                                  }

                                  return IgnorePointer(
                                    child: AnimatedBuilder(
                                      animation: _ctrl,
                                      builder: (_, child) => FadeTransition(
                                        opacity: _exitFade,
                                        child: child,
                                      ),
                                      child: _screenFor(tab),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                            if (activeSpec.scanlines)
                              const Positioned.fill(
                                child: IgnorePointer(child: _ScanlineOverlay()),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_toasts.isNotEmpty)
              Positioned(
                top: 60,
                right: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: _toasts
                      .map(
                        (t) => _ToastCard(
                          toast: t,
                          onTap: () {
                            t.timer.cancel();
                            setState(
                              () => _toasts.removeWhere((e) => e.id == t.id),
                            );
                            ref.read(activeTabProvider.notifier).state =
                                t.target;
                          },
                          onDismiss: () {
                            t.timer.cancel();
                            setState(
                              () => _toasts.removeWhere((e) => e.id == t.id),
                            );
                          },
                        ),
                      )
                      .toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TitleBar extends ConsumerWidget {
  final AppTab activeTab;
  final TabPalette palette;
  final bool isMaximized;

  const _TitleBar({
    required this.activeTab,
    required this.palette,
    required this.isMaximized,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: () async {
        if (isMaximized) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: 48,
        decoration: BoxDecoration(
          color: kSurfaceColor,
          border: Border(bottom: BorderSide(color: kBorderColor)),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.primary,
                boxShadow: [BoxShadow(color: palette.glow, blurRadius: 8)],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'mStorage',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: kTextPrimary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                '— ${activeTab.name[0].toUpperCase()}${activeTab.name.substring(1)}',
                key: ValueKey(activeTab),
                style: TextStyle(fontSize: 13, color: palette.primary),
              ),
            ),
            const Spacer(),
            _WindowButton(
              icon: Icons.remove_rounded,
              tooltip: 'Minimize',
              onTap: () => windowManager.minimize(),
            ),
            _WindowButton(
              icon: isMaximized
                  ? Icons.filter_none_rounded
                  : Icons.crop_square_rounded,
              tooltip: isMaximized ? 'Restore' : 'Maximize',
              onTap: () async {
                if (isMaximized) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
            ),
            _WindowButton(
              icon: Icons.close_rounded,
              tooltip: 'Close',
              onTap: () => windowManager.close(),
              isClose: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isClose;

  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isClose = false,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      preferBelow: true,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 46,
            height: 48,
            color: _hovered
                ? (widget.isClose
                      ? const Color(
                          0xFFE81123,
                        ).withValues(alpha: _pressed ? 1.0 : 0.85)
                      : kSurface2Color)
                : Colors.transparent,
            child: AnimatedScale(
              scale: _pressed ? 0.88 : 1.0,
              duration: const Duration(milliseconds: 80),
              child: Icon(widget.icon, size: 16, color: kTextSecondary),
            ),
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends ConsumerStatefulWidget {
  final AppTab activeTab;
  final TabPalette palette;

  const _Sidebar({required this.activeTab, required this.palette});

  @override
  ConsumerState<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<_Sidebar> {
  AppTab? _hovered;

  static const _baseItems = [
    (AppTab.encode, Icons.upload_rounded, 'Encode'),
    (AppTab.decode, Icons.download_rounded, 'Decode'),
    (AppTab.player, Icons.play_circle_rounded, 'Player'),
    (AppTab.catalog, Icons.photo_library_rounded, 'Catalog'),
    (AppTab.settings, Icons.settings_rounded, 'Settings'),
  ];

  static const _adminItem = (
    AppTab.admin,
    Icons.admin_panel_settings_rounded,
    'Admin',
  );

  @override
  Widget build(BuildContext context) {
    final encodeRunning = ref.watch(encodeProvider).isRunning;
    final decodeRunning = ref.watch(decodeProvider).isRunning;
    final playerPlaying = ref.watch(playerPlayingProvider);
    final isAdmin = ref.watch(ghAuthProvider).valueOrNull ?? false;
    final updateStatus = ref.watch(updateProvider).status;

    final settings = ref.watch(settingsProvider);
    final List<(AppTab, IconData, String)> base;
    if (settings.tabOrder != null) {
      base = settings.tabOrder!
          .where((i) => i <= AppTab.settings.index)
          .map((i) => _baseItems.firstWhere((item) => item.$1.index == i))
          .toList();
    } else {
      final sheetUrl = ref.watch(sheetUrlProvider);
      if (sheetUrl != null) {
        base = [
          _baseItems.firstWhere((i) => i.$1 == AppTab.catalog),
          _baseItems.firstWhere((i) => i.$1 == AppTab.player),
          _baseItems.firstWhere((i) => i.$1 == AppTab.encode),
          _baseItems.firstWhere((i) => i.$1 == AppTab.decode),
          _baseItems.firstWhere((i) => i.$1 == AppTab.settings),
        ];
      } else {
        base = List.of(_baseItems);
      }
    }
    final items = isAdmin ? [...base, _adminItem] : base;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 72,
      decoration: BoxDecoration(
        color: kSurfaceColor,
        border: Border(right: BorderSide(color: kBorderColor)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          for (final item in items)
            _SidebarItem(
              tab: item.$1,
              icon: item.$2,
              label: item.$3,
              isActive: widget.activeTab == item.$1,
              isHovered: _hovered == item.$1,
              isRunning:
                  (item.$1 == AppTab.encode && encodeRunning) ||
                  (item.$1 == AppTab.decode && decodeRunning) ||
                  (item.$1 == AppTab.player && playerPlaying),
              hasBadge:
                  item.$1 == AppTab.settings &&
                  (updateStatus == UpdateStatus.available ||
                      updateStatus == UpdateStatus.downloading ||
                      updateStatus == UpdateStatus.readyToInstall),
              palette: widget.activeTab == item.$1
                  ? widget.palette
                  : item.$1.palette,
              onTap: () => ref.read(activeTabProvider.notifier).state = item.$1,
              onHover: (v) => setState(() => _hovered = v ? item.$1 : null),
            ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final AppTab tab;
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isHovered;
  final bool isRunning;
  final bool hasBadge;
  final TabPalette palette;
  final VoidCallback onTap;
  final ValueChanged<bool> onHover;

  const _SidebarItem({
    required this.tab,
    required this.icon,
    required this.label,
    required this.isActive,
    required this.isHovered,
    required this.isRunning,
    required this.palette,
    required this.onTap,
    required this.onHover,
    this.hasBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? palette.primary
        : isHovered
        ? palette.primary.withValues(alpha: 0.7)
        : kTextMuted;

    return Tooltip(
      message: label,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 800),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => onHover(true),
        onExit: (_) => onHover(false),
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: isActive
                  ? palette.primary.withValues(alpha: 0.1)
                  : Colors.transparent,
              border: Border(
                left: BorderSide(
                  color: isActive ? palette.primary : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: isActive
                            ? [BoxShadow(color: palette.glow, blurRadius: 10)]
                            : [],
                      ),
                      child: Icon(icon, color: color, size: 22),
                    ),
                    if (isRunning)
                      Positioned(
                        top: 2,
                        right: 2,
                        child:
                            Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: palette.primary,
                                    boxShadow: [
                                      BoxShadow(
                                        color: palette.glow,
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                )
                                .animate(onPlay: (c) => c.repeat(reverse: true))
                                .fade(begin: 0.3, end: 1.0, duration: 600.ms),
                      ),
                    if (hasBadge)
                      Positioned(
                        top: -1,
                        right: -1,
                        child: Icon(
                          Icons.download_rounded,
                          size: 15,
                          color: palette.primary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: color,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Toast data ──────────────────────────────────────────────────────────────

class _ToastEntry {
  final int id;
  final String message;
  final TabPalette palette;
  final AppTab target;
  final Timer timer;

  const _ToastEntry({
    required this.id,
    required this.message,
    required this.palette,
    required this.target,
    required this.timer,
  });
}

// ── Toast card widget ───────────────────────────────────────────────────────

class _ToastCard extends StatelessWidget {
  final _ToastEntry toast;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _ToastCard({
    required this.toast,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                width: 240,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: kSurfaceColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: toast.palette.primary.withValues(alpha: 0.4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: toast.palette.primary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        color: toast.palette.primary,
                        size: 14,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        toast.message,
                        style: TextStyle(
                          fontSize: 12,
                          color: kTextPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onDismiss,
                      child: Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.close_rounded,
                          color: kTextMuted,
                          size: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        )
        .animate()
        .fadeIn(duration: 180.ms)
        .slideX(begin: 0.25, end: 0, duration: 180.ms);
  }
}

// ── Scanline overlay (Phosphor / CRT themes) ────────────────────────────────

class _ScanlineOverlay extends StatelessWidget {
  const _ScanlineOverlay();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _ScanlinePainter());
  }
}

class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.16);
    const gap = 3.0;
    for (double y = 0; y < size.height; y += gap) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
