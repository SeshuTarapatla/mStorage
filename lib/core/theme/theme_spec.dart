import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'tab_colors.dart';

/// Identifies one of the bundled visual themes.
/// Persisted by name (see [AppThemeIdX.id] / [appThemeIdFromString]).
enum AppThemeId {
  spectrum,
  monolith,
  aurora,
  manuscript,
  phosphor,
  clay,
  halcyon,
}

/// Broad elevation language a theme uses. Drives glows/borders/shadows in the
/// shell and shared widgets so most components adapt without per-theme code.
enum ElevationStyle { glow, flat, glass, bloom, clay }

extension AppThemeIdX on AppThemeId {
  String get id => name;
}

AppThemeId appThemeIdFromString(String? s) {
  for (final t in AppThemeId.values) {
    if (t.name == s) return t;
  }
  return AppThemeId.spectrum;
}

/// Readable on-colour (black or white) for text/icons placed on a solid [fill],
/// chosen by contrast. Bright fills keep black (so Spectrum is unchanged); dark
/// accent fills (Monolith/Manuscript) flip to white. The crossover sits at the
/// luminance where black text stops being legible (~0.18).
Color onAccentColor(Color fill) {
  final l = fill.computeLuminance();
  return (l + 0.05) / 0.05 >= 1.05 / (l + 0.05) ? Colors.black : Colors.white;
}

/// A complete visual identity: colour tokens, typography, shape, elevation and
/// the per-tab accent map. Switching themes = swapping the active [ThemeSpec].
///
/// Feature logic never references this directly — it reads the getter-backed
/// `k*` constants (app_theme.dart) and `tabPalettes` (tab_colors.dart), both of
/// which resolve through [activeSpec]. That keeps ~1000 call sites untouched.
class ThemeSpec {
  final AppThemeId id;
  final String name;
  final String tagline;
  final bool isDark;

  // Surfaces
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color border;

  // Text tiers
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  // Accent
  final Color brandAccent;
  final Map<AppTab, TabPalette> palettes;
  final TabPalette seriesPalette;

  // Typography (google_fonts family names)
  final String headingFont;
  final String bodyFont;
  final double letterSpacing;

  // Shape
  final double radius;
  final double borderWidth;

  // Elevation / signature flourishes
  final ElevationStyle elevation;
  final bool scanlines;
  final List<Color>? gradientBg;

  const ThemeSpec({
    required this.id,
    required this.name,
    required this.tagline,
    required this.isDark,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.brandAccent,
    required this.palettes,
    required this.seriesPalette,
    required this.headingFont,
    required this.bodyFont,
    this.letterSpacing = 0,
    required this.radius,
    this.borderWidth = 1,
    required this.elevation,
    this.scanlines = false,
    this.gradientBg,
  });

  bool get hasGlow =>
      elevation == ElevationStyle.glow ||
      elevation == ElevationStyle.glass ||
      elevation == ElevationStyle.bloom;

  ThemeData buildThemeData() {
    final base = isDark ? ThemeData.dark() : ThemeData.light();
    final scheme =
        (isDark ? const ColorScheme.dark() : const ColorScheme.light())
            .copyWith(
              surface: surface,
              onSurface: textPrimary,
              primary: brandAccent,
              onPrimary: onAccentColor(brandAccent),
              brightness: isDark ? Brightness.dark : Brightness.light,
            );

    final textTheme = GoogleFonts.getTextTheme(
      bodyFont,
      base.textTheme,
    ).apply(bodyColor: textPrimary, displayColor: textPrimary);

    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: scheme,
      textTheme: textTheme,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: border, width: borderWidth),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: border, width: borderWidth),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: brandAccent, width: borderWidth + 0.5),
        ),
        labelStyle: TextStyle(color: textSecondary),
        hintStyle: TextStyle(color: textMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      dividerColor: border,
      cardColor: surface,
    );
  }
}

// ── Palette helpers ──────────────────────────────────────────────────────────

const _transparent = Color(0x00000000);

/// Builds a TabPalette map where every tab shares one brand accent — used by the
/// single-accent themes that deliberately drop the per-page rainbow.
Map<AppTab, TabPalette> _mono({
  required Color primary,
  required Color secondary,
  required Color glow,
  required Color surface,
}) {
  final p = TabPalette(
    primary: primary,
    secondary: secondary,
    glow: glow,
    surface: surface,
  );
  return {for (final t in AppTab.values) t: p};
}

