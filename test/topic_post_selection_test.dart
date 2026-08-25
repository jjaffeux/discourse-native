import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/plugins/plugin_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads and preserves the selected-post guardian capabilities', () {
    final payload = TopicDetail.parse(const {
      'id': 7,
      'title': 'Moderated topic',
      'post_stream': {
        'stream': [1],
        'posts': [
          {
            'id': 1,
            'post_number': 1,
            'username': 'sam',
            'cooked': '<p>hello</p>',
          },
        ],
      },
      'details': {'can_move_posts': true, 'can_split_merge_topic': true},
    }, 'https://example.com');

    expect(payload.detail.canMovePosts, isTrue);
    expect(payload.detail.canSplitMergeTopic, isTrue);
    expect(payload.detail.hasStatusActions, isTrue);
    expect(payload.detail.copyWith(closed: true).canMovePosts, isTrue);
    expect(
      payload.detail.withPlugins(PluginData.none).canSplitMergeTopic,
      isTrue,
    );
  });
}
