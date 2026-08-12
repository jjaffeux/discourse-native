import 'package:discourse_native/src/shell/external_link.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> launched;

  setUp(() {
    launched = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'launch') {
        launched.add((call.arguments as Map)['url'] as String);
      }
      return true;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('launches web and email links in an external application', () async {
    const links = [
      'https://meta.discourse.org/faq',
      'http://example.com/development',
      'mailto:team@example.com?subject=Hello',
    ];

    for (final link in links) {
      expect(await openExternalLink(link), isTrue);
    }

    expect(launched, links);
  });

  test('rejects unsafe schemes before invoking the launcher', () async {
    const links = [
      'javascript:alert(1)',
      'file:///tmp/private.txt',
      'data:text/html,<script>alert(1)</script>',
      'discourse-native://settings',
    ];

    for (final link in links) {
      expect(await openExternalLink(link), isFalse);
    }

    expect(launched, isEmpty);
  });

  test(
    'rejects credential-bearing web links before invoking the launcher',
    () async {
      const links = [
        'https://reader:secret@meta.discourse.org/faq',
        'https://meta.discourse.org@attacker.example/faq',
        'http://reader@127.0.0.1:3000/private',
      ];

      for (final link in links) {
        expect(await openExternalLink(link), isFalse);
      }

      expect(launched, isEmpty);
    },
  );

  test(
    'rejects malformed and relative links before invoking the launcher',
    () async {
      expect(await openExternalLink('not a URL'), isFalse);
      expect(await openExternalLink('/t/a-topic/1'), isFalse);
      expect(await openExternalLink('https:missing-host'), isFalse);
      expect(await openExternalLink('http:///missing-host'), isFalse);
      expect(await openExternalLink('mailto:'), isFalse);

      expect(launched, isEmpty);
    },
  );

  test('reports a platform launcher failure without throwing', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'unavailable');
    });

    expect(await openExternalLink('https://meta.discourse.org'), isFalse);
  });
}