// ── The themes ────────────────────────────────────────────────────────────────

/// 0 — Spectrum (current ship look): dark, one neon accent per page, glows.
const _spectrum = ThemeSpec(
  id: AppThemeId.spectrum,
  name: 'Spectrum',
  tagline: 'Neon dashboard · one colour per page',
  isDark: true,
  bg: Color(0xFF0A0A0F),
  surface: Color(0xFF13131A),
  surface2: Color(0xFF1C1C26),
  border: Color(0xFF2A2A38),
  textPrimary: Color(0xFFE8E8F0),
  textSecondary: Color(0xFF8888A8),
  textMuted: Color(0xFF4A4A68),
  brandAccent: Color(0xFF3B82F6),
  headingFont: 'Space Grotesk',
  bodyFont: 'Space Grotesk',
  radius: 10,
  elevation: ElevationStyle.glow,
  palettes: {
    AppTab.encode: TabPalette(
      primary: Color(0xFF3B82F6),
      secondary: Color(0xFF818CF8),
      glow: Color(0x663B82F6),
      surface: Color(0xFF0F1629),
    ),
    AppTab.decode: TabPalette(
      primary: Color(0xFF10B981),
      secondary: Color(0xFF34D399),
      glow: Color(0x6610B981),
      surface: Color(0xFF0A1F17),
    ),
    AppTab.player: TabPalette(
      primary: Color(0xFFF43F5E),
      secondary: Color(0xFFFB7185),
      glow: Color(0x66F43F5E),
      surface: Color(0xFF1F0A0F),
    ),
    AppTab.catalog: TabPalette(
      primary: Color(0xFFF59E0B),
      secondary: Color(0xFFFBBF24),
      glow: Color(0x66F59E0B),
      surface: Color(0xFF1F1608),
    ),
    AppTab.settings: TabPalette(
      primary: Color(0xFFA78BFA),
      secondary: Color(0xFFC4B5FD),
      glow: Color(0x66A78BFA),
      surface: Color(0xFF130F1F),
    ),
    AppTab.admin: TabPalette(
      primary: Color(0xFF06B6D4),
      secondary: Color(0xFF22D3EE),
      glow: Color(0x6606B6D4),
      surface: Color(0xFF061921),
    ),
  },
  seriesPalette: TabPalette(
    primary: Color(0xFFEA580C),
    secondary: Color(0xFFF97316),
    glow: Color(0x66EA580C),
    surface: Color(0xFF1A0A02),
  ),
);

/// 1 — Monolith: Swiss/brutalist, light, hard edges, one loud accent.
final _monolith = ThemeSpec(
  id: AppThemeId.monolith,
  name: 'Monolith',
  tagline: 'Swiss brutalist · structure as decoration',
  isDark: false,
  bg: const Color(0xFFFAFAF7),
  surface: const Color(0xFFFFFFFF),
  surface2: const Color(0xFFF0F0EC),
  border: const Color(0xFF0B0B0B),
  textPrimary: const Color(0xFF0B0B0B),
  textSecondary: const Color(0xFF3A3A38),
  textMuted: const Color(0xFF8A8A86),
  brandAccent: const Color(0xFF1F1FFF),
  headingFont: 'Archivo',
  bodyFont: 'Space Grotesk',
  letterSpacing: 0.3,
  radius: 0,
  borderWidth: 1.5,
  elevation: ElevationStyle.flat,
  palettes: _mono(
    primary: const Color(0xFF1F1FFF),
    secondary: const Color(0xFF1F1FFF),
    glow: _transparent,
    surface: const Color(0xFFFAFAF7),
  ),
  seriesPalette: const TabPalette(
    primary: Color(0xFF1F1FFF),
    secondary: Color(0xFF1F1FFF),
    glow: _transparent,
    surface: Color(0xFFFAFAF7),
  ),
);

