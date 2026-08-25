import 'package:discourse_native/src/models/post.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads and preserves the wiki state and its guardian gate', () {
    final post = Post.fromJson(const {
      'id': 42,
      'post_number': 2,
      'username': 'sam',
      'cooked': '<p>Shared notes</p>',
      'wiki': true,
      'can_wiki': true,
    }, 'https://example.com');

    expect(post.wiki, isTrue);
    expect(post.canWiki, isTrue);
    expect(post.copyWith(hidden: true).wiki, isTrue);
    expect(post.copyWith(wiki: false).wiki, isFalse);
    expect(post.copyWith(wiki: false).canWiki, isTrue);
  });
}
