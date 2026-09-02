import 'package:discourse_native/src/shell/site_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveSitePath', () {
    test('keeps a subfolder site prefix for an app-built path', () {
      expect(
        resolveSitePath('https://example.com/forum', 'g/staff'),
        'https://example.com/forum/g/staff',
      );
      expect(
        resolveSitePath('https://example.com/forum/', 'g/staff'),
        'https://example.com/forum/g/staff',
      );
    });

    test('resolves against a root site with or without a trailing slash', () {
      expect(
        resolveSitePath('https://example.com', 'g/staff'),
        'https://example.com/g/staff',
      );
      expect(
        resolveSitePath('https://example.com/', 'g/staff'),
        'https://example.com/g/staff',
      );
    });

    test('returns an absolute link unchanged', () {
      expect(
        resolveSitePath('https://example.com/forum', 'https://cdn.example/x'),
        'https://cdn.example/x',
      );
    });
  });
}
