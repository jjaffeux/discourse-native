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

  group('resolveSiteRootPath', () {
    test('keeps a subfolder site prefix for an app-built root path', () {
      expect(
        resolveSiteRootPath('https://example.com/forum', '/latest'),
        'https://example.com/forum/latest',
      );
      expect(
        resolveSiteRootPath('https://example.com/forum/', '/u/sam?tab=x'),
        'https://example.com/forum/u/sam?tab=x',
      );
    });

    test('resolves a root site exactly as a root-relative link would', () {
      for (final site in ['https://example.com', 'http://localhost:4200']) {
        for (final path in ['/latest', '/c/general/4', '/t/a-topic/7/2']) {
          expect(
            resolveSiteRootPath(site, path),
            resolveSiteUrl(path, site),
            reason: '$site$path',
          );
        }
      }
    });
  });
}
