import 'package:flutter/material.dart';
import 'theme_spec.dart';

// Re-exported so existing `import app_theme.dart` call sites can use it.
export 'theme_spec.dart' show onAccentColor;

// Theme tokens. These are GETTERS (not const) so the whole app re-skins at
// runtime when [applyThemeGlobals] swaps [activeSpec] and the tree rebuilds.
// Call sites are unchanged (`kBgColor`, `kTextPrimary`, …); the only cost is
// that they can no longer appear inside `const` expressions.
Color get kBgColor => activeSpec.bg;
Color get kSurfaceColor => activeSpec.surface;
Color get kSurface2Color => activeSpec.surface2;
Color get kBorderColor => activeSpec.border;
Color get kTextPrimary => activeSpec.textPrimary;
Color get kTextSecondary => activeSpec.textSecondary;
Color get kTextMuted => activeSpec.textMuted;

/// Base corner radius for the active theme (0 for Monolith/Phosphor, large for
/// Aurora/Clay). Use for cards/buttons/inputs so shape adapts per theme.
double get kRadius => activeSpec.radius;

ThemeData buildAppTheme() => activeSpec.buildThemeData();
