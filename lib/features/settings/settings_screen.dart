import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tab_colors.dart';
import '../shell/widgets/shared_widgets.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _palette = AppTab.settings.palette;
  late TextEditingController _passwordCtrl;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _passwordCtrl =
        TextEditingController(text: ref.read(settingsProvider).password);
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
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
    final accent = _palette.primary;

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
                    for (final tab in [AppTab.encode, AppTab.decode, AppTab.player])
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: _ChipButton(
                          label: tab.name[0].toUpperCase() + tab.name.substring(1),
                          selected: settings.startupTab == tab.index,
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
          ).animate().fadeIn(duration: 300.ms, delay: 240.ms),

          const SizedBox(height: 32),

          // Version footer
          Center(
            child: Column(
              children: [
                Divider(color: kBorderColor, height: 1),
                const SizedBox(height: 16),
                const Text(
                  'mStorage  v1.0.0',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: kTextMuted),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Flutter · Windows',
                  style:
                      TextStyle(fontSize: 11, color: kTextMuted),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 300.ms, delay: 280.ms),
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
  final Color accent;
  final Widget control;

  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.control,
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
