import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post_flag.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_tile.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/post_flag_editor.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/chat_shell.dart';
import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _catalog = SitePostActionCatalog(
  postFlags: [
    PostFlagType(
      id: 7,
      nameKey: 'spam',
      name: 'Spam',
      description: 'This message is an advertisement.',
      appliesTo: ['Chat::Message'],
    ),
  ],
);
const _channel = ChatChannel(
  id: 9,
  title: 'Support',
  kind: ChatChannelKind.category,
  canFlag: true,
  membership: ChatMembership(following: true),
);
const _message = ChatMessage(
  id: 7,
  channelId: 9,
  raw: 'Advertisement',
  cooked: '<p>Advertisement</p>',
  author: ChatMessageAuthor(id: 99, username: 'advertiser'),
  availableFlags: ['spam'],
);
final _user = DiscourseUser(
  id: 1,
  username: 'reader',
  plugins: PluginData.none.withValue(
    chatCurrentUserDataKey,
    const ChatCurrentUser(hasChatEnabled: true, canDirectMessage: true),
  ),
);

enum _Operation { unchanged, failedReconnect, failedDisconnect }

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final operation in _Operation.values) {
    testWidgets(
      'a Chat flag form ${operation == _Operation.unchanged ? 'submits in its original session' : 'rejects ${operation.name} session replacement'}',
      (tester) async {
        final site = instance('meta.discourse.org').copyWith(user: _user);
        final store = _FailingStore([site]);
        final api = FakeDiscourseApi(
          user: _user,
          feeds: const {'/latest.json': []},
          categoryPostActionCatalog: _catalog,
          chatChannelsBySite: const {
            _site: ChatChannels(public: [_channel], direct: []),
          },
          chatMessagesByKey: const {
            '9': (
              messages: [_message],
              canLoadMorePast: false,
              canLoadMoreFuture: false,
              targetMessageId: null,
            ),
          },
        );
        await pumpShell(
          tester,
          defaultTargetPlatform == TargetPlatform.macOS ? desktop : phone,
          instances: [site],
          store: store,
          api: api,
          authenticator: FakeAuthenticator()..keys[_site] = 'key',
        );
        final shell = ShellScope.read(
          tester.element(find.byType(MainContent).first),
        );
        await shell.loadCategories(_site);
        await shell.chat.loadChannels(_site);
        expect(shell.openChatChannel(9), isTrue);
        await tester.pumpAndSettle();
        expect(find.byType(ChatMessageTile), findsOneWidget);
        final actions = tester.state(
          find.byWidgetPredicate(
            (widget) => widget.runtimeType.toString() == '_ChatMessageActions',
          ),
        );
        if (defaultTargetPlatform == TargetPlatform.macOS) {
          final pointer = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await pointer.addPointer(location: Offset.zero);
          addTearDown(pointer.removePointer);
          await pointer.moveTo(tester.getCenter(find.byType(ChatMessageTile)));
          await tester.pump();
          await tester.tap(
            find.byTooltip('More message actions').hitTestable(),
          );
        } else {
          await tester.longPress(find.byType(ChatMessageTile));
        }
        await tester.pumpAndSettle();
        await tester.tap(find.text('Flag'));
        await tester.pumpAndSettle();
        final form = find.byType(PostFlagEditor);
        final formState = tester.state(form);
        final lease = shell.chat.captureSession(_site);
        expect(form, findsOneWidget);
        expect(find.text('Spam'), findsOneWidget);

        if (operation != _Operation.unchanged) {
          store.failSignedOut = true;
          if (operation == _Operation.failedDisconnect) {
            expect(
              await tester.runAsync(() => shell.disconnectInstance(_site)),
              isFalse,
            );
          } else {
            await tester.runAsync(shell.connectCurrentInstance);
          }
          expect(shell.currentInstance?.user?.id, _user.id);
          expect(lease.isCurrent, isFalse);
          expect(shell.chatRecords.read<ChatMessage>(_site, 7), isNull);
          await tester.pump();
          expect(tester.state(form), same(formState));
          expect(actions.mounted, isFalse);
          // Re-read the same real channel/message IDs through the API in the
          // restored account, as happens when its channel is visited again.
          await shell.chat.loadChannels(_site);
          await shell.chat.openChannel(_site, 9, force: true);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(shell.chatRecords.read<ChatMessage>(_site, 7), isNotNull);
          expect(tester.state(form), same(formState));
          expect(api.chatMessagesRequested.length, greaterThan(1));
        }

        await tester.tap(find.byKey(const ValueKey('post-flag-submit')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        if (operation == _Operation.unchanged) {
          await tester.pumpAndSettle();
          expect(api.chatMessagesFlagged, [
            (channelId: 9, messageId: 7, flagTypeId: 7, message: null),
          ]);
          expect(form, findsNothing);
        } else {
          expect(api.chatMessagesFlagged, isEmpty);
          expect(form, findsOneWidget);
          expect(
            find.text(
              'Your connection changed. Reopen the flag form and try again.',
            ),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
        TargetPlatform.macOS,
      }),
    );
  }
}

class _FailingStore extends FakeInstanceStore {
  _FailingStore(super.instances);
  bool failSignedOut = false;

  @override
  Future<void> save(List<DiscourseInstance> instances) {
    if (failSignedOut &&
        instances.any((site) => site.url == _site && site.user == null)) {
      return Future.error(StateError('Account snapshot storage unavailable'));
    }
    return super.save(instances);
  }
}
