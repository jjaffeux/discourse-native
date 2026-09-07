import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/user_flair.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_pin.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://meta.example';
const _bot = <String, dynamic>{
  'id': -4000,
  'username': 'helper',
  'flair_group_id': 12,
  'flair_name': 'discourse_ai_users',
  'flair_url': 'discourse-ai',
  'flair_color': 'ffffff',
  'flair_bg_color': '0088cc',
};

void main() {
  test('keeps the server flair and negative AI account id', () {
    final author = ChatMessageAuthor.fromJson(_bot, _site);
    expect(author.id, -4000);
    expect(
      author.flair,
      const UserFlair(
        groupId: 12,
        name: 'discourse_ai_users',
        url: 'discourse-ai',
        color: 'ffffff',
        backgroundColor: '0088cc',
      ),
    );
  });

  test('resolves image flairs without treating icon names as paths', () {
    for (final (input, expected) in [
      ('/uploads/flair.png', '$_site/uploads/flair.png'),
      ('//cdn.example/flair.svg', 'https://cdn.example/flair.svg'),
      ('https://cdn.example/flair.png', 'https://cdn.example/flair.png'),
      ('robot', 'robot'),
    ]) {
      expect(
        UserFlair.fromJson({..._bot, 'flair_url': input}, _site)?.url,
        expected,
      );
    }
  });

  test('older servers and absent or malformed groups have no badge', () {
    for (final value in [
      null,
      false,
      3,
      <Object?>[],
      'bad',
      <String, dynamic>{},
      {..._bot, 'flair_group_id': null},
      {..._bot, 'flair_group_id': 0},
      {..._bot, 'flair_group_id': -1},
      {..._bot, 'flair_group_id': <Object?>[]},
      {..._bot, 'flair_url': <String, dynamic>{}, 'flair_bg_color': false},
      {..._bot, 'flair_url': '', 'flair_bg_color': ''},
    ]) {
      expect(UserFlair.fromJson(value, _site), isNull, reason: '$value');
    }
    expect(
      ChatMessageAuthor.fromJson(const {
        'id': 1,
        'username': 'sam',
      }, _site).flair,
      isNull,
    );
  });

  test('supports background-only flairs and optional names', () {
    final flair = UserFlair.fromJson({
      'flair_group_id': 2,
      'flair_bg_color': '#abc',
    }, _site)!;
    expect(flair.url, isNull);
    expect(flair.backgroundColor, '#abc');
    expect(flair.label, 'Group flair');
  });

  test('flair value equality covers every field', () {
    final flair = UserFlair.fromJson(_bot, _site)!;
    final sameFlair = UserFlair.fromJson({..._bot}, _site)!;
    expect(flair, sameFlair);
    expect(flair.hashCode, sameFlair.hashCode);
    for (final entry in {
      'flair_group_id': 13,
      'flair_name': 'support',
      'flair_url': 'robot',
      'flair_color': '000000',
      'flair_bg_color': 'ffffff',
    }.entries) {
      expect(
        UserFlair.fromJson({..._bot, entry.key: entry.value}, _site),
        isNot(flair),
      );
    }
  });

  test('nested replies, thread authors and pinned authors retain flair', () {
    final flair = UserFlair.fromJson(_bot, _site);
    final reply = ChatReplyTo.fromJson(const {'id': 6, 'user': _bot}, _site);
    final preview = ChatThreadPreview.fromJson({
      'id': 3,
      'reply_count': 1,
      'preview': {
        'last_reply_user': _bot,
        'participant_users': [_bot],
      },
    }, _site)!;
    final original = ChatThreadOriginalMessage.fromJson(const {
      'id': 1,
      'user': _bot,
    }, _site)!;
    final pin = ChatPin.fromJson(const {
      'id': 5,
      'message': {'id': 1, 'user': _bot},
      'pinned_by': _bot,
    }, _site);
    expect(reply.flair, flair);
    expect(preview.lastReplyUser?.flair, flair);
    expect(preview.participantUsers.single.flair, flair);
    expect(original.author.flair, flair);
    expect(pin.message.author.flair, flair);
    expect(pin.pinnedBy.flair, flair);
    expect(
      reply,
      isNot(
        ChatReplyTo.fromJson(const {
          'id': 6,
          'user': {'id': -4000, 'username': 'helper'},
        }, _site),
      ),
    );
  });

  test('flair-only additions, changes and removals notify message readers', () {
    ChatMessage message(Map<String, dynamic> user) => ChatMessage.fromJson({
      'id': 7,
      'chat_channel_id': 9,
      'user': user,
      'cooked': '<p>Hello</p>',
    }, _site);
    final withoutFlair = {..._bot, 'flair_group_id': null};
    final store = Store()..put(_site, message(withoutFlair));
    final ref = store.ref<ChatMessage>(_site, 7);
    var changes = 0;
    ref.addListener(() => changes++);
    store.put(_site, message(_bot));
    expect(changes, 1);
    expect(ref.value!.author.flair?.url, 'discourse-ai');
    store.put(_site, message({..._bot}));
    expect(changes, 1);
    store.put(_site, message({..._bot, 'flair_url': 'robot'}));
    expect(changes, 2);
    expect(ref.value!.author.flair?.url, 'robot');
    store.put(_site, message(withoutFlair));
    expect(changes, 3);
    expect(ref.value!.author.flair, isNull);
  });
}
