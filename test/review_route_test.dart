import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:flutter_test/flutter_test.dart';

const _forum = DiscourseInstance(
  url: 'https://forum.example/discuss',
  title: 'Forum',
  user: DiscourseUser(id: 7, username: 'sam', staff: true),
);

ContentRoute? _decode(String path, {DiscourseInstance forum = _forum}) =>
    ContentRouteCodec.fromUrl(
      '${forum.url}$path',
      instance: forum,
      config: const SiteConfig(),
      defaultTopPeriod: TopPeriod.yearly,
    );

void main() {
  test('the queue and one of its items are distinct saved destinations', () {
    final queue = _decode('/review')!;
    final item = _decode('/review/42')!;

    expect(queue.isPage(CorePage.review), isTrue);
    expect(queue.id, 'review');
    expect(item.isPage(CorePage.review), isTrue);
    expect(item.id, 'review-42');
    expect((item.destination as PageDestination).reviewableId, 42);
    expect(queue.sameDestinationAs(item), isFalse);

    for (final route in [queue, item]) {
      final restored = ContentRouteCodec.decode(
        Map<String, dynamic>.from(ContentRouteCodec.encode(route)),
      );
      expect(restored.sameDestinationAs(route), isTrue);
      expect(restored.id, route.id);
    }
  });

  test('an account that cannot review still lands on the native page', () {
    const member = DiscourseInstance(
      url: 'https://forum.example/discuss',
      title: 'Forum',
      user: DiscourseUser(id: 9, username: 'ann'),
    );
    expect(_decode('/review', forum: member)!.isPage(CorePage.review), isTrue);
  });

  test('review links the page cannot honour are left to the browser', () {
    const anonymous = DiscourseInstance(
      url: 'https://forum.example/discuss',
      title: 'Forum',
    );
    expect(_decode('/review', forum: anonymous), isNull);
    for (final path in [
      '/review/0',
      '/review/-3',
      '/review/abc',
      '/review/7/extra',
      '/review/settings',
      '/review?status=approved',
    ]) {
      expect(_decode(path)?.isPage(CorePage.review), isNot(true), reason: path);
    }
  });

  test('a saved item id must be a positive id on the review page', () {
    final saved = Map<String, dynamic>.from(
      ContentRouteCodec.encode(ContentRoute.review(reviewableId: 5)),
    );
    for (final invalid in <Object>[0, -1, '5', 1.5]) {
      expect(
        () => ContentRouteCodec.decode({...saved, 'reviewable_id': invalid}),
        throwsFormatException,
        reason: '$invalid',
      );
    }
    expect(
      () => ContentRouteCodec.decode({
        ...saved,
        'id': 'dashboard',
        'page': 'dashboard',
      }),
      throwsFormatException,
    );
  });
}
