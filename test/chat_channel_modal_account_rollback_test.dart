import 'dart:async';

import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_info_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/chat_shell.dart';
import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _description = '    Updated description\n';
final _user = _staff(1);
DiscourseUser _staff(int id) => DiscourseUser(
  id: id,
  username: 'staff$id',
  staff: true,
  plugins: PluginData.none.withValue(
    chatCurrentUserDataKey,
    const ChatCurrentUser(hasChatEnabled: true, canDirectMessage: true),
  ),
);

enum _Action { details, close, reopen }

enum _Operation {
  unchanged,
  reconnect,
  failedReconnect,
  failedDisconnect,
  failedReconnectWhileSaving,
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final action in _Action.values) {
    for (final operation in _Operation.values) {
      testWidgets(
        'the ${action.name} modal ${operation == _Operation.unchanged ? 'saves in its opening session' : 'rejects ${operation.name} session replacement'}',
        (tester) async {
          final channel = ChatChannel(
            id: 9,
            title: 'Support',
            slug: 'support',
            description: 'Original description',
            kind: ChatChannelKind.category,
            status: action == _Action.reopen
                ? ChatChannelStatus.closed
                : ChatChannelStatus.open,
            membership: const ChatMembership(following: true),
          );
          final site = instance('meta.discourse.org').copyWith(user: _user);
          final store = _FailingStore([site]);
          final gate = operation == _Operation.failedReconnectWhileSaving
              ? Completer<void>()
              : null;
          addTearDown(() {
            if (gate != null && !gate.isCompleted) gate.complete();
          });
          final api = _ModalApi(channel, gate: gate);
          await pumpShell(
            tester,
            defaultTargetPlatform == TargetPlatform.macOS ? desktop : phone,
            instances: [site],
            store: store,
            api: api,
            authenticator: FakeAuthenticator()..keys[_site] = 'key',
          );
          final shell = ShellScope.read(tester.element(primaryMainContent));
          await shell.chat.loadChannels(_site);
          expect(shell.openChatChannel(9), isTrue);
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('content-header-title-action')),
          );
          await tester.pumpAndSettle();
          expect(find.byType(ChatChannelInfoView), findsOneWidget);
          final source = tester.element(find.byType(ChatChannelInfoView));
          final actionButton = find.byKey(
            ValueKey(
              action == _Action.details
                  ? 'chat-channel-edit-details'
                  : 'chat-channel-toggle-status',
            ),
          );
          await tester.ensureVisible(actionButton);
          await tester.pumpAndSettle();
          await tester.tap(actionButton);
          await tester.pumpAndSettle();
          final dialog = find.byWidgetPredicate(
            (widget) =>
                widget.runtimeType.toString() ==
                (action == _Action.details
                    ? '_ChannelDetailsDialog'
                    : '_ChannelStatusDialog'),
          );
          final state = tester.state(dialog);
          final lease = shell.chat.captureSession(_site);
          if (action == _Action.details) {
            await tester.enterText(
              find.byKey(const ValueKey('chat-channel-title-input')),
              'Updated name',
            );
            await tester.enterText(
              find.byKey(const ValueKey('chat-channel-description-input')),
              _description,
            );
            await tester.pump();
          }
          final confirm = find.byKey(
            ValueKey(
              action == _Action.details
                  ? 'chat-channel-details-save'
                  : 'chat-channel-status-confirm',
            ),
          );
          if (gate != null) {
            await tester.tap(confirm);
            await tester.pump();
            expect(
              action == _Action.details
                  ? api.chatChannelMetadataUpdates
                  : api.chatChannelStatusesUpdated,
              hasLength(1),
            );
          }

          if (operation != _Operation.unchanged) {
            store.failSignedOut = operation != _Operation.reconnect;
            if (operation == _Operation.failedDisconnect) {
              expect(
                await tester.runAsync(() => shell.disconnectInstance(_site)),
                isFalse,
              );
            } else {
              await tester.runAsync(shell.connectCurrentInstance);
            }
            expect(
              shell.currentInstance?.user?.id,
              operation == _Operation.reconnect ? 2 : 1,
            );
            expect(lease.isCurrent, isFalse);
            await tester.pump();
            expect(tester.state(dialog), same(state));
            if (operation == _Operation.reconnect) {
              expect(source.mounted, isFalse);
            }
            await shell.chat.loadChannels(_site);
            await shell.chat.openChannel(_site, 9, force: true);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            expect(shell.chat.channel(_site, 9), isNotNull);
            expect(tester.state(dialog), same(state));
          }

          if (gate == null) {
            await tester.tap(confirm);
          } else {
            gate.complete();
          }
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          if (operation == _Operation.unchanged) {
            await tester.pumpAndSettle();
            if (action == _Action.details) {
              final sent = api.chatChannelMetadataUpdates.single;
              expect(
                (sent.name, sent.slug, sent.description),
                ('Updated name', null, _description),
              );
            } else {
              expect(api.chatChannelStatusesUpdated, [
                (
                  channelId: 9,
                  status: action == _Action.close
                      ? ChatChannelStatus.closed
                      : ChatChannelStatus.open,
                ),
              ]);
            }
            expect(dialog, findsNothing);
          } else {
            if (gate == null) {
              expect(api.chatChannelMetadataUpdates, isEmpty);
              expect(api.chatChannelStatusesUpdated, isEmpty);
            } else {
              expect(
                action == _Action.details
                    ? api.chatChannelMetadataUpdates
                    : api.chatChannelStatusesUpdated,
                hasLength(1),
              );
            }
            expect(dialog, findsOneWidget);
            expect(
              find.text(
                'Your connection changed. Reopen the action and try again.',
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
}

class _ModalApi extends FakeDiscourseApi {
  _ModalApi(ChatChannel channel, {Completer<void>? gate})
    : super(
        user: _user,
        chatChannelUpdateGate: gate,
        chatChannelStatusGate: gate,
        feeds: const {'/latest.json': []},
        chatChannelsBySite: {
          _site: ChatChannels(public: [channel], direct: const []),
        },
        chatChannelsById: {9: channel},
        chatMessagesByKey: const {
          '9': (
            messages: [],
            canLoadMorePast: false,
            canLoadMoreFuture: false,
            targetMessageId: null,
          ),
        },
        chatChannelUpdateResponse: channel.withRemoteMetadata(
          title: 'Updated name',
          slug: 'support',
          description: _description,
        ),
        chatChannelStatusResponse: channel.withRemoteStatus(
          channel.status == ChatChannelStatus.open
              ? ChatChannelStatus.closed
              : ChatChannelStatus.open,
        ),
      );

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => apiKey == 'api-key' ? _staff(2) : _user;
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
