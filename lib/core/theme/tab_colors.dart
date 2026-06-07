import 'package:flutter/material.dart';

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

const tabPalettes = {
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
};

extension TabPaletteX on AppTab {
  TabPalette get palette => tabPalettes[this]!;
}
