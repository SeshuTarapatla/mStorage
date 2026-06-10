import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../core/services/catalog_cache_manager.dart';
import '../../core/models/settings_model.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tab_colors.dart';
import '../catalog/catalog_notifier.dart';
import '../catalog/imdb_service.dart';
import '../catalog/widgets/catalog_card.dart';
import '../shell/widgets/shared_widgets.dart';
import '../updater/update_model.dart';
import '../updater/update_notifier.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _palette = AppTab.settings.palette;
  late TextEditingController _passwordCtrl;
  bool _showPassword = false;
  String? _cacheMessage;
  Timer? _cacheMessageTimer;
  String? _appVersion;

  @override
  void initState() {
    super.initState();
    _passwordCtrl =
        TextEditingController(text: ref.read(settingsProvider).password);
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _appVersion = info.version);
    });
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _cacheMessageTimer?.cancel();
    super.dispose();
  }

  void _showChangelog(UpdateInfo info) {
    final accent = _palette.primary;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          "What's new in v${info.version}",
          style: const TextStyle(color: kTextPrimary, fontSize: 16),
        ),
        content: SizedBox(
          width: 480,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: Markdown(
              data: info.releaseNotes.isNotEmpty ? info.releaseNotes : '_No release notes available._',
              shrinkWrap: true,
              padding: const EdgeInsets.only(top: 4),
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(fontSize: 12, color: kTextSecondary, height: 1.6),
                h1: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: accent),
                h2: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: accent),
                h3: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kTextPrimary),
                strong: const TextStyle(fontWeight: FontWeight.w600, color: kTextPrimary),
                em: const TextStyle(fontStyle: FontStyle.italic, color: kTextSecondary),
                code: const TextStyle(fontSize: 11, color: kTextPrimary, fontFamily: 'monospace'),
                codeblockDecoration: BoxDecoration(
                  color: kSurface2Color,
                  borderRadius: BorderRadius.circular(6),
                ),
                listBullet: const TextStyle(fontSize: 12, color: kTextSecondary),
                horizontalRuleDecoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: kBorderColor)),
                ),
              ),
            ),
          ),
        ),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close', style: TextStyle(color: accent)),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateSubtitle(UpdateState updateState, Color accent) {
    final version = 'v${_appVersion ?? '...'}';
    final info = updateState.info;

    switch (updateState.status) {
      case UpdateStatus.checking:
        return Text('$version  ·  Checking for updates…',
            style: const TextStyle(fontSize: 12, color: kTextSecondary));
      case UpdateStatus.upToDate:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$version  ·  Already up to date  ·',
                style: const TextStyle(fontSize: 12, color: kTextSecondary)),
            if (info?.releaseNotes.isNotEmpty == true) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _showChangelog(info!),
                child: Text(
                  "What's new",
                  style: TextStyle(
                    fontSize: 12,
                    color: accent,
                    decoration: TextDecoration.underline,
                    decorationColor: accent,
                  ),
                ),
              ),
            ],
          ],
        );
      case UpdateStatus.available:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Update available  ·',
                style: TextStyle(fontSize: 12, color: accent)),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: info?.releaseNotes.isNotEmpty == true
                  ? () => _showChangelog(info!)
                  : null,
              child: Text(
                "What's new",
                style: TextStyle(
                  fontSize: 12,
                  color: accent,
                  decoration: TextDecoration.underline,
                  decorationColor: accent,
                ),
              ),
            ),
          ],
        );
      case UpdateStatus.downloading:
        return Text('$version  ·  Downloading update…',
            style: const TextStyle(fontSize: 12, color: kTextSecondary));
      case UpdateStatus.readyToInstall:
        return Text('$version  ·  Ready to install',
            style: TextStyle(fontSize: 12, color: accent));
      case UpdateStatus.error:
        return Text('$version  ·  ${updateState.errorMessage ?? 'Check failed'}',
            style: const TextStyle(fontSize: 12, color: kDanger));
      case UpdateStatus.idle:
        return Text('$version  ·  Currently installed',
            style: const TextStyle(fontSize: 12, color: kTextSecondary));
    }
  }

  Widget _buildUpdateControl(UpdateState updateState) {
    final accent = _palette.primary;
    switch (updateState.status) {
      case UpdateStatus.idle:
      case UpdateStatus.upToDate:
        return _ActionButton(
          label: 'Check Now',
          accent: accent,
          onTap: () => ref.read(updateProvider.notifier).checkForUpdate(),
        );
      case UpdateStatus.checking:
        // Same padding/size as _ActionButton so the row never changes height.
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent.withValues(alpha: 0.3)),
          ),
          child: SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 2, color: accent),
          ),
        );
      case UpdateStatus.available:
        final info = updateState.info!;
        return _ActionButton(
          label: 'Download v${info.version}',
          accent: accent,
          onTap: () => ref.read(updateProvider.notifier).downloadUpdate(),
        );
      case UpdateStatus.downloading:
        return SizedBox(
          width: 140,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Downloading ${(updateState.downloadProgress * 100).round()}%',
                    style: TextStyle(fontSize: 11, color: accent),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: updateState.downloadProgress,
                  backgroundColor: accent.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation(accent),
                  minHeight: 3,
                ),
              ),
            ],
          ),
        );
      case UpdateStatus.readyToInstall:
        return _ActionButton(
          label: 'Install Now',
          accent: accent,
          onTap: () => ref.read(updateProvider.notifier).launchInstaller(),
        );
      case UpdateStatus.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              updateState.errorMessage ?? 'Unknown error',
              style: const TextStyle(fontSize: 11, color: kDanger),
              textAlign: TextAlign.end,
            ),
            const SizedBox(height: 4),
            _ActionButton(
              label: 'Retry',
              accent: accent,
              onTap: () => ref.read(updateProvider.notifier).checkForUpdate(),
            ),
          ],
        );
    }
  }

  Future<void> _confirmClearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear all caches?',
            style: TextStyle(color: kTextPrimary, fontSize: 16)),
        content: const Text(
          'IMDB metadata, image URLs, catalog CSV, and cached poster images will be deleted. App settings are not affected.',
          style: TextStyle(color: kTextSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: _palette.primary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: _palette.primary),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await Future.wait([
      ImdbService().clearCache(),
      CatalogCacheManager.instance.emptyCache(),
      ref.read(catalogProvider.notifier).clearAllCsvCaches(),
    ]);
    clearSlideCropCache();
    if (!mounted) return;
    _cacheMessageTimer?.cancel();
    setState(() => _cacheMessage = 'All caches cleared successfully.');
    _cacheMessageTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _cacheMessage = null);
    });
  }

  static (IconData, String) _tabInfo(AppTab tab) => switch (tab) {
        AppTab.encode   => (Icons.upload_rounded,        'Encode'),
        AppTab.decode   => (Icons.download_rounded,      'Decode'),
        AppTab.player   => (Icons.play_circle_rounded,   'Player'),
        AppTab.catalog  => (Icons.photo_library_rounded, 'Catalog'),
        AppTab.settings => (Icons.settings_rounded,      'Settings'),
        AppTab.admin    => (Icons.admin_panel_settings_rounded, 'Admin'),
      };

  static int _effectiveStartupTab(AppSettings settings, String? sheetUrl) {
    if (settings.startupTab != 0) return settings.startupTab;
    return sheetUrl != null ? AppTab.catalog.index : AppTab.encode.index;
  }

  static List<int> _effectiveOrder(AppSettings settings, String? sheetUrl) {
    if (settings.tabOrder != null) return settings.tabOrder!;
    const defaultOrder = [
      AppTab.encode,
      AppTab.decode,
      AppTab.player,
      AppTab.catalog,
      AppTab.settings,
    ];
    if (settings.startupTab != 0) {
      final startupIdx = settings.startupTab.clamp(0, AppTab.settings.index);
      return [
        startupIdx,
        ...defaultOrder.map((t) => t.index).where((i) => i != startupIdx),
      ];
    }
    if (sheetUrl != null) {
      return [
        AppTab.catalog.index,
        AppTab.player.index,
        AppTab.encode.index,
        AppTab.decode.index,
        AppTab.settings.index,
      ];
    }
    return defaultOrder.map((t) => t.index).toList();
  }

  Widget _buildLayoutSection(AppSettings settings, Color accent, String? sheetUrl) {
    final order = _effectiveOrder(settings, sheetUrl);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.reorder_rounded, color: accent, size: 20),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Page Order',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: kTextPrimary)),
                    const SizedBox(height: 2),
                    const Text('Drag to reorder sidebar pages.',
                        style: TextStyle(fontSize: 12, color: kTextSecondary)),
                  ],
                ),
              ),
              if (settings.tabOrder != null)
                _ActionButton(
                  label: 'Reset',
                  accent: accent,
                  onTap: () async {
                    final n = ref.read(settingsProvider.notifier);
                    await n.resetTabOrder();
                    await n.setStartupTab(0);
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: kSurface2Color,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kBorderColor),
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: 44.0 * order.length,
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: order.length,
                onReorder: (oldIndex, newIndex) {
                  if (newIndex > oldIndex) newIndex--;
                  final newOrder = [...order];
                  newOrder.insert(newIndex, newOrder.removeAt(oldIndex));
                  ref.read(settingsProvider.notifier).setTabOrder(newOrder);
                },
                itemBuilder: (context, index) {
                  final tab = AppTab.values[order[index]];
                  final (icon, label) = _tabInfo(tab);
                  return Container(
                    key: ValueKey(order[index]),
                    height: 44,
                    decoration: index < order.length - 1
                        ? const BoxDecoration(
                            border: Border(
                                bottom: BorderSide(color: kBorderColor)))
                        : null,
                    child: Row(
                      children: [
                        ReorderableDragStartListener(
                          index: index,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            child: Icon(Icons.drag_handle_rounded,
                                color: kTextMuted, size: 18),
                          ),
                        ),
                        Icon(icon, color: accent, size: 16),
                        const SizedBox(width: 10),
                        Text(label,
                            style: const TextStyle(
                                fontSize: 13, color: kTextPrimary)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reset all settings?',
            style: TextStyle(color: kTextPrimary, fontSize: 16)),
        content: const Text(
          'Password, output directories, encode options and Syncplay config will all be cleared.',
          style: TextStyle(color: kTextSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: _palette.primary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: kDanger),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(settingsProvider.notifier).resetAll();
      _passwordCtrl.text = '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final sheetUrl = ref.watch(sheetUrlProvider);
    final accent = _palette.primary;
    final updateState = ref.watch(updateProvider);
    final updatePending = updateState.status == UpdateStatus.available ||
        updateState.status == UpdateStatus.downloading ||
        updateState.status == UpdateStatus.readyToInstall;

    final updatesGroup = _SettingsGroup(
      label: 'Updates',
      accent: accent,
      children: [
        _SettingRow(
          icon: Icons.system_update_rounded,
          title: 'Check for Updates',
          subtitle: '',
          subtitleWidget: _buildUpdateSubtitle(updateState, accent),
          accent: accent,
          control: _buildUpdateControl(updateState),
        ),
      ],
    ).animate().fadeIn(duration: 300.ms, delay: 40.ms);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            icon: Icons.settings_rounded,
            title: 'Settings',
            subtitle: 'Archive password and output preferences',
            color: accent,
          ),
          const SizedBox(height: 32),

          if (updatePending) ...[
            updatesGroup,
            const SizedBox(height: 20),
          ],

          // ── General ──────────────────────────────────────────────────────
          _SettingsGroup(
            label: 'General',
            accent: accent,
            children: [
              _SettingRow(
                icon: Icons.home_rounded,
                title: 'Startup Page',
                subtitle: 'Which tab opens when the app launches.',
                accent: accent,
                control: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final tab in [AppTab.encode, AppTab.decode, AppTab.player, AppTab.catalog])
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: _ChipButton(
                          label: tab.name[0].toUpperCase() + tab.name.substring(1),
                          selected: _effectiveStartupTab(settings, sheetUrl) == tab.index,
                          accent: accent,
                          onTap: () => ref
                              .read(settingsProvider.notifier)
                              .setStartupTab(tab.index),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ).animate().fadeIn(duration: 300.ms, delay: 40.ms),

          const SizedBox(height: 20),

          // ── Layout ───────────────────────────────────────────────────────
          _SettingsGroup(
            label: 'Layout',
            accent: accent,
            children: [_buildLayoutSection(settings, accent, sheetUrl)],
          ).animate().fadeIn(duration: 300.ms, delay: 60.ms),

          const SizedBox(height: 20),

          // ── Archive Password ─────────────────────────────────────────────
          _SettingsGroup(
            label: 'Archive Password',
            accent: accent,
            children: [
              _SettingRow(
                icon: Icons.lock_outline_rounded,
                title: 'Password',
                subtitle:
                    'Applied to every encode/decode. Leave blank for no encryption.',
                accent: accent,
                control: SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _passwordCtrl,
                    obscureText: !_showPassword,
                    style:
                        const TextStyle(fontSize: 13, color: kTextPrimary),
                    onChanged: (v) =>
                        ref.read(settingsProvider.notifier).setPassword(v),
                    decoration: InputDecoration(
                      hintText: 'No password',
                      hintStyle: const TextStyle(
                          fontSize: 13, color: kTextMuted),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: kBorderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: accent, width: 1.5),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _showPassword
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          size: 16,
                          color: kTextMuted,
                        ),
                        onPressed: () =>
                            setState(() => _showPassword = !_showPassword),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ).animate().fadeIn(duration: 300.ms, delay: 60.ms),

          const SizedBox(height: 20),

          // ── Output Directories ───────────────────────────────────────────
          _SettingsGroup(
            label: 'Output Directories',
            accent: accent,
            children: [
              _DirSettingRow(
                icon: Icons.upload_rounded,
                title: 'Encode Output',
                subtitle: 'Where encoded mask MP4 files are saved.',
                accent: accent,
                dir: settings.encodeOutputDirectory,
                onPick: () async {
                  final dir = await FilePicker.platform.getDirectoryPath();
                  if (dir != null) {
                    ref
                        .read(settingsProvider.notifier)
                        .setEncodeOutputDirectory(dir);
                  }
                },
                onClear: settings.encodeOutputDirectory.isEmpty
                    ? null
                    : () => ref
                        .read(settingsProvider.notifier)
                        .setEncodeOutputDirectory(''),
                placeholder: 'Default: Videos\\mStorage\\Encoded',
              ),
              _DirSettingRow(
                icon: Icons.download_rounded,
                title: 'Decode Output',
                subtitle: 'Where extracted files from decoded videos are saved.',
                accent: accent,
                dir: settings.decodeOutputDirectory,
                onPick: () async {
                  final dir = await FilePicker.platform.getDirectoryPath();
                  if (dir != null) {
                    ref
                        .read(settingsProvider.notifier)
                        .setDecodeOutputDirectory(dir);
                  }
                },
                onClear: settings.decodeOutputDirectory.isEmpty
                    ? null
                    : () => ref
                        .read(settingsProvider.notifier)
                        .setDecodeOutputDirectory(''),
                placeholder: 'Default: Videos\\mStorage\\Decoded',
              ),
              _DirSettingRow(
                icon: Icons.cloud_download_rounded,
                title: 'Catalog Downloads',
                subtitle: 'Where videos downloaded from the Catalog are saved.',
                accent: accent,
                dir: settings.catalogDownloadDirectory,
                onPick: () async {
                  final dir = await FilePicker.platform.getDirectoryPath();
                  if (dir != null) {
                    ref
                        .read(settingsProvider.notifier)
                        .setCatalogDownloadDirectory(dir);
                  }
                },
                onClear: settings.catalogDownloadDirectory.isEmpty
                    ? null
                    : () => ref
                        .read(settingsProvider.notifier)
                        .setCatalogDownloadDirectory(''),
                placeholder: 'Default: Videos\\mStorage\\Downloaded',
              ),
            ],
          ).animate().fadeIn(duration: 300.ms, delay: 120.ms),

          const SizedBox(height: 20),

          // ── Encode Options ───────────────────────────────────────────────
          _SettingsGroup(
            label: 'Encode Options',
            accent: accent,
            children: [
              _SettingRow(
                icon: Icons.aspect_ratio_rounded,
                title: 'Preserve Aspect Ratio',
                subtitle:
                    'Letterbox/pillarbox to canvas size instead of stretching. Canvas is 1920×1080 for landscape posters, 1080×1920 for portrait.',
                accent: accent,
                control: Switch(
                  value: settings.preserveAspectRatio,
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .setPreserveAspectRatio(v),
                  activeThumbColor: accent,
                  activeTrackColor: accent.withValues(alpha: 0.3),
                  inactiveThumbColor: kTextMuted,
                  inactiveTrackColor: kSurface2Color,
                ),
              ),
              _SettingRow(
                icon: Icons.timer_outlined,
                title: 'Mask Duration',
                subtitle: 'Length of the mask video in seconds (default 5).',
                accent: accent,
                control: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final s in [3, 5, 10, 15])
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: _ChipButton(
                          label: '${s}s',
                          selected: settings.maskDurationSeconds == s,
                          accent: accent,
                          onTap: () => ref
                              .read(settingsProvider.notifier)
                              .setMaskDuration(s),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ).animate().fadeIn(duration: 300.ms, delay: 180.ms),

          const SizedBox(height: 20),

          if (!updatePending) ...[
            // ── Updates ────────────────────────────────────────────────────
            updatesGroup,
            const SizedBox(height: 20),
          ],

          // ── Cache ─────────────────────────────────────────────────────────
          _SettingsGroup(
            label: 'Cache',
            accent: accent,
            children: [
              _SettingRow(
                icon: Icons.cleaning_services_rounded,
                title: 'Clear Cache',
                subtitle:
                    'Remove cached IMDB data, image URLs, catalog CSV, and poster images.',
                accent: accent,
                control: _ActionButton(
                  label: 'Clear Cache',
                  accent: accent,
                  onTap: _confirmClearCache,
                ),
              ),
            ],
          ).animate().fadeIn(duration: 300.ms, delay: 240.ms),

          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: _cacheMessage == null
                ? const SizedBox.shrink()
                : Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: accent.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_outline_rounded, size: 15, color: accent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _cacheMessage!,
                            style: TextStyle(fontSize: 12, color: accent),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            _cacheMessageTimer?.cancel();
                            setState(() => _cacheMessage = null);
                          },
                          child: Icon(Icons.close_rounded, size: 14, color: accent),
                        ),
                      ],
                    ),
                  ),
          ),

          const SizedBox(height: 20),

          // ── Danger Zone ──────────────────────────────────────────────────
          _SettingsGroup(
            label: 'Danger Zone',
            accent: kDanger,
            children: [
              _SettingRow(
                icon: Icons.restart_alt_rounded,
                title: 'Reset All Settings',
                subtitle:
                    'Clear password, output directories, and Syncplay config.',
                accent: kDanger,
                control: _DangerButton(
                  label: 'Reset',
                  onTap: _confirmReset,
                ),
              ),
            ],
          ).animate().fadeIn(duration: 300.ms, delay: 260.ms),

          const SizedBox(height: 32),

          // Version footer
          Center(
            child: Column(
              children: [
                Divider(color: kBorderColor, height: 1),
                const SizedBox(height: 16),
                Text(
                  'mStorage  v${_appVersion ?? '...'}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: kTextMuted),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Seshu Tarapatla  ·  Flutter · Windows',
                  style: TextStyle(fontSize: 11, color: kTextMuted),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 300.ms, delay: 300.ms),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

const kDanger = Color(0xFFEF4444);

class _SettingsGroup extends StatelessWidget {
  final String label;
  final Color accent;
  final List<Widget> children;

  const _SettingsGroup({
    required this.label,
    required this.accent,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: accent,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: kSurfaceColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kBorderColor),
          ),
          child: Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                if (i > 0) Divider(height: 1, color: kBorderColor),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _SettingRow extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? subtitleWidget;
  final Color accent;
  final Widget control;

  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.control,
    this.subtitleWidget,
  });

  @override
  State<_SettingRow> createState() => _SettingRowState();
}

class _SettingRowState extends State<_SettingRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: _hovered
            ? widget.accent.withValues(alpha: 0.04)
            : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(widget.icon, color: widget.accent, size: 20),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: kTextPrimary)),
                    const SizedBox(height: 2),
                    widget.subtitleWidget ??
                        Text(widget.subtitle,
                            style: const TextStyle(
                                fontSize: 12, color: kTextSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              widget.control,
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _DirSettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final String dir;
  final VoidCallback onPick;
  final VoidCallback? onClear;
  final String placeholder;

  const _DirSettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.dir,
    required this.onPick,
    required this.onClear,
    required this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: kTextPrimary)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12, color: kTextSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OutDirRow(
            dir: dir,
            accentColor: accent,
            onPick: onPick,
            onClear: onClear,
            placeholder: placeholder,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ChipButton extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _ChipButton({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.15) : kSurface2Color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? accent : kBorderColor,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? accent : kTextSecondary,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _DangerButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _DangerButton({required this.label, required this.onTap});

  @override
  State<_DangerButton> createState() => _DangerButtonState();
}

class _DangerButtonState extends State<_DangerButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _hovered
                ? kDanger.withValues(alpha: 0.15)
                : kDanger.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _hovered
                  ? kDanger.withValues(alpha: 0.6)
                  : kDanger.withValues(alpha: 0.3),
            ),
          ),
          child: Text(
            widget.label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: kDanger,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ActionButton extends StatefulWidget {
  final String label;
  final Color accent;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.accent,
    required this.onTap,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.accent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _hovered
                ? c.withValues(alpha: 0.15)
                : c.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _hovered
                  ? c.withValues(alpha: 0.6)
                  : c.withValues(alpha: 0.3),
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c,
            ),
          ),
        ),
      ),
    );
  }
}
