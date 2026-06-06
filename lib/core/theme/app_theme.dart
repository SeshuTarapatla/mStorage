import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const kBgColor = Color(0xFF0A0A0F);
const kSurfaceColor = Color(0xFF13131A);
const kSurface2Color = Color(0xFF1C1C26);
const kBorderColor = Color(0xFF2A2A38);
const kTextPrimary = Color(0xFFE8E8F0);
const kTextSecondary = Color(0xFF8888A8);
const kTextMuted = Color(0xFF4A4A68);

ThemeData buildAppTheme() {
  final base = ThemeData.dark();
  return base.copyWith(
    scaffoldBackgroundColor: kBgColor,
    colorScheme: const ColorScheme.dark(
      surface: kSurfaceColor,
      onSurface: kTextPrimary,
      primary: Color(0xFF3B82F6),
    ),
    textTheme: GoogleFonts.spaceGroteskTextTheme(base.textTheme).apply(
      bodyColor: kTextPrimary,
      displayColor: kTextPrimary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSurface2Color,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kBorderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kBorderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
      ),
      labelStyle: const TextStyle(color: kTextSecondary),
      hintStyle: const TextStyle(color: kTextMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    dividerColor: kBorderColor,
    cardColor: kSurfaceColor,
  );
}
