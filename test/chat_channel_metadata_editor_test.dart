import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_editor.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_controller_test.dart' as fixtures;
import 'support/fakes.dart';

void main() {
  for (final editSlug in [false, true]) {
    testWidgets(
      'saving only the ${editSlug ? 'slug' : 'name'} preserves a live '
      '${editSlug ? 'name' : 'slug'} edit received while the dialog is open',
      (tester) async {
        final original = fixtures.channel(
          9,
          slug: 'bugs',
          description: 'Original description',
        );
        final api = _EditingApi(original);
        final subject = fixtures.build(
          api: api,
          currentUser: const DiscourseUser(
            id: 7,
            username: 'reader',
            staff: true,
          ),
        );
        addTearDown(subject.chat.dispose);
        await subject.chat.loadChannels(fixtures.site);
        final tracker = fixtures.attachTracker(subject.chat);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Builder(
                builder: (context) => DButton(
                  label: const Text('Edit'),
                  onPressed: () => showChatChannelDetailsEditor(
                    context: context,
                    chat: subject.chat,
                    siteUrl: fixtures.site,
                    channel: original,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(
            ValueKey(
              editSlug ? 'chat-channel-slug-input' : 'chat-channel-title-input',
            ),
          ),
          editSlug ? 'local-slug' : 'Local title',
        );
        api.remote = original.withRemoteMetadata(
          title: editSlug ? 'Remote title' : original.title,
          slug: editSlug ? original.slug! : 'remote-slug',
          description: 'Remote description',
        );
        tracker.deliverPluginMessage('/chat/channel-edits', {
          'chat_channel_id': 9,
          'name': api.remote.title,
          'slug': api.remote.slug,
          'description': api.remote.description,
        }, messageId: 1);
        await tester.pumpAndSettle();
        expect(subject.chat.channel(fixtures.site, 9), api.remote);
        await tester.tap(
          find.byKey(const ValueKey('chat-channel-details-save')),
        );
        await tester.pumpAndSettle();

        final saved = subject.chat.channel(fixtures.site, 9)!;
        expect(saved.title, editSlug ? 'Remote title' : 'Local title');
        expect(saved.slug, editSlug ? 'local-slug' : 'remote-slug');
        expect(saved.description, 'Remote description');
        final sent = api.chatChannelMetadataUpdates.single;
        expect(sent.name, editSlug ? isNull : 'Local title');
        expect(sent.slug, editSlug ? 'local-slug' : isNull);
        expect(sent.description, isNull);
        expect(
          find.byKey(const ValueKey('chat-channel-details-dialog')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

/// Core's update service defaults omitted fields to the current server model.
class _EditingApi extends FakeDiscourseApi {
  _EditingApi(ChatChannel original)
    : remote = original,
      super(
        chatChannelsBySite: {
          fixtures.site: ChatChannels(public: [original]),
        },
        chatChannelsById: {9: original},
      );

  ChatChannel remote;

  @override
  Future<ChatChannel> updateChatChannel({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String? name,
    String? slug,
    String? description,
    bool? threadingEnabled,
    String? clientId,
  }) async {
    await super.updateChatChannel(
      siteUrl: siteUrl,
      apiKey: apiKey,
      channelId: channelId,
      name: name,
      slug: slug,
      description: description,
      threadingEnabled: threadingEnabled,
      clientId: clientId,
    );
    return remote = remote.withRemoteMetadata(
      title: name ?? remote.title,
      slug: slug ?? remote.slug!,
      description: description ?? remote.description,
    );
  }
}
