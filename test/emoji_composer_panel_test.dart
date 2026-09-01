import 'dart:convert';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/emoji_usage.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/emoji.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';
import 'support/media_pipeline.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'reader');

SiteEmojiCatalog get _catalog => SiteEmojiCatalog(
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
);

Future<ShellController> _openComposer({bool emojiEnabled = true}) async {
  final api = FakeDiscourseApi(
    user: _user,
    feeds: const {'/latest.json': <Topic>[]},
    topics: {7: topicPayload(id: 7, title: 'Emoji', canCreatePost: true)},
    siteConfigs: {_site: SiteConfig(emojiEnabled: emojiEnabled)},
    emojiCatalogsBySite: {_site: _catalog},
  );
  final authenticator = FakeAuthenticator()..keys[_site] = 'api-key';
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: _user),
    ]),
    api: api,
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  shell.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'emoji', title: 'Emoji'),
  );
  await shell.loadTopic(7, 'emoji');
  shell.openReply();
  return shell;
}

Future<void> _pumpComposer(WidgetTester tester, ShellController shell) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
      home: ShellScope(
        controller: shell,
        child: Scaffold(body: ComposerPanel(composer: shell.visibleComposer!)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('topic composer deletes rendered emoji atomically', (
    tester,
  ) async {
    final pipeline = installTestMediaPipeline(
      client: MockClient((_) async => http.Response.bytes(_pngBytes, 200)),
    );
    final shell = await _openComposer();
    addTearDown(shell.dispose);
    await pipeline.emoji.load(shell.emojiUrlFor(_site, 'wave'));
    final composer = shell.visibleComposer!;
    composer.text.value = const TextEditingValue(
      text: ':wave:',
      selection: TextSelection.collapsed(offset: 6),
    );
    await _pumpComposer(tester, shell);
    await tester.pump();

    expect(find.byType(EmojiImage), findsOneWidget);
    composer.focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(composer.text.text, isEmpty);

    composer.text.value = const TextEditingValue(
      text: ':wave:',
      selection: TextSelection.collapsed(offset: 0),
    );
    await tester.pump();
    expect(find.byType(EmojiImage), findsOneWidget);
    composer.focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();

    expect(composer.text.text, isEmpty);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('horizontal arrows move across a rendered emoji atomically', (
    tester,
  ) async {
    final pipeline = installTestMediaPipeline(
      client: MockClient((_) async => http.Response.bytes(_pngBytes, 200)),
    );
    final shell = await _openComposer();
    addTearDown(shell.dispose);
    await pipeline.emoji.load(shell.emojiUrlFor(_site, 'wave'));
    final composer = shell.visibleComposer!;
    composer.text.value = const TextEditingValue(
      text: ':wave:',
      selection: TextSelection.collapsed(offset: 6),
    );
    await _pumpComposer(tester, shell);

    expect(find.byType(EmojiImage), findsOneWidget);
    composer.focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();

    expect(composer.text.text, ':wave:');
    expect(composer.text.selection, const TextSelection.collapsed(offset: 0));
    expect(find.byType(EmojiImage), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(composer.text.selection, const TextSelection.collapsed(offset: 6));
    expect(find.byType(EmojiImage), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('topic composer inserts a picker selection at captured caret', (
    tester,
  ) async {
    final shell = await _openComposer();
    addTearDown(shell.dispose);
    final composer = shell.visibleComposer!;
    composer.text.value = const TextEditingValue(
      text: 'BeforeAfter',
      selection: TextSelection.collapsed(offset: 6),
    );
    await _pumpComposer(tester, shell);

    await tester.tap(find.byKey(const ValueKey('composer-emoji-picker')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey('emoji-picker-desktop-popover')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip(':wave:'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(composer.text.text, 'Before :wave:After');
    expect(composer.focus.hasFocus, isTrue);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('emoji-disabled sites hide the topic action', (tester) async {
    final shell = await _openComposer(emojiEnabled: false);
    addTearDown(shell.dispose);
    await _pumpComposer(tester, shell);

    expect(find.byTooltip('Add emoji'), findsNothing);
    expect(find.byKey(const ValueKey('composer-emoji-picker')), findsNothing);
  });

  testWidgets('a stale picker result is neither inserted nor remembered', (
    tester,
  ) async {
    final shell = await _openComposer();
    addTearDown(shell.dispose);
    final composer = shell.visibleComposer!;
    composer.text.value = const TextEditingValue(
      text: 'Before',
      selection: TextSelection.collapsed(offset: 6),
    );
    await _pumpComposer(tester, shell);

    await tester.tap(find.byKey(const ValueKey('composer-emoji-picker')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    composer.text.value = const TextEditingValue(
      text: 'Changed elsewhere',
      selection: TextSelection.collapsed(offset: 17),
    );
    await tester.tap(find.byTooltip(':wave:'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(composer.text.text, 'Changed elsewhere');
    expect(
      shell.emojiPickerStore.favoriteEmojiCodesFor(
        siteUrl: _site,
        context: CoreEmojiUsageContexts.topic,
        catalog: _catalog,
      ),
      isEmpty,
    );
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('an edit still loading its body disables emoji insertion', (
    tester,
  ) async {
    final shell = await _openComposer();
    addTearDown(shell.dispose);
    final composer = shell.visibleComposer!..beginLoadingBody();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
        home: ShellScope(
          controller: shell,
          child: Scaffold(body: ComposerPanel(composer: composer)),
        ),
      ),
    );
    await tester.pump();

    final action = tester.widget<IconButton>(
      find.byKey(const ValueKey('composer-emoji-picker')),
    );
    expect(action.onPressed, isNull);

    composer.loadedBody('Existing body');
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('composer-emoji-picker')),
          )
          .onPressed,
      isNotNull,
    );
  });
}

final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);
