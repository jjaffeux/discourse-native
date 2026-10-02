import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_editor.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_controller_test.dart' as fixtures;

const _staff = DiscourseUser(id: 7, username: 'reader', staff: true);
const _site = fixtures.site;
final _save = find.byKey(const ValueKey('chat-channel-details-save'));
final _description = find.byKey(
  const ValueKey('chat-channel-description-input'),
);

void main() {
  for (final editSlug in [false, true]) {
    testWidgets('a channel with a 400-character description can change its '
        '${editSlug ? 'slug' : 'name'}', (tester) async {
      final description = 'a' * 400;
      final original = fixtures.channel(
        9,
        slug: 'bugs',
        description: description,
      );
      final subject = fixtures.build(
        currentUser: _staff,
        channels: {
          _site: ChatChannels(public: [original]),
        },
        channelUpdateResponse: fixtures.channel(
          9,
          title: editSlug ? 'Bugs' : 'Renamed',
          slug: editSlug ? 'renamed' : 'bugs',
          description: description,
        ),
      );
      addTearDown(subject.chat.dispose);
      await subject.chat.loadChannels(_site);
      await _open(
        tester,
        (context) => showChatChannelDetailsEditor(
          context: context,
          chat: subject.chat,
          siteUrl: _site,
          channel: original,
        ),
      );
      expect(
        tester.widget<DTextarea>(_description).controller!.text,
        description,
      );
      await tester.enterText(
        find.byKey(
          ValueKey(
            editSlug ? 'chat-channel-slug-input' : 'chat-channel-title-input',
          ),
        ),
        editSlug ? 'renamed' : 'Renamed',
      );
      await tester.pumpAndSettle();
      expect(tester.widget<DButton>(_save).onPressed, isNotNull);
      await tester.tap(_save);
      await tester.pumpAndSettle();
      final sent = subject.api.chatChannelMetadataUpdates.single;
      expect(sent.name, editSlug ? 'Bugs' : 'Renamed');
      expect(sent.slug, editSlug ? 'renamed' : 'bugs');
      expect(sent.description, isNull);
      expect(subject.chat.channel(_site, 9)!.description, description);
      expect(
        find.byKey(const ValueKey('chat-channel-details-dialog')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final description in ['a' * 500, '🧵' * 500, '']) {
    testWidgets(
      'a changed description with ${description.runes.length} '
      'server characters saves intact (${description.isEmpty ? 'clear' : description.runes.first})',
      (tester) async {
        final original = fixtures.channel(
          9,
          slug: 'bugs',
          description: 'Original',
        );
        final subject = fixtures.build(
          currentUser: _staff,
          channels: {
            _site: ChatChannels(public: [original]),
          },
          channelUpdateResponse: fixtures.channel(
            9,
            slug: 'bugs',
            description: description,
          ),
        );
        addTearDown(subject.chat.dispose);
        await subject.chat.loadChannels(_site);
        await _open(
          tester,
          (context) => showChatChannelDetailsEditor(
            context: context,
            chat: subject.chat,
            siteUrl: _site,
            channel: original,
          ),
        );
        await tester.enterText(_description, description);
        await tester.pumpAndSettle();
        expect(
          tester.widget<DTextarea>(_description).controller!.text,
          description,
        );
        expect(tester.widget<DButton>(_save).onPressed, isNotNull);
        await tester.tap(_save);
        await tester.pumpAndSettle();
        expect(
          subject.api.chatChannelMetadataUpdates.single.description,
          description,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a changed description exceeding 500 scalars reports its bound', (
    tester,
  ) async {
    final original = fixtures.channel(9, slug: 'bugs');
    final subject = fixtures.build(
      currentUser: _staff,
      channels: {
        _site: ChatChannels(public: [original]),
      },
    );
    addTearDown(subject.chat.dispose);
    await subject.chat.loadChannels(_site);
    await _open(
      tester,
      (context) => showChatChannelDetailsEditor(
        context: context,
        chat: subject.chat,
        siteUrl: _site,
        channel: original,
      ),
    );
    // Each composed grapheme contains two scalars, as Ruby String.length counts it.
    await tester.enterText(_description, 'e\u0301' * 251);
    await tester.pumpAndSettle();
    expect(tester.widget<DButton>(_save).onPressed, isNull);
    expect(
      tester.widget<DTextarea>(_description).errorText,
      'The channel description cannot exceed 500 characters.',
    );
    expect(subject.api.chatChannelMetadataUpdates, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final valid in [
    'a' * 500,
    '🧵' * 500,
    '🇫🇷' * 250,
    '👩🏽‍💻' * 125,
    'e\u0301' * 250,
  ]) {
    test(
      'controller description bound uses 500 Unicode scalars (${valid.runes.first})',
      () async {
        final original = fixtures.channel(9, slug: 'bugs');
        final subject = fixtures.build(
          currentUser: _staff,
          channels: {
            _site: ChatChannels(public: [original]),
          },
          channelUpdateResponse: fixtures.channel(
            9,
            slug: 'bugs',
            description: valid,
          ),
        );
        addTearDown(subject.chat.dispose);
        await subject.chat.loadChannels(_site);
        expect(
          await subject.chat.updateChannelMetadata(
            _site,
            9,
            description: '$valid!',
          ),
          'The channel description cannot exceed 500 characters.',
        );
        expect(subject.api.chatChannelMetadataUpdates, isEmpty);
        expect(
          await subject.chat.updateChannelMetadata(
            _site,
            9,
            description: valid,
          ),
          isNull,
        );
        expect(
          subject.api.chatChannelMetadataUpdates.single.description,
          valid,
        );
      },
    );
  }
}

Future<void> _open(
  WidgetTester tester,
  Future<void> Function(BuildContext) open,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return DButton(
              label: const Text('Edit'),
              onPressed: () => open(context),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('Edit'));
  await tester.pumpAndSettle();
}
