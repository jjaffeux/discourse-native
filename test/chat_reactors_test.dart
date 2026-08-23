import 'package:discourse_native/src/plugins/chat/chat_reactors.dart';
import 'package:flutter_test/flutter_test.dart';

const _siteUrl = 'https://meta.discourse.org';

void main() {
  test('reads chat reactor users in the shared presentation shape', () {
    final page = ChatMessageReactors.parse(
      const {
        'users': [
          {
            'id': 3,
            'username': 'sam',
            'name': 'Sam Saffron',
            'avatar_template': '/user_avatar/meta/sam/{size}/1.png',
            'reaction': 'clap',
          },
        ],
        'total_rows': 4,
      },
      channelId: 9,
      messageId: 44,
      siteUrl: _siteUrl,
      filter: 'clap',
    );

    expect(page.channelId, 9);
    expect(page.messageId, 44);
    expect(page.filter, 'clap');
    expect(page.total, 4);
    expect(page.reactors.single.username, 'sam');
    expect(page.reactors.single.displayName, 'Sam Saffron');
    expect(page.reactors.single.reaction, 'clap');
    expect(page.storeId, ChatMessageReactors.key(9, 44, 'clap'));
  });

  test('bounds a hostile chat reactor response', () {
    final page = ChatMessageReactors.parse(
      {
        'users': [
          for (var index = 0; index < 100; index++)
            {'id': index + 1, 'username': 'user-$index', 'reaction': 'heart'},
        ],
        'total_rows': 100,
      },
      channelId: 9,
      messageId: 44,
      siteUrl: _siteUrl,
    );

    expect(page.reactors, hasLength(ChatMessageReactors.maximumPageSize));
    expect(page.total, 100);
  });
}
