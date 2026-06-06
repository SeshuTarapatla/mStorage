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
    final settings = ref.read(settingsProvider);
    _passwordCtrl = TextEditingController(text: settings.password);
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
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

            // ── Archive Password ──────────────────────────────────────────
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
                  control: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 220,
                        child: TextField(
                          controller: _passwordCtrl,
                          obscureText: !_showPassword,
                          style: const TextStyle(
                              fontSize: 14, color: kTextPrimary),
                          onChanged: (v) => ref
                              .read(settingsProvider.notifier)
                              .setPassword(v),
                          decoration: InputDecoration(
                            hintText: 'No password',
                            isDense: true,
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  BorderSide(color: accent, width: 1.5),
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _showPassword
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                                size: 18,
                                color: kTextMuted,
                              ),
                              onPressed: () => setState(
                                  () => _showPassword = !_showPassword),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ).animate().fadeIn(duration: 300.ms, delay: 60.ms),

            const SizedBox(height: 20),

            // ── Output ────────────────────────────────────────────────────
            _SettingsGroup(
              label: 'Output',
              accent: accent,
              children: [
                _DirSettingRow(
                  icon: Icons.upload_rounded,
                  title: 'Encode Output Directory',
                  subtitle: 'Defaults to <video folder>/output/',
                  accent: accent,
                  dir: settings.encodeOutputDirectory,
                  onPick: () async {
                    final dir =
                        await FilePicker.platform.getDirectoryPath();
                    if (dir != null) {
                      ref
                          .read(settingsProvider.notifier)
                          .setEncodeOutputDirectory(dir);
                    }
                  },
                  onClear: () => ref
                      .read(settingsProvider.notifier)
                      .setEncodeOutputDirectory(''),
                ),
                _DirSettingRow(
                  icon: Icons.download_rounded,
                  title: 'Decode Output Directory',
                  subtitle: 'Defaults to same folder as video',
                  accent: accent,
                  dir: settings.decodeOutputDirectory,
                  onPick: () async {
                    final dir =
                        await FilePicker.platform.getDirectoryPath();
                    if (dir != null) {
                      ref
                          .read(settingsProvider.notifier)
                          .setDecodeOutputDirectory(dir);
                    }
                  },
                  onClear: () => ref
                      .read(settingsProvider.notifier)
                      .setDecodeOutputDirectory(''),
                ),
              ],
            ).animate().fadeIn(duration: 300.ms, delay: 120.ms),

            const SizedBox(height: 20),

            // ── Encode Options ─────────────────────────────────────────────
            _SettingsGroup(
              label: 'Encode Options',
              accent: accent,
              children: [
                _SettingRow(
                  icon: Icons.aspect_ratio_rounded,
                  title: 'Preserve Aspect Ratio',
                  subtitle:
                      'Pad poster to 1920×1080 with black bars instead of stretching.',
                  accent: accent,
                  control: Switch(
                    value: settings.preserveAspectRatio,
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .setPreserveAspectRatio(v),
                    activeThumbColor: accent,
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

            const SizedBox(height: 32),

            // Version note
            const Center(
              child: Text(
                'mStorage v1.0.0  ·  Flutter Windows',
                style: TextStyle(fontSize: 11, color: kTextMuted),
              ),
            ),
          ],
        ),
    );
  }
}

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

class _SettingRow extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
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
          const SizedBox(width: 16),
          control,
        ],
      ),
    );
  }
}

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
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
            fontWeight:
                selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? accent : kTextSecondary,
          ),
        ),
      ),
    );
  }
}

class _DirSettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final String dir;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _DirSettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.dir,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingRow(
          icon: icon,
          title: title,
          subtitle: subtitle,
          accent: accent,
          control: SmallButton(
            label: dir.isEmpty ? 'Set folder' : 'Change',
            icon: Icons.folder_open_rounded,
            color: accent,
            onTap: onPick,
          ),
        ),
        if (dir.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Icon(Icons.subdirectory_arrow_right_rounded,
                    size: 14, color: kTextMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    dir,
                    style: const TextStyle(
                        fontSize: 12, color: kTextSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.clear_rounded,
                      size: 14, color: kTextMuted),
                  onPressed: onClear,
                  tooltip: 'Clear',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
