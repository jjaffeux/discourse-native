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
        final loader = FontLoader(entry['family'] as String);
        for (final face in faces) {
          loader.addFont(rootBundle.load(face['asset'] as String));
        }
        await loader.load();
      }
    },
  );
}
