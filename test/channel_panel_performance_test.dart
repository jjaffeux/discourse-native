import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/plugin_data.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_composer.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_tile.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_shell.dart';
import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';

Set<RenderObject> _artwork(Finder root) {
  final result = <RenderObject>{};
  void collect(RenderObject object) {
    if (!object.isRepaintBoundary) result.add(object);
    object.visitChildren(collect);
  }

  for (final element in root.evaluate()) {
    collect(element.findRenderObject()!);
  }
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const notifications = MethodChannel(
    'org.discourse.native/notification_opens',
  );
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifications, (_) async => null),
  );
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifications, null),
  );

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.iOS,
    TargetPlatform.android,
  ]) {
    testWidgets(
      'channel paint stays isolated during scrolling and sheet motion on $platform',
      (tester) async {
        const user = DiscourseUser(id: 1, username: 'reader');
        final config = SiteConfig(
          plugins: PluginData.none.withValue(
            chatSettingsDataKey,
            const ChatSettings(chatEnabled: true, publicChannelsEnabled: true),
          ),
        );
        final api = FakeDiscourseApi(
          user: user,
          totals: chatNotificationTotals(),
          siteConfigs: {_site: config},
          feeds: const {'/latest.json': []},
          chatChannelsBySite: const {
            _site: ChatChannels(
              public: [
                ChatChannel(
                  id: 10,
                  title: 'Support',
                  kind: ChatChannelKind.category,
                  membership: ChatMembership(following: true),
                ),
              ],
            ),
          },
          chatMessagesByKey: {
            '10': (
              messages: [
                for (var id = 1; id <= 80; id++)
                  ChatMessage(
                    id: id,
                    channelId: 10,
                    cooked:
                        '<p>Message $id with <strong>formatted text</strong> in a busy channel.</p>',
                    author: ChatMessageAuthor(
                      id: id % 3 + 1,
                      username: 'reader${id % 3}',
                    ),
                    createdAt: DateTime.utc(
                      2026,
                      10,
                      1,
                    ).add(Duration(minutes: id)),
                  ),
              ],
              canLoadMorePast: false,
              canLoadMoreFuture: false,
              targetMessageId: null,
            ),
          },
        );
        await pumpShell(
          tester,
          platform == TargetPlatform.macOS ? desktop : phone,
          instances: [
            instance('meta.discourse.org').copyWith(user: user, config: config),
          ],
          authenticator: FakeAuthenticator()..keys[_site] = 'key',
          api: api,
        );
        final shell = ShellScope.read(tester.element(primaryMainContent));
        if (platform != TargetPlatform.macOS) {
          shell.selectMobilePanel('chat');
          await tester.pumpAndSettle();
        }
        shell.openChatChannel(10);
        await tester.pumpAndSettle();
        final stream = find.byType(ChatMessageStream);
        expect(stream, findsOneWidget);
        final scrollable = find.descendant(
          of: stream,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
          ),
        );
        // Let the navigation chrome finish changing its compact state before
        // observing artwork that remains unchanged throughout the gesture.
        tester.state<ScrollableState>(scrollable).position.jumpTo(500);
        await tester.pumpAndSettle();
        final composer = _artwork(find.byType(ChatComposer));
        expect(composer, isNotEmpty);
        var composerPaints = 0;
        var channelPaints = 0;
        var totalPaints = 0;
        final previous = debugOnProfilePaint;
        Set<RenderObject> channel = {};
        debugOnProfilePaint = (object) {
          previous?.call(object);
          totalPaints++;
          if (composer.contains(object)) composerPaints++;
          if (channel.contains(object)) channelPaints++;
        };
        try {
          for (var frame = 0; frame < 12; frame++) {
            final position = tester.state<ScrollableState>(scrollable).position;
            final before = position.pixels;
            position.pointerScroll(4);
            await tester.pump(const Duration(milliseconds: 16));
            expect(
              tester.state<ScrollableState>(scrollable).position.pixels,
              greaterThan(before),
            );
          }
          await tester.pumpAndSettle();
          debugPrint(
            'CHANNEL_PAINT $platform scroll composer=$composerPaints total=$totalPaints',
          );
          expect(totalPaints, greaterThan(0));
          expect(composerPaints, 0);
          if (platform != TargetPlatform.macOS) {
            channel = _artwork(find.byType(ChatChannelView));
            final handle = find.byKey(const ValueKey('sheet-drag-handle'));
            final origin = tester.getCenter(handle);
            final gesture = await tester.startGesture(origin);
            await gesture.moveBy(const Offset(0, 24));
            await tester.pump();
            channelPaints = totalPaints = 0;
            for (var frame = 0; frame < 12; frame++) {
              await gesture.moveBy(const Offset(0, 4));
              await tester.pump(const Duration(milliseconds: 16));
            }
            expect(tester.getCenter(handle).dy, greaterThan(origin.dy + 40));
            debugPrint(
              'CHANNEL_PAINT $platform drag channel=$channelPaints total=$totalPaints',
            );
            expect(totalPaints, greaterThan(0));
            expect(channelPaints, 0);
            await gesture.cancel();
            await tester.pumpAndSettle();
            expect(tester.getCenter(handle).dy, closeTo(origin.dy, .01));
          }
          final visibleMessage = tester.widget<ChatMessageTile>(
            find.byType(ChatMessageTile).hitTestable().first,
          );
          shell.chatRecords.put(
            _site,
            shell.chatRecords
                .read<ChatMessage>(_site, visibleMessage.messageId)!
                .withContentOf(
                  ChatMessage(
                    id: visibleMessage.messageId,
                    channelId: 10,
                    cooked: '<p>Updated channel message</p>',
                    author: const ChatMessageAuthor(id: 2, username: 'reader2'),
                  ),
                ),
          );
          await tester.pumpAndSettle();
          expect(renderedText('Updated channel message'), findsOneWidget);
          shell.handleBack();
          await tester.pumpAndSettle();
          expect(find.byType(ChatChannelView), findsNothing);
          if (platform != TargetPlatform.macOS) {
            shell.openChatChannel(10);
            await tester.pump();
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 32));
            final handle = find.byKey(const ValueKey('sheet-drag-handle'));
            final enteringTop = tester.getCenter(handle).dy;
            // Header and dock geometry still animate during entrance. The
            // already laid-out message artwork should stay cached throughout.
            channel = _artwork(find.byType(ChatMessageTile));
            expect(channel, isNotEmpty);
            channelPaints = totalPaints = 0;
            for (var frame = 0; frame < 16; frame++) {
              await tester.pump(const Duration(milliseconds: 16));
            }
            debugPrint(
              'CHANNEL_PAINT $platform entrance channel=$channelPaints total=$totalPaints',
            );
            expect(tester.getCenter(handle).dy, lessThan(enteringTop));
            expect(channelPaints, 0);
            expect(
              _artwork(find.byType(ChatMessageTile)),
              containsAll(channel),
            );
            await tester.pumpAndSettle();
            channel = _artwork(find.byType(ChatChannelView));
            final gesture = await tester.startGesture(tester.getCenter(handle));
            await gesture.moveBy(const Offset(0, 24));
            await tester.pump();
            await gesture.moveBy(const Offset(0, 240));
            await tester.pump();
            channelPaints = totalPaints = 0;
            await gesture.up();
            await tester.pumpAndSettle(const Duration(milliseconds: 16));
            debugPrint(
              'CHANNEL_PAINT $platform dismissal channel=$channelPaints total=$totalPaints',
            );
            expect(channelPaints, 0);
            expect(find.byType(ChatChannelView), findsNothing);
          }
          expect(tester.takeException(), isNull);
        } finally {
          debugOnProfilePaint = previous;
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }
}
