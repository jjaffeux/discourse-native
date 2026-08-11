import 'dart:async';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_composer_pill.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/plugins/poll/poll_composer_pill.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _source =
    'Before the poll.\n\n'
    '[poll name=lunch]\n# Lunch\n* Soup\n* Salad\n[/poll]\n\n'
    'After the poll.';

final class _GatedCurrentUserApi extends FakeDiscourseApi {
  _GatedCurrentUserApi()
    : super(
        feeds: const {'/latest.json': <Topic>[]},
        topics: {7: topicPayload(id: 7, title: 'Lunch', canCreatePost: true)},
        siteConfigs: const {_site: SiteConfig.unknown()},
      );

  final response = Completer<DiscourseUser>();

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) => response.future;
}

Future<ShellController> _openComposer({
  FakeDiscourseApi? api,
  DiscourseUser storedUser = const DiscourseUser(id: 7, username: 'reader'),
}) async {
  final authenticator = FakeAuthenticator()..keys[_site] = 'api-key';
  final discourseApi =
      api ??
      FakeDiscourseApi(
        user: const DiscourseUser(
          id: 7,
          username: 'reader',
          canCreatePoll: true,
        ),
        feeds: const {'/latest.json': <Topic>[]},
        topics: {7: topicPayload(id: 7, title: 'Lunch', canCreatePost: true)},
        siteConfigs: const {_site: SiteConfig.unknown()},
      );
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: storedUser),
    ]),
    api: discourseApi,
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  shell.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'lunch', title: 'Lunch'),
  );
  await shell.loadTopic(7, 'lunch');
  shell.openReply();
  return shell;
}

