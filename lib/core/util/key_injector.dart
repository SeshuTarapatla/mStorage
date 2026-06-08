import 'dart:ffi';
import 'dart:io' show Platform;
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Injects real, OS-level keystrokes into the foreground window.
///
/// Needed for Google Photos' in-page "Download" button: inside the embedded
/// WebView2 it produces no usable download event, but the page's own Shift+D
/// shortcut works — and only a *trusted* (real) key event triggers it. A
/// synthetic JS KeyboardEvent has isTrusted=false and is ignored. SendInput
/// feeds the genuine Windows input pipeline, so the page sees a real keypress.
class KeyInjector {
  static const int _inputKeyboard = 1;
  static const int _keyeventfKeyup = 0x0002;
  static const int _vkShift = 0x10;
  static const int _vkD = 0x44;

  /// Sends a real Shift+D to whatever currently has keyboard focus.
  static void sendShiftD() {
    if (!Platform.isWindows) return;

    final inputs = calloc<INPUT>(4);
    try {
      // Shift down
      inputs[0].type = _inputKeyboard;
      inputs[0].ki.wVk = _vkShift;
      // D down
      inputs[1].type = _inputKeyboard;
      inputs[1].ki.wVk = _vkD;
      // D up
      inputs[2].type = _inputKeyboard;
      inputs[2].ki.wVk = _vkD;
      inputs[2].ki.dwFlags = _keyeventfKeyup;
      // Shift up
      inputs[3].type = _inputKeyboard;
      inputs[3].ki.wVk = _vkShift;
      inputs[3].ki.dwFlags = _keyeventfKeyup;

      SendInput(4, inputs, sizeOf<INPUT>());
    } finally {
      calloc.free(inputs);
    }
  }
}
