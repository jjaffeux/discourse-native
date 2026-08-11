import 'dart:async';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_composer_pill.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/plugins/poll/poll_composer_editor.dart';
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

EditableText _composerEditable(WidgetTester tester) =>
    tester.widget<EditableText>(
      find.descendant(
        of: find.byType(ComposerEditor),
        matching: find.byType(EditableText),
      ),
    );

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

  testWidgets('click and atomic keyboard navigation open the poll editor', (
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

    final afterPoll = composer.text.pollCaretAfter(block);
    composer.text.selection = TextSelection.collapsed(offset: afterPoll);
    composer.focus.requestFocus();
    await tester.pump();
    expect(find.text('Edit poll'), findsNothing);
    expect(tester.widget<PollComposerPill>(pill).highlighted, isFalse);
    expect(_composerEditable(tester).showCursor, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(composer.text.selection.extentOffset, afterPoll);
    expect(tester.widget<PollComposerPill>(pill).highlighted, isTrue);
    expect(_composerEditable(tester).showCursor, isFalse);
    expect(find.byType(PollComposerPill), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(composer.text.selection.extentOffset, afterPoll);
    expect(tester.widget<PollComposerPill>(pill).highlighted, isTrue);
    expect(_composerEditable(tester).showCursor, isFalse);
    expect(find.byType(PollComposerPill), findsOneWidget);

    composer.text.clearKeyboardPillSelection();
    composer.text.selection = TextSelection.collapsed(offset: block.start);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(composer.text.selection.extentOffset, block.start);
    expect(tester.widget<PollComposerPill>(pill).highlighted, isTrue);
    expect(_composerEditable(tester).showCursor, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(composer.text.selection.extentOffset, block.start);
    expect(tester.widget<PollComposerPill>(pill).highlighted, isTrue);
    expect(_composerEditable(tester).showCursor, isFalse);
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

  testWidgets('typing on a newly inserted poll after-line keeps the pill', (
    tester,
  ) async {
    const poll = '[poll]\n* Soup\n* Salad\n[/poll]';
    final shell = await _openComposer();
    addTearDown(shell.dispose);
    final composer = shell.visibleComposer!;
    composer.text.value = insertVerifiedPoll(
      current: composer.text.value,
      expectedDocument: '',
      expectedSelection: const TextSelection.collapsed(offset: 0),
      markup: poll,
    ).value;

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

    expect(composer.text.text, '$poll\n');
    expect(composer.text.selection.extentOffset, poll.length + 1);
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: '$poll\nNext line',
        selection: TextSelection.collapsed(offset: '$poll\nNext line'.length),
      ),
    );
    await tester.pump();

    expect(find.byType(PollComposerPill), findsOneWidget);
    expect(composer.text.pollBlocks, hasLength(1));
    expect(composer.text.text, '$poll\nNext line');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('typing before a poll creates a preceding caret line', (
    tester,
  ) async {
    const poll = '[poll]\n* Soup\n* Salad\n[/poll]';
    const source = '$poll\n';
    const typed = 'Before';
    final shell = await _openComposer();
    addTearDown(shell.dispose);
    final composer = shell.visibleComposer!;
    composer.text.value = const TextEditingValue(
      text: source,
      selection: TextSelection.collapsed(offset: 0),
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
    expect(_composerEditable(tester).showCursor, isTrue);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '$typed$source',
        selection: TextSelection.collapsed(offset: typed.length),
      ),
    );
    await tester.pump();

    expect(composer.text.text, '$typed\n$source');
    expect(composer.text.selection.extentOffset, typed.length);
    expect(composer.text.pollBlocks, hasLength(1));
    expect(composer.text.pollBlocks.single.start, typed.length + 1);
    expect(
      composer.text.isPollCollapsed(composer.text.pollBlocks.single),
      true,
    );
    expect(find.byType(PollComposerPill), findsOneWidget);
    expect(composer.text.keyboardSelectedPoll, isNull);
    expect(_composerEditable(tester).showCursor, isTrue);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a selected poll blocks every other key and text input', (
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
    final poll = composer.text.pollBlocks.single;
    final afterPoll = composer.text.pollCaretAfter(poll);
    composer.text.selection = TextSelection.collapsed(offset: afterPoll);
    composer.focus.requestFocus();
    composer.autocomplete.update(
      const TextEditingValue(
        text: ':item',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    expect(composer.autocomplete.trigger, isNotNull);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();

    final selectedValue = composer.text.value;
    final pill = find.byType(PollComposerPill);
    expect(composer.autocomplete.trigger, isNull);
    void expectLocked() {
      expect(composer.text.value, selectedValue);
      expect(composer.text.keyboardSelectedPoll, isNotNull);
      expect(
        composer.text.isPollCollapsed(composer.text.pollBlocks.single),
        true,
      );
      expect(tester.widget<PollComposerPill>(pill).highlighted, isTrue);
      expect(_composerEditable(tester).showCursor, isFalse);
      expect(composer.focus.hasFocus, isTrue);
      expect(shell.visibleComposer, same(composer));
      expect(find.text('Edit poll'), findsNothing);
    }

    expectLocked();
    for (final key in [
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.delete,
      LogicalKeyboardKey.escape,
      LogicalKeyboardKey.tab,
      LogicalKeyboardKey.keyA,
    ]) {
      expect(
        await tester.sendKeyEvent(
          key,
          character: key == LogicalKeyboardKey.keyA ? 'a' : null,
        ),
        isTrue,
      );
      await tester.pump();
      expectLocked();
    }

    expect(await tester.sendKeyDownEvent(LogicalKeyboardKey.delete), isTrue);
    expect(await tester.sendKeyRepeatEvent(LogicalKeyboardKey.delete), isTrue);
    expect(await tester.sendKeyUpEvent(LogicalKeyboardKey.delete), isTrue);
    await tester.pump();
    expectLocked();

    expect(
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft),
      isTrue,
    );
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isTrue);
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.backspace), isTrue);
    expect(await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft), isTrue);
    await tester.pump();
    expectLocked();

    final caret = selectedValue.selection.extentOffset;
    for (final inserted in ['x', 'pasted text', 'k']) {
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: selectedValue.text.replaceRange(caret, caret, inserted),
          selection: TextSelection.collapsed(offset: caret + inserted.length),
          composing: inserted == 'k'
              ? TextRange(start: caret, end: caret + 1)
              : TextRange.empty,
        ),
      );
      await tester.pump();
      expectLocked();
    }
    for (final value in [
      selectedValue.copyWith(
        selection: const TextSelection.collapsed(offset: 0),
      ),
      selectedValue.copyWith(composing: const TextRange(start: 0, end: 1)),
    ]) {
      tester.testTextInput.updateEditingValue(value);
      await tester.pump();
      expectLocked();
    }
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('boundary deletes select an LF or CRLF poll before removing it', (
    tester,
  ) async {
    const poll = '[poll]\n* Soup\n* Salad\n[/poll]';
    for (final lineEnding in ['\n', '\r\n']) {
      final shell = await _openComposer();
      addTearDown(shell.dispose);
      final composer = shell.visibleComposer!;
      final source = '$poll$lineEnding';
      composer.text.value = TextEditingValue(
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
      composer.focus.requestFocus();
      await tester.pump();

      final block = composer.text.pollBlocks.single;
      final afterPoll = composer.text.pollCaretAfter(block);
      expect(afterPoll, source.length);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(composer.text.text, source);
      expect(composer.text.selection.extentOffset, afterPoll);
      expect(
        tester
            .widget<PollComposerPill>(find.byType(PollComposerPill))
            .highlighted,
        isTrue,
      );
      expect(_composerEditable(tester).showCursor, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(_composerEditable(tester).showCursor, isFalse);
      expect(composer.text.keyboardSelectedPoll, isNotNull);
      expect(composer.text.selection.extentOffset, afterPoll);
      composer.text.clearKeyboardPillSelection();
      await tester.pump();
      expect(_composerEditable(tester).showCursor, isTrue);
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: '${source}Next line',
          selection: TextSelection.collapsed(
            offset: '${source}Next line'.length,
          ),
        ),
      );
      await tester.pump();
      expect(composer.text.text, '${source}Next line');
      expect(find.byType(PollComposerPill), findsOneWidget);

      composer.text.value = TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: block.start),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();

      expect(composer.text.text, source);
      expect(composer.text.selection.extentOffset, block.start);
      expect(
        tester
            .widget<PollComposerPill>(find.byType(PollComposerPill))
            .highlighted,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(composer.text.text, source);
      expect(composer.text.keyboardSelectedPoll, isNotNull);
    }
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

  testWidgets('backspace on a selected poll removes the whole poll', (
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

    final poll = composer.text.pollBlocks.single;
    composer.text.selection = TextSelection.collapsed(offset: poll.end);
    composer.focus.requestFocus();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(
      tester
          .widget<PollComposerPill>(find.byType(PollComposerPill))
          .highlighted,
      isTrue,
    );
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
      isFalse,
    );
    expect(find.text('Edit date and time'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(composer.text.selection.extentOffset, block.start);
    expect(
      tester
          .widget<LocalDateComposerPill>(find.byType(LocalDateComposerPill))
          .highlighted,
      isTrue,
    );
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
