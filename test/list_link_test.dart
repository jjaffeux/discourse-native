import 'package:discourse_native/src/models/list_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ListLink.parse', () {
    String read(String url) {
      final link = ListLink.parse(url);
      if (link == null) return '-';
      return '${link.kind.name}:${link.slug}:${link.id}:${link.feedPath}';
    }

    test('reads a category', () {
      expect(read('/c/bug/5'), 'category:bug:5:/c/bug/5.json');
    });

    test('keeps a subcategory path whole', () {
      expect(
        read('/c/parent/child/12'),
        'category:child:12:/c/parent/child/12.json',
      );
      expect(read('/c/a/b/c/9'), 'category:c:9:/c/a/b/c/9.json');
    });

    test('reads a category named only by ID', () {
      expect(read('/c/12'), 'category::12:/c/12.json');
    });

    test('reads a tag', () {
      expect(read('/tag/ux/3'), 'tag:ux:3:/tag/ux/3.json');
    });

    test('reads the older slug-only tag', () {
      expect(read('/tag/ux'), 'tag:ux:null:/tag/ux.json');
    });

    test(
      'reads a bare number after /tag/ as an ID, the way Discourse does',
      () {
        // Discourse routes a numeric final tag segment as an ID.
        expect(read('/tag/2024'), 'tag::2024:/tag/2024.json');
        expect(read('/c/2024/7'), 'category:2024:7:/c/2024/7.json');
      },
    );

    test('survives a trailing slash', () {
      expect(read('/c/bug/5/'), 'category:bug:5:/c/bug/5.json');
    });

    test('reads an absolute URL', () {
      expect(
        read('https://meta.discourse.org/c/bug/5'),
        'category:bug:5:/c/bug/5.json',
      );
    });

    test('refuses a filtered list', () {
      expect(read('/c/bug/5/l/top'), '-');
      expect(read('/c/bug/5/l/latest'), '-');
      expect(read('/c/bug/5/none'), '-');
      expect(read('/c/bug/5/subcategories'), '-');
      expect(read('/tag/ux/3/l/top'), '-');
    });

    test('refuses everything that is not a list', () {
      expect(read('/c/bug'), '-');
      expect(read('/tags'), '-');
      expect(read('/tags/c/bug/5/ux'), '-');
      expect(read('/t/a-slug/9'), '-');
      expect(read('/u/sam'), '-');
      expect(read('/latest'), '-');
      expect(read('/'), '-');
      expect(read(''), '-');
      expect(read('mailto:someone@example.com'), '-');
    });

    test('refuses oversized and credential-bearing links', () {
      expect(read('/tag/${'a' * ListLink.maximumUrlLength}'), '-');
      expect(read('https://user:secret@meta.discourse.org/tag/ux'), '-');
    });

    test('refuses an ID that is not one', () {
      expect(read('/c/bug/0'), '-');
      expect(read('/c/bug/-3'), '-');
    });
  });

  group('placeholderTitle', () {
    String titleOf(String url) => ListLink.parse(url)!.placeholderTitle;

    test('reads the slug as words', () {
      expect(titleOf('/c/feature-requests/5'), 'Feature requests');
      expect(titleOf('/tag/ux'), 'Ux');
    });

    test('falls back to what the link is when there is no slug', () {
      expect(titleOf('/c/12'), 'Category');
    });
  });
}
