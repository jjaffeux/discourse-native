import 'package:discourse_native/src/models/list_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ListLink.parse', () {
    /// The link as `kind:slug:id:feedPath`, or `-` for anything refused.
    String read(String url) {
      final link = ListLink.parse(url);
      if (link == null) return '-';
      return '${link.kind.name}:${link.slug}:${link.id}:${link.feedPath}';
    }

    test('reads a category', () {
      expect(read('/c/bug/5'), 'category:bug:5:/c/bug/5.json');
    });

    test('keeps a subcategory path whole', () {
      // The depth is not decoration: `/c/child/12` is a different category
      // from `/c/parent/child/12`, and rebuilding the path from the slug and
      // the id is how a working link stops working.
      expect(
        read('/c/parent/child/12'),
        'category:child:12:/c/parent/child/12.json',
      );
      expect(
        read('/c/a/b/c/9'),
        'category:c:9:/c/a/b/c/9.json',
      );
    });

    test('reads a category named only by id', () {
      expect(read('/c/12'), 'category::12:/c/12.json');
    });

    test('reads a tag', () {
      expect(read('/tag/ux/3'), 'tag:ux:3:/tag/ux/3.json');
    });

    test('reads the older slug-only tag', () {
      // Posts cooked before tag urls carried an id still say this.
      expect(read('/tag/ux'), 'tag:ux:null:/tag/ux.json');
    });

    test('reads a bare number after /tag/ as an id, the way Discourse does', () {
      // `/tag/2024` is genuinely ambiguous — a tag called 2024, or tag id
      // 2024 — and Discourse settles it as the id: its `/tag/:tag_id` route
      // is constrained to digits and is matched ahead of the legacy name one.
      // It costs nothing either way, because the list is at the same address
      // on both readings; only the stand-in title differs.
      expect(read('/tag/2024'), 'tag::2024:/tag/2024.json');
      // Only the *last* segment is ever the id, so a category can be called
      // 2024 without being confused for one.
      expect(read('/c/2024/7'), 'category:2024:7:/c/2024/7.json');
    });

    test('survives a trailing slash', () {
      expect(read('/c/bug/5/'), 'category:bug:5:/c/bug/5.json');
    });

    test('reads an absolute url', () {
      expect(
        read('https://meta.discourse.org/c/bug/5'),
        'category:bug:5:/c/bug/5.json',
      );
    });

    test('refuses a filtered list', () {
      // Real routes, but filters this app has no screen for. The browser can
      // have them rather than us quietly showing the unfiltered list instead.
      expect(read('/c/bug/5/l/top'), '-');
      expect(read('/c/bug/5/l/latest'), '-');
      expect(read('/c/bug/5/none'), '-');
      expect(read('/c/bug/5/subcategories'), '-');
      expect(read('/tag/ux/3/l/top'), '-');
    });

    test('refuses everything that is not a list', () {
      expect(read('/c/bug'), '-'); // no id, and not a tag
      expect(read('/tags'), '-');
      expect(read('/tags/c/bug/5/ux'), '-');
      expect(read('/t/a-slug/9'), '-');
      expect(read('/u/sam'), '-');
      expect(read('/latest'), '-');
      expect(read('/'), '-');
      expect(read(''), '-');
      expect(read('mailto:someone@example.com'), '-');
    });

    test('refuses an id that is not one', () {
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
