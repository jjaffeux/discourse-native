import 'package:discourse_native/src/plugins/reactions/post_reactors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const site = 'https://meta.discourse.org';

  PostReactors parse(Map<String, dynamic> json, {String? filter}) =>
      PostReactors.parse(json, postId: 1, siteUrl: site, filter: filter);

  test('reads named and unnamed reactors in server reaction order', () {
    final reactors = parse({
      'users': [
        {
          'id': 3,
          'username': 'sam',
          'name': 'Sam Saffron',
          'avatar_template': '/user_avatar/sam/{size}/1.png',
          'reaction': 'heart',
        },
        {'id': 4, 'username': 'codinghorror', 'reaction': 'clap'},
      ],
      'total_rows': 12,
    });

    expect(reactors.reactors, hasLength(2));
    expect(reactors.reactors.first.username, 'sam');
    expect(reactors.reactors.first.displayName, 'Sam Saffron');
    expect(reactors.reactors.first.avatarUrl, '$site/user_avatar/sam/90/1.png');
    expect(reactors.reactors.map((r) => r.reaction), ['heart', 'clap']);
    expect(reactors.reactors.last.name, isNull);
    expect(reactors.reactors.last.displayName, 'codinghorror');
    expect(reactors.total, 12);
  });

  test('retains at most one legal server page in its original order', () {
    final reactors = parse({
      'users': [
        for (var index = 0; index < 55; index++)
          {'id': index + 1, 'username': 'user-$index', 'reaction': 'heart'},
      ],
      'total_rows': 55,
    });

    expect(reactors.reactors.map((reactor) => reactor.username), [
      for (var index = 0; index < PostReactors.maximumPageSize; index++)
        'user-$index',
    ]);
    expect(reactors.total, 55);
  });

  test('empty answers keep distinct unfiltered and per-emoji record keys', () {
    final empty = parse(const {});
    expect(empty.reactors, isEmpty);
    expect(empty.total, 0);
    expect(empty.storeId, '1');
    expect(parse(const {}, filter: 'clap').storeId, '1:clap');
    expect(PostReactors.key(1, null), isNot(PostReactors.key(1, 'clap')));
  });
}
