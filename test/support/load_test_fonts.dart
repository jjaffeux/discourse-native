import 'dart:convert';

import 'package:flutter/services.dart';

/// Loads the application's bundled fonts for readable layout evidence.
Future<void> loadTestFonts() async {
  final manifest =
      jsonDecode(await rootBundle.loadString('FontManifest.json'))
          as List<dynamic>;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(entry['family'] as String);
    for (final face in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(face['asset'] as String));
    }
    await loader.load();
  }
}
