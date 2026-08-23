import 'package:discourse_native/src/models/post.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes Discourse whisper posts', () {
    final post = Post.fromJson(const {
      'id': 5,
      'post_number': 3,
      'username': 'sam',
      'cooked': '<p>Private aside</p>',
      'post_type': 4,
    }, 'https://meta.discourse.org');

    expect(Post.whisperPostType, 4);
    expect(post.isWhisper, isTrue);
    expect(post.isSmallAction, isFalse);
  });
}
