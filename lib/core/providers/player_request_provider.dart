import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Set to a video path to tell the Player screen to open it.
/// The Player screen clears it after consuming.
final playerOpenRequestProvider = StateProvider<String?>((ref) => null);
