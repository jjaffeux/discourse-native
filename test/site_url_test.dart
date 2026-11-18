import 'package:discourse_native/src/shell/site_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('path-relative cooked links stay inside a subfolder forum', () {
    expect(
      resolveSiteUrl('t/topic/7', 'https://example.com/forum'),
      'https://example.com/forum/t/topic/7',
    );
    expect(
      resolveSiteUrl('/uploads/a.png', 'https://example.com/forum'),
      'https://example.com/uploads/a.png',
    );
  });

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
    test('resolves app-built root paths against the site directory', () {
      expect(
        resolveSiteRootPath('https://example.com/forum', '/latest'),
        'https://example.com/forum/latest',
      );
      expect(
        resolveSiteRootPath('https://example.com/forum/', '/u/sam?tab=x'),
        'https://example.com/forum/u/sam?tab=x',
      );
      expect(
        resolveSiteRootPath('http://localhost:4200', '/c/general/4'),
        'http://localhost:4200/c/general/4',
      );
    });
  });
}