void main() {
  setUpAll(() {
    LocalDateEnvironment.instance.ensureDatabase();
    LocalDateEnvironment.instance.setDeviceTimezone('Etc/UTC');
  });

  testWidgets('local-date toolbar gating and Shift+. follow the site setting', (
    tester,
  ) async {
    final disabled = await _openComposer();
    addTearDown(disabled.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: ShellScope(
          controller: disabled,
          child: Scaffold(
            body: ComposerPanel(composer: disabled.visibleComposer!),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byTooltip('Insert date/time  ⇧.'), findsNothing);

    final enabled = await _openComposer(
      api: FakeDiscourseApi(
        user: const DiscourseUser(id: 7, username: 'reader'),
        feeds: const {'/latest.json': <Topic>[]},
        topics: {7: topicPayload(id: 7, title: 'Lunch', canCreatePost: true)},
        siteConfigs: const {_site: SiteConfig(localDatesEnabled: true)},
      ),
    );
    addTearDown(enabled.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: ShellScope(
          controller: enabled,
          child: Scaffold(
            body: ComposerPanel(composer: enabled.visibleComposer!),
          ),
        ),
      ),
    );
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(find.byTooltip('Insert date/time  ⇧.'), findsOneWidget);

    await tester.tap(find.byType(TextField).last);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(enabled.visibleComposer!.text.text, startsWith('[date='));
    expect(find.byType(LocalDateComposerPill), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets(
    'the Add poll action waits for and reacts to a fresh session capability',
    (tester) async {
      final api = _GatedCurrentUserApi();
      final shell = await _openComposer(
        api: api,
        storedUser: const DiscourseUser(
          id: 7,
          username: 'reader',
          canCreatePoll: true,
        ),
      );
      addTearDown(shell.dispose);
      final composer = shell.visibleComposer!;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: ShellScope(
            controller: shell,
            child: Scaffold(body: ComposerPanel(composer: composer)),
          ),
        ),
      );
      await tester.pump();

      expect(find.byTooltip('Add poll'), findsNothing);

      api.response.complete(
        const DiscourseUser(id: 7, username: 'reader', canCreatePoll: true),
      );
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump(const Duration(milliseconds: 1));
      }

      expect(find.byTooltip('Add poll'), findsOneWidget);
    },
  );

  testWidgets('click and keyboard boundaries open the poll editor', (
    tester,
  ) async {
    final shell = await _openComposer();
    addTearDown(shell.dispose);
    final composer = shell.visibleComposer!;
    composer.text.value = TextEditingValue(
      text: _source,
      selection: const TextSelection.collapsed(offset: _source.length),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: ShellScope(
          controller: shell,
          child: Scaffold(body: ComposerPanel(composer: composer)),
        ),
      ),
    );
    await tester.pump();

    final pill = find.byType(PollComposerPill);
    expect(pill, findsOneWidget);
    // The field resolves the pill from its visual coordinates before the
    // editable moves its caret.
    final gesture = await tester.startGesture(tester.getCenter(pill));
    final block = composer.text.pollBlocks.single;
    // Desktop EditableText can move the caret and rebuild before or after its
    // tap callback. Neither timing may reveal the source under the modal.
    composer.text.selection = TextSelection.collapsed(offset: block.start + 1);
    await tester.pump();
    expect(find.byType(PollComposerPill), findsOneWidget);
    await gesture.up();
    await tester.pump();
    composer.text.selection = TextSelection.collapsed(offset: block.end - 1);
    await tester.pump();
    expect(find.byType(PollComposerPill), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(PollComposerPill), findsOneWidget);
    expect(find.text('Edit poll'), findsOneWidget);
    expect(composer.text.text, _source);
    expect(
      composer.text.isPollExpanded(composer.text.pollBlocks.single),
      isFalse,
    );

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    for (final offset in [block.start, block.end]) {
      composer.text.selection = TextSelection.collapsed(offset: offset);
      composer.focus.requestFocus();
      await tester.pump();
      expect(find.text('Edit poll'), findsNothing);
      expect(
        tester
            .widget<PollComposerPill>(find.byType(PollComposerPill))
            .highlighted,
        isTrue,
      );
    }

    composer.text.selection = TextSelection.collapsed(offset: block.start);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Edit poll'), findsOneWidget);
    Navigator.of(tester.element(find.text('Edit poll'))).pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('tapping immediately after the pill leaves it collapsed', (
    tester,
  ) async {
    final shell = await _openComposer();
    addTearDown(shell.dispose);
    final composer = shell.visibleComposer!;
    composer.text.value = TextEditingValue(
      text: _source,
      selection: const TextSelection.collapsed(offset: _source.length),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: ShellScope(
          controller: shell,
          child: Scaffold(body: ComposerPanel(composer: composer)),
        ),
      ),
    );
    await tester.pump();

    final pill = find.byType(PollComposerPill);
    final pillRect = tester.getRect(pill);
    await tester.tapAt(Offset(pillRect.right + 6, pillRect.center.dy));
    await tester.pump();

    expect(find.byType(PollComposerPill), findsOneWidget);
    expect(composer.text.text, _source);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('hovering the pill does not show an edit or delete menu', (
    tester,
  ) async {
    final shell = await _openComposer();
    addTearDown(shell.dispose);
    final composer = shell.visibleComposer!;
    composer.text.value = TextEditingValue(
      text: _source,
      selection: const TextSelection.collapsed(offset: _source.length),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: ShellScope(
          controller: shell,
          child: Scaffold(body: ComposerPanel(composer: composer)),
        ),
      ),
    );
    await tester.pump();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(PollComposerPill)));
    await tester.pump();

    expect(find.byTooltip('Edit poll'), findsNothing);
    expect(find.byTooltip('Remove poll'), findsNothing);
    expect(
      composer.text.isPollCollapsed(composer.text.pollBlocks.single),
      isTrue,
    );
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('backspace after a poll removes the whole poll', (tester) async {
    final shell = await _openComposer();
    addTearDown(shell.dispose);
    final composer = shell.visibleComposer!;
    composer.text.value = TextEditingValue(
      text: _source,
      selection: const TextSelection.collapsed(offset: _source.length),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: ShellScope(
          controller: shell,
          child: Scaffold(body: ComposerPanel(composer: composer)),
        ),
      ),
    );
    await tester.pump();

    final poll = composer.text.pollBlocks.single;
    composer.text.selection = TextSelection.collapsed(offset: poll.end);
    composer.focus.requestFocus();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(composer.text.text, 'Before the poll.\n\n\n\nAfter the poll.');
    expect(find.byType(PollComposerPill), findsNothing);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(composer.text.text, _source);
    expect(find.byType(PollComposerPill), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('backspace after ordinary text keeps its native behavior', (
    tester,
  ) async {
    final shell = await _openComposer();
    addTearDown(shell.dispose);
    final composer = shell.visibleComposer!;
    composer.text.value = const TextEditingValue(
      text: 'hello',
      selection: TextSelection.collapsed(offset: 5),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: ShellScope(
          controller: shell,
          child: Scaffold(body: ComposerPanel(composer: composer)),
        ),
      ),
    );
    composer.focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(composer.text.text, 'hell');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('tapping a date pill edits it and backspace removes it', (
    tester,
  ) async {
    const date = '[date=2026-08-11 time=09:00:00 timezone=UTC calendar=off]';
    const source = 'Before $date after';
    final shell = await _openComposer();
    addTearDown(shell.dispose);
    final composer = shell.visibleComposer!;
    composer.text.value = const TextEditingValue(
      text: source,
      selection: TextSelection.collapsed(offset: source.length),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: ShellScope(
          controller: shell,
          child: Scaffold(body: ComposerPanel(composer: composer)),
        ),
      ),
    );
    await tester.pump();

    final pill = find.byType(LocalDateComposerPill);
    final gesture = await tester.startGesture(tester.getCenter(pill));
    final block = composer.text.localDateBlocks.single;
    composer.text.selection = TextSelection.collapsed(offset: block.start + 1);
    await tester.pump();
    expect(find.byType(LocalDateComposerPill), findsOneWidget);
    await gesture.up();
    await tester.pump();
    composer.text.selection = TextSelection.collapsed(offset: block.end - 1);
    await tester.pump();
    expect(find.byType(LocalDateComposerPill), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Edit date and time'), findsOneWidget);
    expect(find.byType(LocalDateComposerPill), findsOneWidget);
    expect(composer.text.text, source);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    composer.text.selection = TextSelection.collapsed(offset: block.start);
    composer.focus.requestFocus();
    await tester.pump();
    expect(
      tester
          .widget<LocalDateComposerPill>(find.byType(LocalDateComposerPill))
          .highlighted,
      isTrue,
    );
    expect(find.text('Edit date and time'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Edit date and time'), findsOneWidget);
    Navigator.of(tester.element(find.text('Edit date and time'))).pop();
    await tester.pumpAndSettle();
    composer.text.selection = TextSelection.collapsed(
      offset: composer.text.localDateBlocks.single.end,
    );
    composer.focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(composer.text.text, 'Before  after');
    expect(find.byType(LocalDateComposerPill), findsNothing);
    await tester.pump(const Duration(seconds: 3));
  });
}
