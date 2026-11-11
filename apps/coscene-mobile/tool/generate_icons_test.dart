// Draws every icon and launch image from the logo painter and writes them
// into the iOS and Android projects. Run from apps/coscene-mobile:
//
//   flutter test tool/generate_icons_test.dart
//
// Nothing here is hand-edited artwork: change the logo in
// packages/coscene-render/lib/src/logo.dart and run this again.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:coscene_render/coscene_render.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Encodes pixels as a PNG. Without [alpha] the file has no alpha channel
/// at all, which the App Store requires of app icons.
Uint8List encodePng(Uint8List rgba, int width, int height, {required bool alpha}) {
  final channels = alpha ? 4 : 3;
  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0);
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      raw.add(rgba.sublist(i, i + channels));
    }
  }
  final crcTable = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = c & 1 == 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
    }
    return c;
  });
  List<int> chunk(String type, List<int> data) {
    final body = [...type.codeUnits, ...data];
    var crc = 0xFFFFFFFF;
    for (final b in body) {
      crc = crcTable[(crc ^ b) & 0xFF] ^ (crc >>> 8);
    }
    crc ^= 0xFFFFFFFF;
    final header = ByteData(4)..setUint32(0, data.length);
    final footer = ByteData(4)..setUint32(0, crc);
    return [...header.buffer.asUint8List(), ...body, ...footer.buffer.asUint8List()];
  }

  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, alpha ? 6 : 2);
  return Uint8List.fromList([
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    ...chunk('IHDR', ihdr.buffer.asUint8List()),
    ...chunk('IDAT', zlib.encode(raw.takeBytes())),
    ...chunk('IEND', const []),
  ]);
}

Future<void> write(
  WidgetTester tester,
  String path,
  int width,
  int height,
  void Function(Canvas canvas, Size size) draw, {
  bool alpha = true,
}) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder), Size(width.toDouble(), height.toDouble()));
  final picture = recorder.endRecording();
  await tester.runAsync(() async {
    final image = await picture.toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(encodePng(data!.buffer.asUint8List(), width, height, alpha: alpha));
    image.dispose();
  });
  picture.dispose();
}

/// The full-bleed square icon. The stores and iOS round the corners.
void square(Canvas c, Size s) => Logo.paint(c, Offset.zero & s);

/// The icon with its own rounded corners, for older Android launchers.
void rounded(Canvas c, Size s) {
  c.clipRRect(RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(s.width * 0.225)));
  Logo.paint(c, Offset.zero & s);
}

/// Android adaptive layers: the mark sits in the middle 72 of 108, with
/// the artwork carried on past it so any mask shape stays filled.
void adaptive(Canvas c, Size s, {Color? mono}) {
  final inset = s.width * 18 / 108;
  Logo.paint(c, Rect.fromLTWH(inset, inset, s.width - 2 * inset, s.height - 2 * inset), bleed: 30, mono: mono);
}

/// Eyes and glasses alone, for the launch screens.
void mark(Canvas c, Size s) => Logo.paint(c, Offset.zero & s, background: false);

void main() {
  testWidgets('writes icons and launch images', (tester) async {
    if (!Directory('ios/Runner').existsSync() || !Directory('android/app').existsSync()) {
      fail('Run this from apps/coscene-mobile.');
    }
    const ios = 'ios/Runner/Assets.xcassets';
    await write(tester, '$ios/AppIcon.appiconset/icon-1024.png', 1024, 1024, square, alpha: false);
    for (final (suffix, px) in [('', 168), ('@2x', 336), ('@3x', 504)]) {
      await write(tester, '$ios/LaunchImage.imageset/LaunchImage$suffix.png', px, px, mark);
    }

    const res = 'android/app/src/main/res';
    for (final (density, scale) in [('mdpi', 1.0), ('hdpi', 1.5), ('xhdpi', 2.0), ('xxhdpi', 3.0), ('xxxhdpi', 4.0)]) {
      final legacy = (48 * scale).round(), layer = (108 * scale).round();
      await write(tester, '$res/mipmap-$density/ic_launcher.png', legacy, legacy, rounded);
      await write(tester, '$res/mipmap-$density/ic_launcher_foreground.png', layer, layer, adaptive, alpha: false);
      await write(
        tester,
        '$res/mipmap-$density/ic_launcher_monochrome.png',
        layer,
        layer,
        (c, s) => adaptive(c, s, mono: const Color(0xFFFFFFFF)),
      );
    }
    await write(tester, '$res/drawable-xxhdpi/launch_mark.png', 504, 504, mark);

    // Store listing artwork.
    const store = 'build/store';
    await write(tester, '$store/app-store-icon-1024.png', 1024, 1024, square, alpha: false);
    await write(tester, '$store/play-icon-512.png', 512, 512, square, alpha: false);
    await write(tester, '$store/play-feature-graphic-1024x500.png', 1024, 500, (c, s) {
      Logo.paint(c, const Rect.fromLTWH(262, 0, 500, 500), bleed: 70);
    }, alpha: false);
  });
}
