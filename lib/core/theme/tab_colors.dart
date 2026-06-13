import 'package:flutter/material.dart';
import 'theme_spec.dart';

enum AppTab { encode, decode, player, catalog, settings, admin }

class TabPalette {
  final Color primary;
  final Color secondary;
  final Color glow;
  final Color surface;

  const TabPalette({
    required this.primary,
    required this.secondary,
    required this.glow,
    required this.surface,
  });
}

/// Per-tab accent map for the active theme. A single-accent theme returns the
/// same palette for every tab; Spectrum/Halcyon return distinct ones.
Map<AppTab, TabPalette> get tabPalettes => activeSpec.palettes;

extension TabPaletteX on AppTab {
  TabPalette get palette =>
      tabPalettes[this] ?? activeSpec.palettes.values.first;
}

TabPalette get kSeriesPalette => activeSpec.seriesPalette;
