import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Set to a video path to tell the Player screen to open it.
/// The Player screen clears it after consuming.
final playerOpenRequestProvider = StateProvider<String?>((ref) => null);

/// True while the player is in fullscreen mode.
/// AppShell hides the title bar and sidebar while this is true.
final playerFullscreenProvider = StateProvider<bool>((ref) => false);

/// Mirrors _sharedPlayer.state.playing so the sidebar can show a playing dot.
final playerPlayingProvider = StateProvider<bool>((ref) => false);
