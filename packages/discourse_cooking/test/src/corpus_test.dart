import 'dart:convert';
import 'dart:io';

import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:test/test.dart';

void main() {
  final corpus =
      (jsonDecode(File('js/test/corpus.json').readAsStringSync()) as List)
          .cast<Map<String, Object?>>();
  late OfflineCookingService service;
  setUpAll(() => service = OfflineCookingService());
  tearDownAll(() => service.dispose());
  for (final fixture in corpus) {
    test('shared JS/native corpus: ${fixture['name']}', () async {
      final snapshot = <String, Object?>{
        'siteId': 'corpus',
        'accountId': 'anonymous',
        ...?fixture['snapshot'] as Map<String, Object?>?,
      };
      final result = await service.cook(
        CookingRequest(
          raw: fixture['raw']! as String,
          profile: CookingProfile.values.byName(fixture['profile']! as String),
          snapshot: CookingSnapshot.fromJson(snapshot),
        ),
      );
      expect(result.failure, isNull);
      expect(result.warnings, isEmpty);
      if (fixture['html'] case final String html) expect(result.html, html);
      for (final part
          in (fixture['includes'] as List? ?? const []).cast<String>()) {
        expect(result.html, contains(part));
      }
      for (final part
          in (fixture['excludes'] as List? ?? const []).cast<String>()) {
        expect(result.html, isNot(contains(part)));
      }
    });
  }
}
