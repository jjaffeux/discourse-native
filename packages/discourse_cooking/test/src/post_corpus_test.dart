import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:test/test.dart';

void main() {
  final corpus =
      jsonDecode(File('js/test/post-corpus.json').readAsStringSync())
          as Map<String, dynamic>;
  final modules = (corpus['configuration']['modules'] as List)
      .map(
        (value) =>
            CookingModule.fromJson(Map<String, Object?>.from(value as Map)),
      )
      .toList();
  late OfflineCookingService service;
  setUpAll(() => service = OfflineCookingService());
  tearDownAll(() => service.dispose());

  Future<String> cook(Map<String, dynamic> fixture) async {
    final snapshot =
        jsonDecode(
              jsonEncode({
                ...corpus['snapshot'] as Map,
                ...?fixture['snapshot'] as Map?,
              }),
            )
            as Map<String, dynamic>;
    for (final entry in (fixture['pluginSettings'] as Map? ?? {}).entries) {
      (snapshot['pluginContext'][entry.key]['settings'] as Map).addAll(
        entry.value as Map,
      );
    }
    final omitted = fixture['omitModules'] as List? ?? [];
    final result = await service.cook(
      CookingRequest(
        raw: fixture['raw'] as String,
        profile: CookingProfile.values.byName(
          fixture['profile'] as String? ?? 'post',
        ),
        configuration: CookingConfiguration(
          modules: modules
              .where((module) => !omitted.contains(module.id))
              .toList(),
        ),
        snapshot: CookingSnapshot.fromJson(snapshot),
      ),
    );
    expect(result.failure, isNull, reason: result.warnings.join(', '));
    return result.html;
  }

  for (final fixture
      in (corpus['fixtures'] as List).cast<Map<String, dynamic>>()) {
    test('pinned post rules: ${fixture['name']}', () async {
      final html = await cook(fixture);
      if (fixture['html'] case final String expected) expect(html, expected);
      for (final value in fixture['includes'] as List? ?? []) {
        expect(html, contains(value));
      }
      for (final value in fixture['excludes'] as List? ?? []) {
        expect(html, isNot(contains(value)));
      }
      for (final entry in (fixture['counts'] as Map? ?? {}).entries) {
        expect(html.split(entry.key as String).length - 1, entry.value);
      }
    });
  }
  test('native worker poll IDs match independent UTF-8 JSON MD5', () async {
    for (final text in ['Café', '猫 😺', 'é é', 'العربية', '👨‍👩‍👧‍👦']) {
      final hash = md5.convert(utf8.encode(jsonEncode([text])));
      final html = await cook({'raw': '[poll]\n* $text\n* other\n[/poll]'});
      expect(html, contains('data-poll-option-id="$hash"'));
    }
  });
}
