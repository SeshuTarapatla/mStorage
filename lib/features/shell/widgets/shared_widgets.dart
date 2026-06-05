import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const SectionHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 16)
            ],
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: kTextPrimary)),
            Text(subtitle,
                style:
                    const TextStyle(fontSize: 13, color: kTextSecondary)),
          ],
        ),
      ],
    );
  }
}

class SmallButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const SmallButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: color),
      label: Text(label, style: TextStyle(color: color, fontSize: 13)),
      style: TextButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.1),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  final String message;
  const ErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF2A0A0A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF7F1D1D)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Color(0xFFF87171), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFFFCA5A5))),
          ),
        ],
      ),
    );
  }
}

class OutDirRow extends StatelessWidget {
  final String dir;
  final Color accentColor;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  const OutDirRow({
    super.key,
    required this.dir,
    required this.accentColor,
    required this.onPick,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final isCustom = onClear != null;  // user-picked dir, not auto-computed
    final hasContent = dir.isNotEmpty;
    return Row(
      children: [
        Expanded(
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: kSurface2Color,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isCustom
                    ? accentColor.withValues(alpha: 0.45)
                    : kBorderColor,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.folder_outlined,
                    color: isCustom ? accentColor : kTextMuted, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    hasContent ? dir : 'Default: <video folder>/output/',
                    style: TextStyle(
                      fontSize: 13,
                      color: hasContent ? kTextPrimary : kTextMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isCustom)
                  GestureDetector(
                    onTap: onClear,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.close_rounded,
                          size: 15, color: kTextMuted),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        SmallButton(
          label: 'Browse',
          icon: Icons.folder_open_rounded,
          color: accentColor,
          onTap: onPick,
        ),
      ],
    );
  }
}
