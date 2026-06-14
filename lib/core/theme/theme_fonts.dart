import 'package:google_fonts/google_fonts.dart';

/// Eagerly loads all font families used across the 7 bundled themes so that
/// theme switching never triggers an async font-load + relayout.  Call once
/// (non-blocking) after settings are initialised in main().
Future<void> preloadThemeFonts() async {
  // Touch one style per family — enough to trigger the cache fetch.
  GoogleFonts.spaceGrotesk();   // Spectrum + Halcyon body fallback
  GoogleFonts.archivo();        // Monolith headings
  GoogleFonts.inter();          // Aurora + Halcyon
  GoogleFonts.fraunces();       // Manuscript headings
  GoogleFonts.sourceSans3();    // Manuscript body
  GoogleFonts.jetBrainsMono();  // Phosphor
  GoogleFonts.nunito();         // Clay
  await GoogleFonts.pendingFonts();
}
