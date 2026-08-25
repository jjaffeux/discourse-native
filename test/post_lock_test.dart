import 'package:discourse_native/src/models/post.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads and preserves the post author identity and lock state', () {
    final post = Post.fromJson(const {
      'id': 42,
      'post_number': 2,
      'user_id': 7,
      'username': 'sam',
      'cooked': '<p>Do not edit</p>',
      'locked': true,
    }, 'https://example.com');

    expect(post.userId, 7);
    expect(post.locked, isTrue);
    expect(post.copyWith(hidden: true).locked, isTrue);
    expect(post.copyWith(locked: false).locked, isFalse);
    expect(post.copyWith(locked: false).userId, 7);
  });
}