/// 2 — Aurora: glassmorphism over a living gradient.
final _aurora = ThemeSpec(
  id: AppThemeId.aurora,
  name: 'Aurora',
  tagline: 'Frosted glass · living gradient',
  isDark: true,
  bg: const Color(0xFF1E1B4B),
  surface: const Color(0x29FFFFFF),
  surface2: const Color(0x1FFFFFFF),
  border: const Color(0x24FFFFFF),
  textPrimary: const Color(0xFFF5F5FF),
  textSecondary: const Color(0xFFC4C2E0),
  textMuted: const Color(0xFF8E8CB0),
  brandAccent: const Color(0xFFA78BFA),
  headingFont: 'Inter',
  bodyFont: 'Inter',
  radius: 22,
  elevation: ElevationStyle.glass,
  gradientBg: const [Color(0xFF1E1B4B), Color(0xFF312E81), Color(0xFF0F766E)],
  palettes: _mono(
    primary: const Color(0xFFA78BFA),
    secondary: const Color(0xFF6EE7F9),
    glow: const Color(0x66A78BFA),
    surface: _transparent,
  ),
  // Single-accent theme: series shares the brand accent, not a separate colour.
  seriesPalette: const TabPalette(
    primary: Color(0xFFA78BFA),
    secondary: Color(0xFF6EE7F9),
    glow: Color(0x66A78BFA),
    surface: _transparent,
  ),
);

/// 3 — Manuscript: editorial light, paper + serif display.
final _manuscript = ThemeSpec(
  id: AppThemeId.manuscript,
  name: 'Manuscript',
  tagline: 'Editorial paper · serif display',
  isDark: false,
  bg: const Color(0xFFF6F2E9),
  surface: const Color(0xFFFBF9F3),
  surface2: const Color(0xFFEFE9DA),
  border: const Color(0xFFE2DBCB),
  textPrimary: const Color(0xFF1C1A17),
  textSecondary: const Color(0xFF6B6357),
  textMuted: const Color(0xFFA39A88),
  brandAccent: const Color(0xFF2B4C7E),
  headingFont: 'Fraunces',
  bodyFont: 'Source Sans 3',
  radius: 4,
  borderWidth: 1,
  elevation: ElevationStyle.flat,
  palettes: _mono(
    primary: const Color(0xFF2B4C7E),
    secondary: const Color(0xFFB4552D),
    glow: _transparent,
    surface: const Color(0xFFF6F2E9),
  ),
  // Single-accent theme: series shares the brand accent, not a separate colour.
  seriesPalette: const TabPalette(
    primary: Color(0xFF2B4C7E),
    secondary: Color(0xFFB4552D),
    glow: _transparent,
    surface: Color(0xFFF6F2E9),
  ),
);

/// 4 — Phosphor: retro CRT terminal, monospace, single phosphor hue.
final _phosphor = ThemeSpec(
  id: AppThemeId.phosphor,
  name: 'Phosphor',
  tagline: 'CRT terminal · monospace phosphor',
  isDark: true,
  bg: const Color(0xFF020402),
  surface: const Color(0xFF050A05),
  surface2: const Color(0xFF08120A),
  border: const Color(0xFF1C3D1C),
  textPrimary: const Color(0xFF33FF66),
  textSecondary: const Color(0xFF1FA847),
  textMuted: const Color(0xFF0F5C28),
  brandAccent: const Color(0xFF5BFF8F),
  headingFont: 'JetBrains Mono',
  bodyFont: 'JetBrains Mono',
  letterSpacing: 0.4,
  radius: 0,
  borderWidth: 1,
  elevation: ElevationStyle.bloom,
  scanlines: true,
  palettes: _mono(
    primary: const Color(0xFF5BFF8F),
    secondary: const Color(0xFF33FF66),
    glow: const Color(0x6633FF66),
    surface: const Color(0xFF020402),
  ),
  seriesPalette: const TabPalette(
    primary: Color(0xFF5BFF8F),
    secondary: Color(0xFF33FF66),
    glow: Color(0x6633FF66),
    surface: Color(0xFF020402),
  ),
);

