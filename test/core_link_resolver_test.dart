import 'dart:ui' show Color;

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/core_link_resolver.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter_test/flutter_test.dart';

const _root = DiscourseInstance(url: 'https://example.com', title: 'Root');
const _nested = DiscourseInstance(
  url: 'https://example.com/forum',
  title: 'Nested',
);
const _deep = DiscourseInstance(
  url: 'https://example.com/forum/help',
  title: 'Deep',
);

CoreLinkTarget? _match(
  String url, {
  String? base = 'https://example.com/forum',
  List<DiscourseInstance> sites = const [_root, _nested, _deep],
}) => CoreLinkTarget.match(url, currentSiteUrl: base, instances: sites);

void main() {
  test('matching chooses the deepest configured forum in either order', () {
    for (final sites in [
      const [_root, _nested, _deep],
      const [_deep, _nested, _root],
    ]) {
      expect(
        _match('/forum/help/t/example/7', sites: sites)?.instance,
        same(_deep),
      );
      expect(
        _match('/forum/t/example/7', sites: sites)?.instance,
        same(_nested),
      );
      expect(
        _match('/forums/t/example/7', sites: sites)?.instance,
        same(_root),
      );
    }
    expect(
      _match(
        '/forum/t/example/7',
        sites: [
          _nested,
          _nested.copyWith(title: 'Duplicate'),
        ],
      )?.instance,
      same(_nested),
    );
  });

  test(
    'relative links retain site URL file semantics and protocol-relative matching',
    () {
      expect(_match('t/example/7')?.instance, same(_root));
      expect(
        _match('t/example/7', base: 'https://example.com/forum/')?.instance,
        same(_nested),
      );
      expect(
        _match('//example.com/forum/t/example/7', base: null)?.instance,
        same(_nested),
      );
      expect(_match('/forum/t/example/7', base: null), isNull);
    },
  );

  test('external and malformed links are declined', () {
    for (final url in [
      'https://elsewhere.example/t/example/7',
      'https://[',
      'mailto:person@example.com',
    ]) {
      expect(_match(url), isNull, reason: url);
    }
    expect(
      _match('https://example.com/t/example/7', sites: const [_nested]),
      isNull,
    );
  });

  test(
    'credential-bearing links retain codec admission after forum matching',
    () {
      final target = _match(
        'https://user:secret@example.com/forum/t/example/7',
      );
      expect(target?.instance, same(_nested));
      expect(target!.decode(config: const SiteConfig()), isNull);
    },
  );

  test('only bare roots receive configured or contributed homepages', () {
    const config = SiteConfig(defaultHomepage: 'categories');
    const contributed = ContentRoute(
      destination: ExtensionDestination('custom-home'),
      title: 'Custom home',
      icon: DIcons.folder,
    );
    for (final path in ['/forum', '/forum/']) {
      final target = _match(path)!;
      expect(target.isHomepage, isTrue);
      expect(target.decode(config: config)?.id, 'all-categories');
      expect(
        target.decode(
          config: config,
          homepage: contributed,
          title: 'Ignored',
          specializedTitle: 'Also ignored',
        ),
        same(contributed),
      );
    }
    for (final path in ['/forum?x=1', '/forum#section']) {
      final target = _match(path)!;
      expect(target.isHomepage, isFalse);
      expect(target.decode(config: config, homepage: contributed), isNull);
    }
  });

  test(
    'the codec retains site configuration and account admission authority',
    () {
      expect(
        _match('/forum/top')!
            .decode(config: const SiteConfig(topPageDefaultPeriod: 'monthly'))
            ?.id,
        'top-monthly',
      );
      expect(
        _match(
          '/forum/badges/1',
        )!.decode(config: const SiteConfig(badgesEnabled: false)),
        isNull,
      );
      expect(
        _match('/forum/unread')!.decode(config: const SiteConfig()),
        isNull,
      );
      expect(
        _match('/forum/my/messages')!.decode(config: const SiteConfig()),
        isNull,
      );
      final signedIn = _nested.copyWith(
        user: const DiscourseUser(id: 1, username: 'sam'),
      );
      final own = _match('/forum/u/sam/messages', sites: [signedIn])!;
      expect(own.decode(config: const SiteConfig())?.isMessages, isTrue);
      expect(
        _match(
          '/forum/u/other/messages',
          sites: [signedIn],
        )!.decode(config: const SiteConfig()),
        isNull,
      );
    },
  );

  for (final (path, expected) in const [
    ('/forum/t/a-topic/7', 'General title'),
    ('/forum/badges/1', 'Special title'),
    ('/forum/c/support/12', 'Special title'),
    ('/forum/tag/news', 'Special title'),
    ('/forum/g/staff', 'staff'),
    ('/forum/about', 'About this forum'),
  ]) {
    test('title policy for $path stays with the owning destination', () {
      final target = _match(path)!;
      expect(
        target
            .decode(
              config: const SiteConfig(),
              title: 'General title',
              specializedTitle: 'Special title',
            )
            ?.title,
        expected,
      );
      if (path.contains('/badges/') ||
          path.contains('/c/') ||
          path.contains('/tag/')) {
        expect(
          target
              .decode(config: const SiteConfig(), title: 'General title')
              ?.title,
          'General title',
        );
      }
    });
  }

  test(
    'numeric category color comes from canonical facts independently of directory',
    () {
      const category = TopicCategory(
        id: 12,
        name: 'Support',
        color: '123456',
        slug: 'support',
      );
      final target = _match('/forum/c/support/12')!;
      final decoded = target.decode(config: const SiteConfig())!;
      final result = target.enrich(
        decoded,
        category: category,
        filterCategories: const [],
      );
      expect(result.siteUrl, _nested.url);
      expect(result.route.color, const Color(0xff123456));
      expect(result.route.destination, decoded.destination);
      expect(result.route.feedPath, decoded.feedPath);
    },
  );

  test(
    'slug-only links use top-level directory categories and retain route identity',
    () {
      const child = TopicCategory(
        id: 99,
        name: 'Child',
        color: 'ff0000',
        slug: 'support',
        parentCategoryId: 1,
      );
      const category = TopicCategory(
        id: 12,
        name: 'Support',
        color: '123456',
        slug: 'support',
      );
      final target = _match('/forum/c/support')!;
      final decoded = target.decode(
        config: const SiteConfig(),
        title: 'Support title',
      )!;
      final result = target.enrich(
        decoded,
        category: null,
        filterCategories: const [child, category],
      );
      expect(result.route.id, decoded.id);
      expect(result.route.title, 'Support title');
      expect(result.route.feedPath, '/c/support/12.json');
      expect(result.route.color, const Color(0xff123456));
      expect(
        target
            .enrich(decoded, category: null, filterCategories: const [child])
            .route
            .feedPath,
        decoded.feedPath,
      );
    },
  );
}
