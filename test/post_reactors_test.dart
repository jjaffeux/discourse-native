import 'package:discourse_native/src/plugins/reactions/post_reactors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const site = 'https://meta.discourse.org';

  PostReactors parse(Map<String, dynamic> json, {String? filter}) =>
      PostReactors.parse(json, postId: 1, siteUrl: site, filter: filter);

  test('reads the envelope the reactions route answers with', () {
    final reactors = parse({
      'users': [
        {
          'id': 3,
          'username': 'sam',
          'name': 'Sam Saffron',
          'avatar_template': '/user_avatar/sam/{size}/1.png',
          'reaction': 'clap',
        },
      ],
      'total_rows': 12,
    });

    expect(reactors.reactors, hasLength(1));
    expect(reactors.reactors.single.username, 'sam');
    expect(reactors.reactors.single.displayName, 'Sam Saffron');
    expect(
      reactors.reactors.single.avatarUrl,
      '$site/user_avatar/sam/90/1.png',
    );
    expect(reactors.reactors.single.reaction, 'clap');
    expect(reactors.total, 12);
  });

  test('falls back to the username where the site has no names', () {
    final reactors = parse({
      'users': [
        {'id': 3, 'username': 'sam', 'reaction': 'heart'},
      ],
      'total_rows': 1,
    });

    expect(reactors.reactors.single.name, isNull);
    expect(reactors.reactors.single.displayName, 'sam');
  });

  test('preserves each server-provided reaction in order', () {
    final reactors = parse({
      'users': [
        {'id': 3, 'username': 'sam', 'reaction': 'heart'},
        {'id': 4, 'username': 'codinghorror', 'reaction': 'clap'},
      ],
      'total_rows': 2,
    });

    expect(reactors.reactors.map((r) => r.reaction), ['heart', 'clap']);
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

  test('an empty answer is an empty list rather than a failure', () {
    expect(parse(const {}).reactors, isEmpty);
    expect(parse(const {}).total, 0);
  });

  test('the unfiltered list and a per-emoji one are separate records', () {
    expect(parse(const {}).storeId, '1');
    expect(parse(const {}, filter: 'clap').storeId, '1:clap');
    expect(PostReactors.key(1, null), isNot(PostReactors.key(1, 'clap')));
  });
}
