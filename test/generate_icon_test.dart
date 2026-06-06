// Generates the mStorage app icon and writes:
//   windows/runner/resources/app_icon.ico  — used by the Windows runner
//   assets/icons/app_icon.png              — used by the MSIX installer logo
//
// Run once before building:
//   flutter test test/generate_icon_test.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

// mdi:movie-open-play  (viewBox 0 0 24 24)
const _svgPath =
    'M14.75 7.46L12 3.93L13.97 3.54L16.71 7.07L14.75 7.46'
    'M21.62 6.1L20.84 2.18L16.91 2.96L19.65 6.5L21.62 6.1'
    'M4.16 5.5L3.18 5.69C2.1 5.91 1.4 6.96 1.61 8.04L2 10L6.9 9.03L4.16 5.5'
    'M11.81 8.05L9.07 4.5L7.1 4.91L9.85 8.44L11.81 8.05'
    'M2 10V20C2 21.11 2.9 22 4 22H13.81C13.3 21.12 13 20.1 13 19'
    'C13 15.69 15.69 13 19 13C20.1 13 21.12 13.3 22 13.81V10H2'
    'M17 22L22 19L17 16V22Z';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generate app icon', () async {
    const sizes = [16, 32, 48, 256];
    final pngs = <Uint8List>[];

    for (final size in sizes) {
      pngs.add(await _renderIcon(size));
    }

    // Write ICO (used by windows runner and taskbar)
    await File('windows/runner/resources/app_icon.ico')
        .writeAsBytes(_buildIco(pngs, sizes));

    // Write 256px PNG (used by msix installer as logo)
    await File('assets/icons/app_icon.png').writeAsBytes(pngs.last);

    // ignore: avoid_print
    print('Icon written to windows/runner/resources/app_icon.ico and assets/icons/app_icon.png');
  }, timeout: const Timeout(Duration(seconds: 60)));
}

// ---------------------------------------------------------------------------

Future<Uint8List> _renderIcon(int size) async {
  final s = size.toDouble();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, s, s));

  // Rounded-rectangle background — encode surface (#0F1629)
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(0, 0, s, s),
      ui.Radius.circular(s * 0.18),
    ),
    ui.Paint()..color = const ui.Color(0xFF0F1629),
  );

  // Icon centred with ~12 % padding on each side
  final padding = s * 0.12;
  final scale = (s - padding * 2) / 24.0;

  canvas.save();
  canvas.translate(padding, padding);
  canvas.drawPath(
    _parseSvgPath(_svgPath, scale),
    ui.Paint()
      ..color = const ui.Color(0xFF3B82F6) // encode accent blue
      ..style = ui.PaintingStyle.fill,
  );
  canvas.restore();

  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

// ---------------------------------------------------------------------------
// Minimal SVG path parser — handles absolute M L C H V Z only (sufficient for MDI paths).

ui.Path _parseSvgPath(String d, double scale) {
  final path = ui.Path();

  // Tokenise: command letters | numbers (including decimals)
  final tokens =
      RegExp(r'[MLCHVZmlchvz]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?')
          .allMatches(d)
          .map((m) => m.group(0)!)
          .toList();

  int i = 0;
  String cmd = 'M';
  double cx = 0, cy = 0;

  double takeNum() => double.parse(tokens[i++]) * scale;

  while (i < tokens.length) {
    final t = tokens[i];
    if (RegExp(r'[A-Za-z]').hasMatch(t)) {
      cmd = t;
      i++;
      if (cmd == 'Z' || cmd == 'z') path.close();
      continue;
    }

    switch (cmd) {
      case 'M':
        cx = takeNum(); cy = takeNum();
        path.moveTo(cx, cy);
        cmd = 'L'; // implicit L after M
      case 'L':
        cx = takeNum(); cy = takeNum();
        path.lineTo(cx, cy);
      case 'C':
        final x1 = takeNum(), y1 = takeNum();
        final x2 = takeNum(), y2 = takeNum();
        cx = takeNum(); cy = takeNum();
        path.cubicTo(x1, y1, x2, y2, cx, cy);
      case 'H':
        cx = takeNum();
        path.lineTo(cx, cy);
      case 'V':
        cy = takeNum();
        path.lineTo(cx, cy);
    }
  }

  return path;
}

// ---------------------------------------------------------------------------
// Build a Windows ICO containing PNG frames (Vista+ "PNG ICO" format).

Uint8List _buildIco(List<Uint8List> pngs, List<int> sizes) {
  final count = pngs.length;
  int dataOffset = 6 + count * 16; // header + directory

  final out = BytesBuilder();

  // ICONDIR header
  out.addByte(0); out.addByte(0);           // reserved
  out.addByte(1); out.addByte(0);           // type: 1 = ICO
  out.addByte(count & 0xFF); out.addByte((count >> 8) & 0xFF);

  // ICONDIRENTRY × count
  for (int k = 0; k < count; k++) {
    final sz = sizes[k];
    out.addByte(sz == 256 ? 0 : sz); // width  (0 means 256)
    out.addByte(sz == 256 ? 0 : sz); // height (0 means 256)
    out.addByte(0); out.addByte(0);  // colorCount, reserved
    out.addByte(1); out.addByte(0);  // planes
    out.addByte(32); out.addByte(0); // bitCount (32-bit RGBA)
    _le32(out, pngs[k].length);
    _le32(out, dataOffset);
    dataOffset += pngs[k].length;
  }

  for (final png in pngs) {
    out.add(png);
  }

  return out.toBytes();
}

void _le32(BytesBuilder b, int v) {
  b.addByte(v & 0xFF);
  b.addByte((v >> 8) & 0xFF);
  b.addByte((v >> 16) & 0xFF);
  b.addByte((v >> 24) & 0xFF);
}
