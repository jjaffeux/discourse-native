import 'dart:convert';

import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'reading fonts are bundled under the families used by the app',
    () async {
      // Run from both the root and profiles/full. Dependency fonts normally get
      // package-prefixed family names. Themes must resolve a bundled face in
      // either launch target before falling back to a system font.
      final manifest =
          jsonDecode(await rootBundle.loadString('FontManifest.json'))
              as List<dynamic>;
      for (final font in ForumFont.values.where(
        (font) => font.family != null,
      )) {
        final style = AppTheme.forBrightness(
          Brightness.light,
          fontFamily: font.family,
        ).textTheme.bodyMedium!;
        final families = [style.fontFamily, ...?style.fontFamilyFallback];
        final entry = manifest.cast<Map<String, dynamic>>().firstWhere(
          (entry) => families.contains(entry['family']),
          orElse: () => fail('Missing bundled font family: ${font.family}'),
        );
        final faces = (entry['fonts'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(faces, isNotEmpty);
        if (font == ForumFont.lora) {
          expect(
            {
              for (final face in faces)
                (face['weight'] ?? 400, face['style'] ?? 'normal'),
            },
            containsAll({
              (400, 'normal'),
              (700, 'normal'),
              (400, 'italic'),
              (700, 'italic'),
              if (font == ForumFont.lora) ...{(600, 'normal'), (600, 'italic')},
            }),
          );
          final asset = faces.first['asset'] as String;
          final prefix = asset.substring(0, asset.indexOf('assets/fonts/'));
          final license = await rootBundle.loadString(
            '${prefix}assets/fonts/${font.family}-OFL.txt',
          );
          expect(license, contains('SIL OPEN FONT LICENSE'));
          for (final face in faces) {
            final bytes = await rootBundle.load(face['asset'] as String);
            final metadata = _fontMetadata(bytes);
            expect(
              metadata.italic,
              face['style'] == 'italic',
              reason: face['asset'] as String,
            );
            final weight = face['weight'] as int;
            expect(metadata.weight, weight, reason: face['asset'] as String);
          }
        }
        final loader = FontLoader(entry['family'] as String);
        for (final face in faces) {
          loader.addFont(rootBundle.load(face['asset'] as String));
        }
        await loader.load();
      }
    },
  );
}

({bool italic, int weight}) _fontMetadata(ByteData bytes) {
  final tableCount = bytes.getUint16(4);
  bool? italic;
  int? weight;
  for (var index = 0; index < tableCount; index++) {
    final table = 12 + index * 16;
    final tag = String.fromCharCodes([
      for (var offset = 0; offset < 4; offset++) bytes.getUint8(table + offset),
    ]);
    final start = bytes.getUint32(table + 8);
    if (tag == 'head') italic = bytes.getUint16(start + 44) & 2 != 0;
    if (tag == 'OS/2') weight = bytes.getUint16(start + 4);
  }
  if (italic == null || weight == null) {
    fail('Bundled font has no style metadata');
  }
  return (italic: italic, weight: weight);
}
