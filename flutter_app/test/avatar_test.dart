import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Test image resize via dart:ui', () async {
    // 1x1 transparent PNG
    final rawPng = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');
    final codec = await ui.instantiateImageCodec(rawPng, targetWidth: 128, targetHeight: 128);
    final frameInfo = await codec.getNextFrame();
    final image = frameInfo.image;
    expect(image.width, 128);
    expect(image.height, 128);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    expect(byteData, isNotNull);
    final resizedBase64 = 'data:image/png;base64,${base64Encode(byteData!.buffer.asUint8List())}';
    expect(resizedBase64.startsWith('data:image/png;base64,'), true);
  });

  test('Test base64 sanitization with newlines and spaces', () {
    const raw = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
    // Introduce newlines, carriage returns, and whitespace
    final dirty = 'data:image/png;base64,\n  $raw\r\n ';
    
    final commaIndex = dirty.indexOf(',');
    var clean = dirty.substring(commaIndex + 1);
    clean = clean.replaceAll(RegExp(r'\s+'), '').replaceAll(' ', '+');
    clean = base64.normalize(clean);
    final decoded = base64Decode(clean);
    expect(decoded.length, greaterThan(0));
  });
}
