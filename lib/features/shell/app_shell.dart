import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/services/gh_auth_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tab_colors.dart';
import '../admin/admin_screen.dart';
import '../decode/decode_notifier.dart';
import '../encode/encode_notifier.dart';
import '../encode/encode_screen.dart';
import '../decode/decode_screen.dart';
import '../player/player_screen.dart';
import '../catalog/catalog_screen.dart';
import '../settings/settings_screen.dart';

// Reads startupTab from already-loaded settings (main() loads before runApp).
// ref.read (not watch) so user navigation doesn't get overridden on rebuilds.
final activeTabProvider = StateProvider<AppTab>((ref) {
  final idx = ref.read(settingsProvider).startupTab;
  // Clamp to public tabs only — admin is the last enum value and not a startup option.
  return AppTab.values[idx.clamp(0, AppTab.settings.index)];
});

final ghAuthProvider = FutureProvider<bool>(
    (ref) => GhAuthService().isAuthorized());

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _enterFade;
  late final Animation<Offset> _enterSlide;
  late final Animation<double> _exitFade;

  AppTab? _exitingTab;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..value = 1.0; // start complete so first render is instant

    final curved = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _enterFade  = curved;
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

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _screenFor(AppTab tab) => switch (tab) {
    AppTab.encode   => const EncodeScreen(),
    AppTab.decode   => const DecodeScreen(),
    AppTab.player   => const PlayerScreen(),
    AppTab.catalog  => const CatalogScreen(),
    AppTab.settings => const SettingsScreen(),
    AppTab.admin    => const AdminScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final activeTab = ref.watch(activeTabProvider);
    final palette = activeTab.palette;

    // Trigger animation whenever the active tab changes.
    ref.listen(activeTabProvider, (prev, next) {
      if (prev != null && prev != next) {
        setState(() => _exitingTab = prev);
        _ctrl.forward(from: 0);
      }
    });

    return AnimatedTheme(
      duration: const Duration(milliseconds: 300),
      data: Theme.of(context),
      child: Scaffold(
        backgroundColor: kBgColor,
        body: Column(
          children: [
            _TitleBar(activeTab: activeTab, palette: palette),
            Expanded(
              child: Row(
                children: [
                  _Sidebar(activeTab: activeTab, palette: palette),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      color: palette.surface,
                      child: Stack(
                        fit: StackFit.expand,
                        children: AppTab.values.map((tab) {
                          final isActive  = tab == activeTab;
                          final isExiting = tab == _exitingTab;

                          // Tabs not involved in this transition stay in the
                          // tree (state preserved) but are invisible.
                          if (!isActive && !isExiting) {
                            return IgnorePointer(
                              child: Opacity(
                                opacity: 0,
                                child: _screenFor(tab),
                              ),
                            );
                          }

                          // Entering tab — fades in and slides up.
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

                          // Exiting tab — fades out behind the entering tab.
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
                  ),
                ],
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

  const _TitleBar({required this.activeTab, required this.palette});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
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
                boxShadow: [
                  BoxShadow(color: palette.glow, blurRadius: 8),
                ],
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
              icon: Icons.crop_square_rounded,
              tooltip: 'Maximize',
              onTap: () async {
                if (await windowManager.isMaximized()) {
                  windowManager.unmaximize();
                } else {
                  windowManager.maximize();
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
      onExit: (_) => setState(() { _hovered = false; _pressed = false; }),
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
                  ? const Color(0xFFE81123).withValues(alpha: _pressed ? 1.0 : 0.85)
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

  static const _adminItem =
      (AppTab.admin, Icons.admin_panel_settings_rounded, 'Admin');

  @override
  Widget build(BuildContext context) {
    final encodeRunning = ref.watch(encodeProvider).isRunning;
    final decodeRunning = ref.watch(decodeProvider).isRunning;
    final isAdmin = ref.watch(ghAuthProvider).valueOrNull ?? false;

    final items = isAdmin ? [..._baseItems, _adminItem] : _baseItems;

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
              isRunning: (item.$1 == AppTab.encode && encodeRunning) ||
                  (item.$1 == AppTab.decode && decodeRunning),
              palette: item.$1.palette,
              onTap: () =>
                  ref.read(activeTabProvider.notifier).state = item.$1,
              onHover: (v) =>
                  setState(() => _hovered = v ? item.$1 : null),
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
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: palette.primary,
                          boxShadow: [
                            BoxShadow(color: palette.glow, blurRadius: 4)
                          ],
                        ),
                      )
                          .animate(onPlay: (c) => c.repeat(reverse: true))
                          .fade(begin: 0.3, end: 1.0, duration: 600.ms),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight:
                      isActive ? FontWeight.w600 : FontWeight.normal,
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