/// 5 — Clay: neumorphic / claymorphic soft UI, candy accent.
final _clay = ThemeSpec(
  id: AppThemeId.clay,
  name: 'Clay',
  tagline: 'Soft neumorphic · tactile',
  isDark: false,
  bg: const Color(0xFFE8EAF1),
  surface: const Color(0xFFEDEFF5),
  surface2: const Color(0xFFF3F5FA),
  border: const Color(0xFFD2D6E2),
  textPrimary: const Color(0xFF3A3D4D),
  textSecondary: const Color(0xFF6E7287),
  textMuted: const Color(0xFFA0A4B8),
  brandAccent: const Color(0xFF9B8CFF),
  headingFont: 'Nunito',
  bodyFont: 'Nunito',
  radius: 22,
  borderWidth: 1,
  elevation: ElevationStyle.clay,
  palettes: _mono(
    primary: const Color(0xFF9B8CFF),
    secondary: const Color(0xFF5BD6A8),
    glow: const Color(0x339B8CFF),
    surface: const Color(0xFFE8EAF1),
  ),
  // Single-accent theme: series shares the brand accent, not a separate colour.
  seriesPalette: const TabPalette(
    primary: Color(0xFF9B8CFF),
    secondary: Color(0xFF5BD6A8),
    glow: Color(0x339B8CFF),
    surface: Color(0xFFE8EAF1),
  ),
);

/// 6 — Halcyon: muted, calm, anti-neon dark. Keeps per-page identity, desaturated.
const _halcyon = ThemeSpec(
  id: AppThemeId.halcyon,
  name: 'Halcyon',
  tagline: 'Muted calm · the quiet pro tool',
  isDark: true,
  bg: Color(0xFF1A1B26),
  surface: Color(0xFF1F2335),
  surface2: Color(0xFF24283B),
  border: Color(0xFF2E3350),
  textPrimary: Color(0xFFC0CAF5),
  textSecondary: Color(0xFF9AA5CE),
  textMuted: Color(0xFF565F89),
  brandAccent: Color(0xFF7AA2F7),
  headingFont: 'Inter',
  bodyFont: 'Inter',
  radius: 8,
  elevation: ElevationStyle.flat,
  palettes: {
    AppTab.encode: TabPalette(
      primary: Color(0xFF7AA2F7),
      secondary: Color(0xFF9AB8FF),
      glow: _transparent,
      surface: Color(0xFF1A1B26),
    ),
    AppTab.decode: TabPalette(
      primary: Color(0xFF9ECE6A),
      secondary: Color(0xFFB9E08C),
      glow: _transparent,
      surface: Color(0xFF1A1B26),
    ),
    AppTab.player: TabPalette(
      primary: Color(0xFFF7768E),
      secondary: Color(0xFFFF9CB0),
      glow: _transparent,
      surface: Color(0xFF1A1B26),
    ),
    AppTab.catalog: TabPalette(
      primary: Color(0xFFE0AF68),
      secondary: Color(0xFFF0C788),
      glow: _transparent,
      surface: Color(0xFF1A1B26),
    ),
    AppTab.settings: TabPalette(
      primary: Color(0xFFBB9AF7),
      secondary: Color(0xFFD0B8FF),
      glow: _transparent,
      surface: Color(0xFF1A1B26),
    ),
    AppTab.admin: TabPalette(
      primary: Color(0xFF7DCFFF),
      secondary: Color(0xFFA3DEFF),
      glow: _transparent,
      surface: Color(0xFF1A1B26),
    ),
  },
  seriesPalette: TabPalette(
    primary: Color(0xFFFF9E64),
    secondary: Color(0xFFFFB888),
    glow: _transparent,
    surface: Color(0xFF1A1B26),
  ),
);

/// All bundled themes, keyed by id. Order here is the order shown in Settings.
final Map<AppThemeId, ThemeSpec> themeSpecs = {
  AppThemeId.spectrum: _spectrum,
  AppThemeId.halcyon: _halcyon,
  AppThemeId.monolith: _monolith,
  AppThemeId.manuscript: _manuscript,
  AppThemeId.aurora: _aurora,
  AppThemeId.clay: _clay,
  AppThemeId.phosphor: _phosphor,
};

// ── Active theme holder ───────────────────────────────────────────────────────
// The getter-backed `k*` constants and `tabPalettes` resolve through this.
// Mutated by [applyThemeGlobals]; the UI then rebuilds (see MStorageApp).

ThemeSpec activeSpec = _spectrum;

void applyThemeGlobals(AppThemeId id) {
  activeSpec = themeSpecs[id] ?? _spectrum;
}
