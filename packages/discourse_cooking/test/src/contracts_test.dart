import 'dart:convert';

import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:test/test.dart';

void main() {
  test('snapshot construction bounds total strings and wide collections', () {
    for (final values in <Map<String, Object?>>[
      {'large': 'x' * 262145},
      {'wide': List<Object?>.filled(65537, null)},
      {for (var i = 0; i < 32769; i++) '$i': null},
    ]) {
      expect(
        () => CookingSnapshot(siteId: 'a', accountId: 'b', uploads: values),
        throwsArgumentError,
      );
    }
    expect(
      () => CookingSnapshot(
        siteId: 'a',
        accountId: 'b',
        uploads: {'part': 'x' * 140000},
        oneboxes: {'part': 'x' * 140000},
      ),
      throwsArgumentError,
    );
  });
  test('rejects cyclic or excessively nested snapshots', () {
    final cycle = <String, Object?>{};
    cycle['self'] = cycle;
    expect(
      () => CookingSnapshot(siteId: 'a', accountId: 'b', uploads: cycle),
      throwsArgumentError,
    );
    Object? nested = 'leaf';
    for (var i = 0; i < 40; i++) {
      nested = <Object?>[nested];
    }
    expect(
      () => CookingSnapshot(
        siteId: 'a',
        accountId: 'b',
        uploads: {'deep': nested},
      ),
      throwsArgumentError,
    );
  });
  test('request survives serialization and snapshots own recursive copies', () {
    final nested = <String, Object?>{
      'items': <Object?>['original'],
    };
    final snapshot = CookingSnapshot(
      siteId: 'a',
      accountId: 'alice',
      uploads: nested,
    );
    (nested['items']! as List)[0] = 'changed';
    expect(snapshot.uploads['items'], ['original']);
    expect(
      () => (snapshot.uploads['items']! as List).add('bad'),
      throwsUnsupportedError,
    );
    expect(() => snapshot.uploads['bad'] = true, throwsUnsupportedError);
    final request = CookingRequest(
      raw: '你好 😀',
      snapshot: snapshot,
      profile: CookingProfile.chat,
    );
    final decoded = CookingRequest.fromJson(
      (jsonDecode(jsonEncode(request.toJson())) as Map).cast<String, Object?>(),
    );
    expect(decoded.toJson(), request.toJson());
  });

  test('rejects non JSON snapshot values', () {
    for (final value in [double.infinity, double.nan, Object(), () {}]) {
      expect(
        () =>
            CookingSnapshot(siteId: 'a', accountId: 'b', uploads: {'x': value}),
        throwsArgumentError,
      );
    }
  });

  test('result warnings immutable and result serializable', () {
    final warnings = ['missing-context'];
    final result = CookingResult(
      html: '<p>ok</p>',
      warnings: warnings,
      memoryUsageBytes: 100,
      elapsedMicroseconds: 2,
    );
    warnings.clear();
    expect(result.warnings, ['missing-context']);
    expect(CookingResult.fromJson(result.toJson()).toJson(), result.toJson());
  });

  test('fallback escapes hostile text and truncates at a scalar boundary', () {
    final result = readableFallback(
      '${'a' * 8191}😀<script>',
      CookingFailure.inputLimit,
    );
    expect(result.html, isNot(contains('�')));
    expect(result.html.length, lessThan(8300));
    expect(result.failure, CookingFailure.inputLimit);
    expect(
      readableFallback('<script>&', CookingFailure.engine).html,
      '<pre>&lt;script&gt;&amp;</pre>',
    );
  });
}
