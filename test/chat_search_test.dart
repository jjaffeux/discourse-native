import 'package:discourse_native/src/plugins/chat/chat_search.dart';
import 'package:flutter_test/flutter_test.dart';

const site = 'https://example.com';

Map<String, dynamic> result(int id, {int channelId = 9}) => {
  'id': id,
  'chat_channel_id': channelId,
  'cooked': '<p>message $id</p>',
  'excerpt': 'message $id',
  'created_at': '2026-08-25T10:00:00Z',
  'user': {'id': 2, 'username': 'sam'},
  'channel': {
    'id': channelId,
    'title': 'Bugs',
    'chatable_type': 'Category',
    'chatable': {'color': '0088CC'},
  },
};

void main() {
  test('parses message, channel, thread context, and paging metadata', () {
    final json = result(40)
      ..['thread_id'] = 7
      ..['thread_title'] = 'Search design';

    final page = ChatSearchPage.fromJson({
      'messages': [json],
      'meta': const {'has_more': true, 'limit': 20, 'offset': 40},
    }, site);

    expect(page.hits.single.message.id, 40);
    expect(page.hits.single.channel.title, 'Bugs');
    expect(page.hits.single.threadTitle, 'Search design');
    expect(page.hits.single.excerpt, 'message 40');
    expect(page.hasMore, isTrue);
    expect(page.limit, 20);
    expect(page.offset, 40);
    expect(page.consumedCount, 1);
  });

  test('bounds work and drops partial or mismatched result records', () {
    final messages = [for (var id = 1; id <= 45; id++) result(id)];
    messages[0].remove('channel');
    messages[1]['chat_channel_id'] = 10;

    final page = ChatSearchPage.fromJson({'messages': messages}, site);

    expect(page.hits.map((hit) => hit.id), [
      for (var id = 3; id <= ChatSearchPage.maximumPageSize; id++) id,
    ]);
    expect(page.limit, ChatSearchPage.defaultPageSize);
    expect(page.offset, 0);
    expect(page.consumedCount, ChatSearchPage.maximumPageSize);
  });
}
