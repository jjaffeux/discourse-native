import 'dart:async';
import 'dart:convert';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_composer.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_tile.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_preview_body.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/gifs/gifs_contract.dart';
import 'package:discourse_native/src/plugins/gifs/gifs_settings.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_settings.dart';
import 'package:discourse_native/src/shell/composer_link.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/emoji.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_image.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/bundled_plugins.dart';
import 'support/chat_shell.dart';
import 'support/fakes.dart';
import 'support/media_pipeline.dart';

const _site = 'https://chat.example';
final _gifsConfig = SiteConfig(
  plugins: PluginData.none
      .withValue(gifsSettingsDataKey, const GifsSettings(enabled: true))
      .withValue(
        localDatesSettingsDataKey,
        const LocalDatesSettings(enabled: true),
      ),
);
const _gif = GifResult(
  title: 'Party parrot',
  url: 'https://cdn.example/party.webp',
  width: 320,
  height: 180,
);

void main() {
  group('draft editing, layout, and uploads', () {
    testWidgets('follows the desktop reading lane width', (tester) async {
      final fixture = await _fixture(
        pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
      );
      addTearDown(fixture.shell.dispose);
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await tester.binding.setSurfaceSize(const Size(1200, 600));
      try {
        await tester.pumpWidget(_TestView(shell: fixture.shell));
        await tester.pumpAndSettle();

        final bar = find.byKey(const ValueKey('chat-composer'));
        expect(tester.getSize(bar).width, 825);
        expect(tester.getTopLeft(bar).dx, 187.5);

        await tester.binding.setSurfaceSize(const Size(700, 600));
        await tester.pumpAndSettle();

        expect(tester.getSize(bar).width, 676);
        expect(tester.getTopLeft(bar).dx, 12);
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
        await tester.binding.setSurfaceSize(null);
      }
    });

    testWidgets('Command-E wraps the selected chat text in backticks', (
      tester,
    ) async {
      final fixture = await _fixture(
        pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
      );
      addTearDown(fixture.shell.dispose);
      await tester.pumpWidget(_TestView(shell: fixture.shell));
      await tester.pumpAndSettle();

      final controller = _field(tester).controller!;
      controller.value = const TextEditingValue(
        text: 'format me',
        selection: TextSelection(baseOffset: 0, extentOffset: 6),
      );
      _field(tester).focusNode!.requestFocus();
      await tester.pump();

      await _pressCommandE(tester);

      expect(controller.text, '`format` me');
      expect(
        controller.selection,
        const TextSelection(baseOffset: 1, extentOffset: 7),
      );
    });

    testWidgets('Command-L links the selected chat text', (tester) async {
      final fixture = await _fixture(
        pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
      );
      addTearDown(fixture.shell.dispose);
      await tester.pumpWidget(_TestView(shell: fixture.shell));
      await tester.pumpAndSettle();

      final controller = _field(tester).controller!;
      controller.value = const TextEditingValue(
        text: 'format me',
        selection: TextSelection(baseOffset: 0, extentOffset: 6),
      );
      _field(tester).focusNode!.requestFocus();
      await tester.pump();

      await _pressCommandL(tester);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('composer-link-dialog')),
        findsOneWidget,
      );
      final anchor = tester.widget<TextField>(
        find.byKey(const ValueKey('composer-link-anchor')),
      );
      expect(anchor.controller!.text, 'format');

      await tester.enterText(
        find.byKey(const ValueKey('composer-link-url')),
        'https://example.com',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-link-insert')));
      await tester.pumpAndSettle();

      expect(controller.text, '[format](https://example.com) me');
      expect(find.byType(ComposerLinkPill), findsOneWidget);
    });

    testWidgets('a typed domain becomes a link in chat', (tester) async {
      final fixture = await _fixture(
        pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
      );
      addTearDown(fixture.shell.dispose);
      await tester.pumpWidget(_TestView(shell: fixture.shell));
      await tester.pumpAndSettle();

      await tester.enterText(_composerField(), 'google.fr');
      await tester.pump();

      final pill = tester.widget<ComposerLinkPill>(
        find.byType(ComposerLinkPill),
      );
      expect(pill.anchor, 'google.fr');
      expect(pill.url, 'http://google.fr');
      expect(_text(tester), 'google.fr');
    });

    testWidgets('chat composer deletes a rendered emoji atomically', (
      tester,
    ) async {
      final pipeline = installTestMediaPipeline(
        client: MockClient((_) async => http.Response.bytes(_pngBytes, 200)),
      );
      final fixture = await _fixture(
        pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
      );
      addTearDown(fixture.shell.dispose);
      await pipeline.emoji.load(fixture.shell.emojiUrlFor(_site, 'smile'));
      await tester.pumpWidget(_TestView(shell: fixture.shell));
      await tester.pumpAndSettle();
      await tester.enterText(_composerField(), ':smile:');
      await tester.pump();

      expect(find.byType(EmojiImage), findsOneWidget);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: ':smile',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
      await tester.pump();

      expect(_text(tester), isEmpty);
    });

    testWidgets('the site-config listenable ignores changes from other sites', (
      tester,
    ) async {
      const otherSite = 'https://other.example';
      const otherConfig = SiteConfig(userStatusEnabled: true);
      final fixture = await _fixture(
        pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
        additionalInstances: const [
          DiscourseInstance(url: otherSite, title: 'Other', apiVersion: 4),
        ],
        fetchedSiteConfigs: const {otherSite: otherConfig},
      );
      addTearDown(fixture.shell.dispose);
      await tester.pumpWidget(_TestView(shell: fixture.shell));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(ChatComposer));
      final host = PluginUiScope.require(context, chatComposerHostService);
      final config = host.siteConfigListenableFor(_site);
      expect(config, isNot(isA<ShellController>()));
      expect(host.siteConfigListenableFor(_site), same(config));

      var notifications = 0;
      void notified() => notifications++;
      config.addListener(notified);
      addTearDown(() => config.removeListener(notified));

      expect(await fixture.shell.resolveSiteConfig(otherSite), otherConfig);
      await tester.pump();

      expect(notifications, 0);
    });

    testWidgets('stays pinned while the message stream scrolls', (
      tester,
    ) async {
      final messages = [for (var id = 1; id <= 80; id++) _message(id)];
      final fixture = await _fixture(
        pages: {
          FakeDiscourseApi.chatMessagesKey(9): (
            messages: messages,
            canLoadMorePast: false,
            canLoadMoreFuture: false,
            targetMessageId: null,
          ),
        },
      );
      addTearDown(fixture.shell.dispose);
      await tester.pumpWidget(_TestView(shell: fixture.shell));
      await tester.pumpAndSettle();

      final bar = find.byKey(const ValueKey('chat-composer'));
      expect(find.byTooltip('Add to message'), findsNothing);
      expect(find.byTooltip('Add emoji'), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-composer-emoji')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-composer-gif')), findsNothing);
      expect(find.byKey(const ValueKey('chat-composer-send')), findsOneWidget);
      final before = tester.getRect(bar);
      final scrollable = find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.up,
      );
      expect(scrollable, findsOneWidget);

      await tester.drag(scrollable, const Offset(0, 400));
      await tester.pump();

      expect(tester.getRect(bar), before);
      expect(before.bottom, closeTo(588, 1));
    });

    testWidgets('focuses the field from any non-button composer space', (
      tester,
    ) async {
      final fixture = await _fixture(
        pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
      );
      addTearDown(fixture.shell.dispose);
      await tester.pumpWidget(_TestView(shell: fixture.shell));
      await tester.pumpAndSettle();

      final fieldFinder = find.byType(TextField);
      final sendFinder = find.byKey(const ValueKey('chat-composer-send'));
      final field = tester.widget<TextField>(fieldFinder);
      field.focusNode!.unfocus();
      await tester.pump();

      final bar = tester.getRect(find.byKey(const ValueKey('chat-composer')));
      final chromeTarget = bar.topLeft + const Offset(8, 8);
      expect(tester.getRect(fieldFinder).contains(chromeTarget), isFalse);
      expect(tester.getRect(sendFinder).contains(chromeTarget), isFalse);
      await tester.tapAt(chromeTarget);
      await tester.pump();

      expect(field.focusNode!.hasFocus, isTrue);

      field.focusNode!.unfocus();
      await tester.pump();
      final trailingTarget = Offset(bar.right - 2, bar.center.dy);
      expect(tester.getRect(fieldFinder).contains(trailingTarget), isFalse);
      expect(tester.getRect(sendFinder).contains(trailingTarget), isFalse);
      await tester.tapAt(trailingTarget);
      await tester.pump();

      expect(field.focusNode!.hasFocus, isTrue);

      field.focusNode!.unfocus();
      await tester.pump();
      expect(tester.widget<DButton>(sendFinder).onPressed, isNull);
      await tester.tap(sendFinder);
      await tester.pump();

      expect(field.focusNode!.hasFocus, isFalse);
    });

    testWidgets(
      'grows with the draft, scrolls at the core viewport limit, and collapses after sending',
      (tester) async {
        final fixture = await _fixture(
          pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
        );
        addTearDown(fixture.shell.dispose);
        await tester.pumpWidget(_TestView(shell: fixture.shell));
        await tester.pumpAndSettle();

        final bar = find.byKey(const ValueKey('chat-composer'));
        final initialHeight = tester.getSize(bar).height;
        expect(initialHeight, 58);
        expect(_field(tester).expands, isFalse);
        expect(_field(tester).minLines, 1);
        expect(_field(tester).maxLines, isNull);

        await tester.enterText(
          _composerField(),
          [for (var word = 0; word < 80; word++) 'word$word'].join(' '),
        );
        await tester.pump();

        expect(tester.getSize(bar).height, greaterThan(initialHeight));

        await tester.enterText(
          _composerField(),
          [for (var line = 0; line < 80; line++) 'line $line'].join('\n'),
        );
        await tester.pump();

        final viewportHeight = MediaQuery.sizeOf(tester.element(bar)).height;
        final fieldHeight = tester.getSize(_composerField()).height;
        expect(fieldHeight, closeTo(viewportHeight * 0.25, 1));
        expect(
          _field(tester).scrollController!.position.maxScrollExtent,
          greaterThan(0),
        );

        await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
        await tester.pumpAndSettle();

        expect(tester.getSize(bar).height, initialHeight);
      },
    );

    testWidgets(
      'the whole channel accepts an image and sends it as a chat attachment',
      (tester) async {
        const upload = ComposerUploadResult(
          id: 73,
          originalFilename: 'photo.png',
          shortUrl: 'upload://photo',
          url: 'https://chat.example/uploads/photo.png',
          thumbnailUrl:
              'data:image/png;base64,'
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
              'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
          width: 640,
          height: 480,
        );
        final fixture = await _fixture(
          pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
          composerUploadResult: upload,
        );
        addTearDown(fixture.shell.dispose);
        await tester.pumpWidget(_TestView(shell: fixture.shell));
        await tester.pumpAndSettle();

        final targetFinder = find.byKey(
          const ValueKey('chat-upload-drop-target'),
        );
        final target = tester.widget<DropTarget>(targetFinder);
        final position = tester.getCenter(targetFinder);
        target.onDragEntered!(
          DropEventDetails(localPosition: position, globalPosition: position),
        );
        await tester.pump();

        final overlay = find.byKey(const ValueKey('chat-upload-drop-overlay'));
        expect(overlay, findsOneWidget);
        expect(find.text('Drop images to upload to #design'), findsOneWidget);
        expect(
          tester.getRect(overlay),
          tester.getRect(find.byType(ChatUploadDropRegion)),
        );

        final file = DropItemFile(
          '/tmp/photo.png',
          bytes: Uint8List.fromList(const [1, 2, 3]),
        );
        expect(file.name, 'photo.png');
        tester.widget<DropTarget>(targetFinder).onDragDone!(
          DropDoneDetails(
            files: [file],
            localPosition: position,
            globalPosition: position,
          ),
        );
        await tester.pumpAndSettle();

        expect(overlay, findsNothing);
        expect(_text(tester), isEmpty);
        expect(fixture.api.composerUploads, hasLength(1));
        expect(
          fixture.api.composerUploads.single.uploadType,
          ChatPlugin.messageUploadType,
        );
        expect(find.text('photo.png'), findsOneWidget);
        expect(find.text('Ready to send'), findsNothing);
        final thumbnailFinder = find.byKey(
          const ValueKey('composer-upload-thumbnail-73'),
        );
        final thumbnail = tester.widget<SiteImage>(thumbnailFinder);
        expect(thumbnail.url, upload.previewUrl);
        expect(thumbnail.siteUrl, _site);
        expect(thumbnail.fit, BoxFit.cover);
        expect(tester.getSize(thumbnailFinder), const Size.square(32));
        expect(_button(tester, 'chat-composer-send').onPressed, isNotNull);

        await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
        await tester.pumpAndSettle();

        expect(fixture.api.chatMessagesSent.single.message, isEmpty);
        expect(fixture.api.chatMessagesSent.single.uploadIds, [73]);
        expect(thumbnailFinder, findsNothing);
      },
    );

    testWidgets(
      'editing fills the composer with message text and uploads',
      (tester) async {
        const thumbnail =
            'data:image/png;base64,'
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
            'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
        final message = ChatMessage(
          id: 7,
          channelId: 9,
          raw: '**before**\nsecond line\nthird line',
          cooked: '<p><strong>before</strong></p>',
          author: const ChatMessageAuthor(id: 7, username: 'reader'),
          createdAt: DateTime.utc(2026, 8, 11),
          uploads: const [
            ChatUpload(
              id: 31,
              url: 'https://chat.example/uploads/photo.png',
              originalFilename: 'photo.png',
              kind: ChatUploadKind.image,
              thumbnailUrl: thumbnail,
              width: 640,
              height: 480,
            ),
          ],
        );
        final fixture = await _fixture(
          pages: {
            FakeDiscourseApi.chatMessagesKey(9): (
              messages: [message],
              canLoadMorePast: false,
              canLoadMoreFuture: false,
              targetMessageId: null,
            ),
          },
          sessionUser: const DiscourseUser(id: 7, username: 'reader'),
        );
        addTearDown(fixture.shell.dispose);
        await tester.pumpWidget(_TestView(shell: fixture.shell));
        await tester.pumpAndSettle();

        final compactComposerHeight = tester
            .getSize(find.byKey(const ValueKey('chat-composer')))
            .height;
        await tester.enterText(_composerField(), 'unrelated draft');
        final pointer = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await pointer.addPointer(location: Offset.zero);
        addTearDown(pointer.removePointer);
        await pointer.moveTo(
          tester.getCenter(find.byKey(ChatMessageTile.actionsKey(7))),
        );
        await tester.pump();
        await tester.tap(find.byTooltip('More message actions'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(MenuItemButton, 'Edit'));
        await tester.pumpAndSettle();

        expect(find.text('Edit message'), findsNothing);
        expect(
          find.byKey(const ValueKey('chat-composer-editing')),
          findsNothing,
        );
        expect(find.text('Editing @reader'), findsNothing);
        expect(
          find.byKey(const ValueKey('chat-composer-edit-cancel')),
          findsOneWidget,
        );
        expect(_text(tester), '**before**\nsecond line\nthird line');
        expect(
          tester.getSize(find.byKey(const ValueKey('chat-composer'))).height,
          greaterThan(compactComposerHeight),
        );
        expect(find.text('photo.png'), findsOneWidget);
        expect(find.byTooltip('Save edit'), findsOneWidget);

        await tester.enterText(_composerField(), '**after**');
        await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
        await tester.pumpAndSettle();

        final request = fixture.api.chatMessagesEdited.single;
        expect(request.channelId, 9);
        expect(request.messageId, 7);
        expect(request.message, '**after**');
        expect(request.uploadIds, [31]);
        expect(
          find.byKey(const ValueKey('chat-composer-edit-cancel')),
          findsNothing,
        );
        expect(_text(tester), isEmpty);
        expect(
          tester.getSize(find.byKey(const ValueKey('chat-composer'))).height,
          compactComposerHeight,
        );
        expect(find.text('photo.png'), findsNothing);
      },
    );

    testWidgets(
      'Arrow Up edits the latest message and inline cancel exits editing',
      (tester) async {
        const reader = ChatMessageAuthor(id: 7, username: 'reader');
        final fixture = await _fixture(
          pages: {
            FakeDiscourseApi.chatMessagesKey(9): (
              messages: [
                ChatMessage(
                  id: 1,
                  channelId: 9,
                  raw: 'older message',
                  cooked: '<p>older message</p>',
                  author: reader,
                  createdAt: DateTime.utc(2026, 8, 11, 10),
                ),
                ChatMessage(
                  id: 2,
                  channelId: 9,
                  raw: 'another user',
                  cooked: '<p>another user</p>',
                  author: const ChatMessageAuthor(id: 8, username: 'sam'),
                  createdAt: DateTime.utc(2026, 8, 11, 11),
                ),
                ChatMessage(
                  id: 3,
                  channelId: 9,
                  raw: 'latest editable message',
                  cooked: '<p>latest editable message</p>',
                  author: reader,
                  createdAt: DateTime.utc(2026, 8, 11, 12),
                ),
                ChatMessage(
                  id: 4,
                  channelId: 9,
                  raw: 'deleted message',
                  cooked: '<p>deleted message</p>',
                  author: reader,
                  createdAt: DateTime.utc(2026, 8, 11, 13),
                  deletedAt: DateTime.utc(2026, 8, 11, 14),
                ),
              ],
              canLoadMorePast: false,
              canLoadMoreFuture: false,
              targetMessageId: null,
            ),
          },
          sessionUser: const DiscourseUser(id: 7, username: 'reader'),
        );
        addTearDown(fixture.shell.dispose);
        await tester.pumpWidget(_TestView(shell: fixture.shell));
        await tester.pumpAndSettle();

        _field(tester).focusNode!.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('chat-composer-edit-cancel')),
          findsOneWidget,
        );
        expect(_text(tester), 'latest editable message');

        await tester.tap(
          find.byKey(const ValueKey('chat-composer-edit-cancel')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('chat-composer-edit-cancel')),
          findsNothing,
        );
        expect(_text(tester), isEmpty);
        expect(find.byTooltip('Send message'), findsOneWidget);
      },
    );

    testWidgets(
      'Arrow Up does not fall back past the latest uneditable user message',
      (tester) async {
        const reader = ChatMessageAuthor(id: 7, username: 'reader');
        final fixture = await _fixture(
          pages: {
            FakeDiscourseApi.chatMessagesKey(9): (
              messages: [
                ChatMessage(
                  id: 1,
                  channelId: 9,
                  raw: 'older editable message',
                  cooked: '<p>older editable message</p>',
                  author: reader,
                  createdAt: DateTime.utc(2026, 8, 11, 10),
                ),
                ChatMessage(
                  id: -1,
                  channelId: 9,
                  raw: 'message still sending',
                  cooked: '',
                  author: reader,
                  createdAt: DateTime.utc(2026, 8, 11, 11),
                  stagedId: 'pending-message',
                ),
              ],
              canLoadMorePast: false,
              canLoadMoreFuture: false,
              targetMessageId: null,
            ),
          },
          sessionUser: const DiscourseUser(id: 7, username: 'reader'),
        );
        addTearDown(fixture.shell.dispose);
        await tester.pumpWidget(_TestView(shell: fixture.shell));
        await tester.pumpAndSettle();

        _field(tester).focusNode!.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('chat-composer-edit-cancel')),
          findsNothing,
        );
        expect(_text(tester), isEmpty);
      },
    );

    testWidgets('Arrow Up does not edit while the draft has content', (
      tester,
    ) async {
      final fixture = await _fixture(
        pages: {
          FakeDiscourseApi.chatMessagesKey(9): (
            messages: [
              ChatMessage(
                id: 1,
                channelId: 9,
                raw: 'previous message',
                cooked: '<p>previous message</p>',
                author: const ChatMessageAuthor(id: 7, username: 'reader'),
                createdAt: DateTime.utc(2026, 8, 11, 10),
              ),
            ],
            canLoadMorePast: false,
            canLoadMoreFuture: false,
            targetMessageId: null,
          ),
        },
        sessionUser: const DiscourseUser(id: 7, username: 'reader'),
      );
      addTearDown(fixture.shell.dispose);
      await tester.pumpWidget(_TestView(shell: fixture.shell));
      await tester.pumpAndSettle();

      await tester.enterText(_composerField(), 'draft in progress');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('chat-composer-edit-cancel')),
        findsNothing,
      );
    });

    testWidgets('the channel drop target honors the site upload setting', (
      tester,
    ) async {
      final fixture = await _fixture(
        pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
        config: SiteConfig(
          plugins: PluginData.none.withValue(
            chatSettingsDataKey,
            const ChatSettings(uploadsEnabled: false),
          ),
        ),
      );
      addTearDown(fixture.shell.dispose);
      await tester.pumpWidget(_TestView(shell: fixture.shell));
      await tester.pumpAndSettle();

      final targetFinder = find.byKey(
        const ValueKey('chat-upload-drop-target'),
      );
      final target = tester.widget<DropTarget>(targetFinder);
      final position = tester.getCenter(targetFinder);
      target.onDragEntered!(
        DropEventDetails(localPosition: position, globalPosition: position),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('chat-upload-drop-overlay')),
        findsNothing,
      );
      target.onDragDone!(
        DropDoneDetails(
          files: [
            DropItemFile(
              '/tmp/photo.png',
              bytes: Uint8List.fromList(const [1, 2, 3]),
            ),
          ],
          localPosition: position,
          globalPosition: position,
        ),
      );
      await tester.pumpAndSettle();

      expect(fixture.api.composerUploads, isEmpty);
    });
  });

  group('emoji and GIF picker action handling', () {
    testWidgets('adds only the compact Send GIF action when enabled', (
      tester,
    ) async {
      final fixture = await _fixture(
        pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
        config: _gifsConfig,
      );
      addTearDown(fixture.shell.dispose);
      await tester.pumpWidget(_TestView(shell: fixture.shell));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Send GIF'), findsOneWidget);
      expect(find.byTooltip('Insert GIF'), findsNothing);
      expect(find.byTooltip('Search GIFs'), findsNothing);
      expect(find.byTooltip('Insert date/time  Ctrl Shift .'), findsNothing);
      expect(find.byTooltip('Add to message'), findsNothing);
      expect(find.byTooltip('Add emoji'), findsOneWidget);
      final composer = tester.getRect(
        find.byKey(const ValueKey('chat-composer')),
      );
      expect(composer.height, 58);
      for (final key in const [
        'chat-composer-emoji',
        'chat-composer-gif',
        'chat-composer-send',
      ]) {
        final finder = find.byKey(ValueKey(key));
        final dButton = tester.widget<DButton>(finder);
        final button = tester.getRect(finder);
        expect(
          dButton.variant,
          key == 'chat-composer-send'
              ? DButtonVariant.transparentPrimary
              : DButtonVariant.flat,
        );
        expect(button.size, const Size.square(DButton.minimumDimension));
        expect(button.height, lessThan(composer.height));
        expect(button.center.dy, composer.center.dy);
      }
    });

    testWidgets('keeps both send actions idle while the GIF picker is open', (
      tester,
    ) async {
      final fixture = await _fixture(
        pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
        config: _gifsConfig,
      );
      addTearDown(fixture.shell.dispose);
      await tester.pumpWidget(_TestView(shell: fixture.shell));
      await tester.pumpAndSettle();

      final field = _composerField();
      await tester.enterText(field, 'keep this draft');
      await tester.pump();
      await _openGifPicker(tester);

      expect(_button(tester, 'chat-composer-gif').onPressed, isNull);
      expect(_button(tester, 'chat-composer-send').onPressed, isNull);

      await _closeGifPicker(tester);
      await tester.pumpAndSettle();

      expect(_text(tester), 'keep this draft');
      expect(fixture.api.chatMessagesSent, isEmpty);
      expect(_button(tester, 'chat-composer-gif').onPressed, isNotNull);
      expect(_button(tester, 'chat-composer-send').onPressed, isNotNull);
    });

    testWidgets('inserts a picked emoji into the draft without sending it', (
      tester,
    ) async {
      final fixture = await _fixture(
        pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
        emojiCatalog: SiteEmojiCatalog(
          groups: [
            SiteEmojiGroup(
              id: 'smileys_&_emotion',
              emojis: const [
                SiteEmoji(
                  name: 'wave',
                  url: 'https://cdn.example/wave.png',
                  tonable: true,
                ),
              ],
            ),
          ],
        ),
      );
      addTearDown(fixture.shell.dispose);
      await tester.pumpWidget(_TestView(shell: fixture.shell));
      await tester.pumpAndSettle();
      await tester.enterText(_composerField(), 'hello');

      await tester.tap(find.byKey(const ValueKey('chat-composer-emoji')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(':wave:'));
      await tester.pumpAndSettle();

      expect(_text(tester), 'hello :wave:');
      expect(fixture.api.chatMessagesSent, isEmpty);
      expect(_field(tester).focusNode!.hasFocus, isTrue);
    });

    testWidgets(
      'sends a selected GIF immediately without consuming the draft',
      (tester) async {
        final sendGate = Completer<void>();
        final fixture = await _fixture(
          pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
          config: _gifsConfig,
          sendGate: sendGate,
        );
        addTearDown(fixture.shell.dispose);
        await tester.pumpWidget(_TestView(shell: fixture.shell));
        await tester.pumpAndSettle();

        await tester.enterText(_composerField(), 'unchanged draft');
        await tester.pump();
        await _openGifPicker(tester);
        await _closeGifPicker(tester, _gif);

        expect(fixture.api.chatMessagesSent, hasLength(1));
        expect(fixture.api.chatMessagesSent.single.siteUrl, _site);
        expect(fixture.api.chatMessagesSent.single.channelId, 9);
        expect(fixture.api.chatMessagesSent.single.message, _gif.markdown);
        expect(_text(tester), 'unchanged draft');
        expect(_button(tester, 'chat-composer-gif').onPressed, isNotNull);
        expect(_button(tester, 'chat-composer-send').onPressed, isNotNull);
        expect(find.byKey(const ValueKey('chat-preview-gif')), findsOneWidget);
        expect(
          tester.getSize(find.byKey(const ValueKey('chat-preview-gif'))).height,
          150,
        );
        expect(
          find.byKey(const ValueKey('chat-preview-gif-fallback')),
          findsOneWidget,
        );
        expect(find.text('Party parrot'), findsOneWidget);

        sendGate.complete();
        await tester.pumpAndSettle();

        expect(_text(tester), 'unchanged draft');
        expect(_field(tester).focusNode!.hasFocus, isTrue);
      },
    );

    testWidgets('preserves a draft when the GIF send fails', (tester) async {
      const failure = WriteException(WriteFailure.unreachable);
      final fixture = await _fixture(
        pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
        config: _gifsConfig,
        sendFailure: failure,
      );
      addTearDown(fixture.shell.dispose);
      await tester.pumpWidget(_TestView(shell: fixture.shell));
      await tester.pumpAndSettle();

      await tester.enterText(_composerField(), 'do not consume me');
      await tester.pump();
      await _openGifPicker(tester);
      await _closeGifPicker(tester, _gif);
      await tester.pumpAndSettle();

      expect(_text(tester), 'do not consume me');
      expect(find.text(failure.message), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-preview-gif')), findsOneWidget);
      expect(fixture.api.chatMessagesSent, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('preserves text typed while a GIF send is in flight', (
      tester,
    ) async {
      final sendGate = Completer<void>();
      final fixture = await _fixture(
        pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
        config: _gifsConfig,
        sendGate: sendGate,
      );
      addTearDown(fixture.shell.dispose);
      await tester.pumpWidget(_TestView(shell: fixture.shell));
      await tester.pumpAndSettle();

      await tester.enterText(_composerField(), 'old draft');
      await tester.pump();
      await _openGifPicker(tester);
      await _closeGifPicker(tester, _gif);
      await tester.enterText(_composerField(), 'next draft');
      await tester.pump();

      sendGate.complete();
      await tester.pumpAndSettle();

      expect(_text(tester), 'next draft');
      expect(_field(tester).focusNode!.hasFocus, isTrue);
    });

    testWidgets('preserves selection-only changes made in the GIF picker', (
      tester,
    ) async {
      final fixture = await _fixture(
        pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
        config: _gifsConfig,
      );
      addTearDown(fixture.shell.dispose);
      await tester.pumpWidget(_TestView(shell: fixture.shell));
      await tester.pumpAndSettle();

      await tester.enterText(_composerField(), 'same text');
      await tester.pump();
      await _openGifPicker(tester);
      const changedDocument = TextEditingValue(
        text: 'same text',
        selection: TextSelection.collapsed(offset: 0),
      );
      _field(tester).controller!.value = changedDocument;
      await tester.pump();
      await _closeGifPicker(tester, _gif);
      await tester.pumpAndSettle();

      expect(_field(tester).controller!.value, changedDocument);
      expect(fixture.api.chatMessagesSent, hasLength(1));
    });

    testWidgets(
      'a completed GIF send does not clear or refocus a replacement channel',
      (tester) async {
        final sendGate = Completer<void>();
        final fixture = await _fixture(
          pages: const {},
          config: _gifsConfig,
          sendGate: sendGate,
        );
        addTearDown(fixture.shell.dispose);
        await tester.pumpWidget(
          _ComposerView(shell: fixture.shell, channelId: 9),
        );
        await tester.pumpAndSettle();

        await tester.enterText(_composerField(), 'channel nine draft');
        await tester.pump();
        await _openGifPicker(tester);
        await _closeGifPicker(tester, _gif);
        expect(fixture.api.chatMessagesSent.single.channelId, 9);

        await tester.pumpWidget(
          _ComposerView(shell: fixture.shell, channelId: 10),
        );
        await tester.pump();
        await tester.enterText(_composerField(), 'channel ten draft');
        await tester.pump();

        sendGate.complete();
        await tester.pumpAndSettle();

        expect(_text(tester), 'channel ten draft');
        expect(_field(tester).focusNode!.hasFocus, isTrue);
      },
    );
  });

  group('optimistic send projection', () {
    testWidgets('sends markdown and starts a clean, focused document', (
      tester,
    ) async {
      final fixture = await _fixture(
        pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
      );
      addTearDown(fixture.shell.dispose);
      await tester.pumpWidget(_TestView(shell: fixture.shell));
      await tester.pumpAndSettle();

      final field = find.byType(TextField);
      await tester.enterText(field, '**hello** chat');
      await tester.pump();
      final send = find.byKey(const ValueKey('chat-composer-send'));
      expect(tester.widget<DButton>(send).onPressed, isNotNull);
      await tester.tap(send);
      await tester.pumpAndSettle();

      final sent = fixture.api.chatMessagesSent.single;
      expect(sent.siteUrl, _site);
      expect(sent.channelId, 9);
      expect(sent.message, '**hello** chat');
      expect(sent.threadId, isNull);
      expect(sent.stagedId, startsWith('native-'));
      expect(sent.clientCreatedAt, isNotNull);
      expect(sent.clientCreatedAt!.isUtc, isTrue);
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(fixture.shell.chat.stream(_site, 9).messageIds, isEmpty);
      expect(fixture.shell.chat.stream(_site, 9).localMessageIds, hasLength(1));
      expect(fixture.api.chatMessagesRequested, hasLength(1));
      expect(find.text('hello chat'), findsOneWidget);
      expect(find.text('**hello** chat'), findsNothing);
    });

    testWidgets('stages immediately without clearing the next draft', (
      tester,
    ) async {
      final sendGate = Completer<void>();
      final fixture = await _fixture(
        pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
        sendGate: sendGate,
        sentMessageId: 42,
      );
      addTearDown(fixture.shell.dispose);
      await tester.pumpWidget(_TestView(shell: fixture.shell));
      await tester.pumpAndSettle();

      final field = find.byType(TextField);
      await tester.enterText(field, 'first message');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
      await tester.pump();

      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      expect(find.text('first message'), findsOneWidget);
      expect(find.text('Sending…'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(fixture.shell.chat.stream(_site, 9).localMessageIds, hasLength(1));
      expect(fixture.api.chatMessagesRequested, hasLength(1));

      await tester.enterText(field, 'next draft');
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, 'next draft');
      expect(_button(tester, 'chat-composer-send').onPressed, isNotNull);

      sendGate.complete();
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(field).controller!.text, 'next draft');
      expect(fixture.api.chatMessagesRequested, hasLength(1));
      expect(fixture.api.chatMessagesSent, hasLength(1));
      expect(
        fixture.api.chatMessagesSent.single.stagedId,
        startsWith('native-'),
      );
      expect(fixture.api.chatMessagesSent.single.clientCreatedAt, isNotNull);
    });

    testWidgets(
      'canonical cooked content replaces the projected row in place',
      (tester) async {
        final fixture = await _fixture(
          pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
        );
        addTearDown(fixture.shell.dispose);
        await tester.pumpWidget(_TestView(shell: fixture.shell));
        await tester.pumpAndSettle();

        await tester.enterText(_composerField(), '**provisional**');
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
        await tester.pumpAndSettle();

        final localId = fixture.shell.chat
            .stream(_site, 9)
            .localMessageIds
            .single;
        final local = fixture.shell.chatRecords.read<ChatMessage>(
          _site,
          localId,
        )!;
        expect(find.text('provisional'), findsOneWidget);
        expect(find.byType(ChatPreviewBody), findsOneWidget);
        expect(find.byType(ChatMessageTile), findsOneWidget);

        fixture.shell.chatRecords.put(
          _site,
          local.withCanonical(
            ChatMessage(
              id: 42,
              channelId: 9,
              cooked: '<p>Canonical answer</p>',
              author: local.author,
              createdAt: local.createdAt,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final canonical = tester.widget<CookedHtml>(find.byType(CookedHtml));
        expect(canonical.html, '<p>Canonical answer</p>');
        expect(find.byType(ChatPreviewBody), findsNothing);
        expect(find.text('provisional'), findsNothing);
        expect(find.byType(ChatMessageTile), findsOneWidget);
        expect(fixture.shell.chat.stream(_site, 9).localMessageIds, [localId]);
      },
    );

    testWidgets('an empty canonical body still retires the projected body', (
      tester,
    ) async {
      final fixture = await _fixture(
        pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
      );
      addTearDown(fixture.shell.dispose);
      await tester.pumpWidget(_TestView(shell: fixture.shell));
      await tester.pumpAndSettle();

      await tester.enterText(_composerField(), '**provisional**');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
      await tester.pumpAndSettle();

      final localId = fixture.shell.chat
          .stream(_site, 9)
          .localMessageIds
          .single;
      final local = fixture.shell.chatRecords.read<ChatMessage>(
        _site,
        localId,
      )!;
      expect(find.byType(ChatPreviewBody), findsOneWidget);

      fixture.shell.chatRecords.put(
        _site,
        local.withCanonical(
          ChatMessage(
            id: 42,
            channelId: 9,
            cooked: '',
            author: local.author,
            createdAt: local.createdAt,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ChatPreviewBody), findsNothing);
      expect(find.text('provisional'), findsNothing);
      expect(find.byType(CookedHtml), findsNothing);
      expect(find.byType(ChatMessageTile), findsOneWidget);
    });

    testWidgets('accepts another row immediately and sends it FIFO', (
      tester,
    ) async {
      final sendGate = Completer<void>();
      final fixture = await _fixture(
        pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
        sendGate: sendGate,
      );
      addTearDown(fixture.shell.dispose);
      await tester.pumpWidget(_TestView(shell: fixture.shell));
      await tester.pumpAndSettle();

      await tester.enterText(_composerField(), 'first');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
      await tester.pumpAndSettle();
      await tester.enterText(_composerField(), 'second');
      await tester.pump();
      expect(_text(tester), 'second');
      expect(_button(tester, 'chat-composer-send').onPressed, isNotNull);
      _button(tester, 'chat-composer-send').onPressed!();
      expect(fixture.shell.chatRecords.read<ChatMessage>(_site, -2), isNotNull);
      expect(fixture.shell.chat.stream(_site, 9).localMessageIds, hasLength(2));
      await tester.pump();

      expect(_text(tester), isEmpty);
      expect(fixture.shell.chat.stream(_site, 9).localMessageIds, hasLength(2));
      expect(find.text('Sending…'), findsNothing);
      expect(fixture.api.chatMessagesSent, hasLength(1));

      sendGate.complete();
      await tester.pumpAndSettle();

      expect(fixture.api.chatMessagesSent.map((call) => call.message), [
        'first',
        'second',
      ]);
    });
  });

  group('composer fallbacks and availability', () {
    testWidgets('manually typed image Markdown stays visible as raw source', (
      tester,
    ) async {
      final fixture = await _fixture(
        pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
      );
      addTearDown(fixture.shell.dispose);
      await tester.pumpWidget(_TestView(shell: fixture.shell));
      await tester.pumpAndSettle();

      await tester.enterText(_composerField(), _gif.markdown);
      await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
      await tester.pumpAndSettle();

      expect(find.text(_gif.markdown), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-preview-gif')), findsNothing);
    });

    testWidgets(
      'keeps an uncertain network failure on the row without resending',
      (tester) async {
        const failure = WriteException(WriteFailure.unreachable);
        final fixture = await _fixture(
          pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
          sendFailure: failure,
        );
        addTearDown(fixture.shell.dispose);
        await tester.pumpWidget(_TestView(shell: fixture.shell));
        await tester.pumpAndSettle();

        final field = find.byType(TextField);
        await tester.enterText(field, 'keep me visible');
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
        await tester.pumpAndSettle();

        expect(tester.widget<TextField>(field).controller!.text, isEmpty);
        expect(find.text('keep me visible'), findsOneWidget);
        expect(find.text(failure.message), findsOneWidget);
        expect(find.text('Retry'), findsNothing);
        expect(fixture.api.chatMessagesSent, hasLength(1));
      },
    );

    testWidgets('does not offer retry for a definitive refusal', (
      tester,
    ) async {
      const failure = WriteException(
        WriteFailure.validation,
        errors: ['That message is not allowed.'],
      );
      final fixture = await _fixture(
        pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
        sendFailure: failure,
      );
      addTearDown(fixture.shell.dispose);
      await tester.pumpWidget(_TestView(shell: fixture.shell));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'not allowed');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
      await tester.pumpAndSettle();

      expect(find.text(failure.message), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('replaces the composer when the channel is read-only', (
      tester,
    ) async {
      final fixture = await _fixture(
        pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
        channelStatus: ChatChannelStatus.readOnly,
      );
      addTearDown(fixture.shell.dispose);
      await tester.pumpWidget(_TestView(shell: fixture.shell));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('chat-composer-read-only')),
        findsOneWidget,
      );
      expect(find.text('This chat is read-only.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(fixture.api.chatMessagesSent, isEmpty);
    });

    testWidgets('shares the selection formatting menu with topics', (
      tester,
    ) async {
      final fixture = await _fixture(
        pages: {FakeDiscourseApi.chatMessagesKey(9): _emptyPage},
      );
      addTearDown(fixture.shell.dispose);
      await tester.pumpWidget(_TestView(shell: fixture.shell));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Bold'), findsNothing);
      expect(find.byTooltip('Italic'), findsNothing);

      final field = tester.widget<TextField>(find.byType(TextField));
      field.controller!.value = const TextEditingValue(
        text: 'format me',
        selection: TextSelection(baseOffset: 0, extentOffset: 6),
      );
      field.focusNode!.requestFocus();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('composer-selection-toolbar')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Italic'));
      await tester.pump();

      expect(field.controller!.text, '*format* me');
    });
  });
}

final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

const ChatMessagePage _emptyPage = (
  messages: [],
  canLoadMorePast: false,
  canLoadMoreFuture: false,
  targetMessageId: null,
);

ChatMessage _message(int id) => ChatMessage(
  id: id,
  channelId: 9,
  cooked: '<p>Message $id</p>',
  author: const ChatMessageAuthor(id: 2, username: 'sam'),
  createdAt: DateTime.utc(2026, 8, 11, 0, 0, id),
);

Future<({ShellController shell, FakeDiscourseApi api})> _fixture({
  required Map<String, ChatMessagePage> pages,
  SiteConfig config = const SiteConfig.unknown(),
  List<DiscourseInstance> additionalInstances = const [],
  Map<String, SiteConfig> fetchedSiteConfigs = const {},
  DiscourseUser? sessionUser,
  Completer<void>? sendGate,
  WriteException? sendFailure,
  int? sentMessageId,
  SiteEmojiCatalog? emojiCatalog,
  ComposerUploadResult? composerUploadResult,
  ChatChannelStatus channelStatus = ChatChannelStatus.open,
}) async {
  final api = FakeDiscourseApi(
    user: sessionUser,
    chatMessagesByKey: pages,
    chatSendGate: sendGate,
    chatSendFailure: sendFailure,
    chatSentMessageId: sentMessageId ?? 1,
    composerUploadResult: composerUploadResult,
    emojiCatalogsBySite: {_site: ?emojiCatalog},
    siteConfigs: fetchedSiteConfigs,
  );
  final authenticator = FakeAuthenticator()..keys[_site] = 'key';
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      DiscourseInstance(
        url: _site,
        title: 'Chat',
        apiVersion: 4,
        config: config,
        user: sessionUser,
      ),
      ...additionalInstances,
    ]),
    api: api,
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    plugins: installedPlugins,
  );
  await shell.load();
  shell.chatRecords.put(
    _site,
    ChatChannel(
      id: 9,
      title: 'design',
      kind: ChatChannelKind.category,
      status: channelStatus,
      membership: const ChatMembership(following: true),
    ),
  );
  shell.chatRecords.put(
    _site,
    const ChatChannel(
      id: 10,
      title: 'support',
      kind: ChatChannelKind.category,
      membership: ChatMembership(following: true),
    ),
  );
  return (shell: shell, api: api);
}

Finder _composerField() => find.descendant(
  of: find.byKey(const ValueKey('chat-composer')),
  matching: find.byType(TextField),
);

TextField _field(WidgetTester tester) => tester.widget(_composerField());

String _text(WidgetTester tester) => _field(tester).controller!.text;

Future<void> _pressCommandE(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pump();
}

Future<void> _pressCommandL(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pump();
}

DButton _button(WidgetTester tester, String key) =>
    tester.widget(find.byKey(ValueKey(key)));

Future<void> _openGifPicker(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('chat-composer-gif')));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('gif-picker-search')), findsOneWidget);
}

Future<void> _closeGifPicker(WidgetTester tester, [GifResult? result]) async {
  final search = find.byKey(const ValueKey('gif-picker-search'));
  Navigator.of(tester.element(search)).pop(result);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

final class _TestView extends StatelessWidget {
  const _TestView({required this.shell});

  final ShellController shell;

  @override
  Widget build(BuildContext context) {
    final app = MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: ChatChannelView(channelId: 9)),
    );
    final ownedApp = PluginUiScope.own(chatPluginId, app);
    return ShellScope(controller: shell, child: ownedApp);
  }
}

final class _ComposerView extends StatelessWidget {
  const _ComposerView({required this.shell, required this.channelId});

  final ShellController shell;
  final int channelId;

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: shell,
    child: PluginUiScope.own(
      chatPluginId,
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ChatComposer(siteUrl: _site, channelId: channelId),
        ),
      ),
    ),
  );
}
