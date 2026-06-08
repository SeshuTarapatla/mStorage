import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Set to a file path to tell the Decode screen to load it.
/// The Decode screen clears it after consuming.
final decodeOpenRequestProvider = StateProvider<String?>((ref) => null);
