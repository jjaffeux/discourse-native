import 'package:discourse_native/src/models/post.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads and preserves a reply permanent-delete capability', () {
    final post = Post.fromJson(const {
      'id': 42,
      'post_number': 2,
      'username': 'sam',
      'cooked': '<p>Deleted</p>',
      'deleted_at': '2026-08-25T10:00:00Z',
      'can_permanently_delete': true,
    }, 'https://example.com');

    expect(post.isDeleted, isTrue);
    expect(post.canPermanentlyDelete, isTrue);
    expect(post.copyWith(hidden: true).canPermanentlyDelete, isTrue);
  });

  test('reads and preserves the opening-post topic capability', () {
    final payload = TopicDetail.parse(const {
      'id': 7,
      'title': 'Deleted topic',
      'deleted_at': '2026-08-25T10:00:00Z',
      'post_stream': {'stream': <int>[], 'posts': <Object>[]},
      'details': {'can_permanently_delete': true},
    }, 'https://example.com');

    expect(payload.detail.canPermanentlyDelete, isTrue);
    expect(payload.detail.copyWith(closed: true).canPermanentlyDelete, isTrue);
    expect(
      payload.detail.withPlugins(payload.detail.plugins).canPermanentlyDelete,
      isTrue,
    );
  });
}
