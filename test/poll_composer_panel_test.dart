import 'dart:async';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/bundled_plugin_manifest.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_composer_pill.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_settings.dart';
import 'package:discourse_native/src/plugins/poll/poll_composer_editor.dart';
import 'package:discourse_native/src/plugins/poll/poll_composer_pill.dart';
import 'package:discourse_native/src/plugins/poll/poll_data.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/pill.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
final _localDatesConfig = SiteConfig(
  plugins: PluginData.none.withValue(
    localDatesSettingsDataKey,
    const LocalDatesSettings(enabled: true),
  ),
);
final _pollUser = DiscourseUser(
  id: 7,
  username: 'reader',
  plugins: PluginData.none.withValue(
    pollCurrentUserDataKey,
    const PollCurrentUser(canCreatePoll: true),
  ),
);
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

final class _RecordingNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushedRoutes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route);
  }
}

Future<ShellController> _openComposer({
  FakeDiscourseApi? api,
  DiscourseUser storedUser = const DiscourseUser(id: 7, username: 'reader'),
}) async {
  final authenticator = FakeAuthenticator()..keys[_site] = 'api-key';
  final discourseApi =
      api ??
      FakeDiscourseApi(
        user: _pollUser,
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
    plugins: PluginInstaller.install(bundledPluginManifest),
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

BoxDecoration _pollPillDecoration(WidgetTester tester) =>
    tester
            .widget<Container>(
              find.descendant(
                of: find.byType(PollComposerPill),
                matching: find.byType(Container),
              ),
            )
            .decoration!
        as BoxDecoration;

Future<void> _closeComposerDuringProjectedEdit(
  WidgetTester tester, {
  required bool poll,
  required String source,
  required String dialogTitle,
}) async {
  final shell = await _openComposer();
  addTearDown(shell.dispose);
  final composer = shell.visibleComposer!;
  composer.text.value = TextEditingValue(
    text: source,
    selection: TextSelection.collapsed(offset: source.length),
  );

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: ShellScope(
        controller: shell,
        child: Scaffold(
          body: ListenableBuilder(
            listenable: shell,
            builder: (context, _) {
              final visible = shell.visibleComposer;
              return visible == null
                  ? const SizedBox.shrink()
                  : ComposerPanel(composer: visible);
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();

  final pill = poll
      ? find.byType(PollComposerPill)
      : find.byType(LocalDateComposerPill);
  final (start, end) = poll
      ? () {
          final block = composer.text.pollBlocks.single;
          return (block.start, block.end);
        }()
      : () {
          final block = composer.text.localDateBlocks.single;
          return (block.start, block.end);
        }();
  final gesture = await tester.startGesture(tester.getCenter(pill));
  composer.text.selection = TextSelection.collapsed(offset: start + 1);
  await tester.pump();
  await gesture.up();
  await tester.pump();
  composer.text.selection = TextSelection.collapsed(offset: end - 1);
  await tester.pump(const Duration(milliseconds: 500));
  expect(find.text(dialogTitle), findsOneWidget);

  shell.closeComposer();
  await tester.pump();
  expect(find.byType(ComposerPanel), findsNothing);
  expect(find.text(dialogTitle), findsOneWidget);

  await tester.tap(find.byTooltip('Close'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _closeComposerAfterAssertions(
  WidgetTester tester,
  ShellController shell,
) async {
  shell.closeComposer();
  await tester.pump();
}

void main() {
  setUpAll(LocalDateEnvironment.instance.ensureDatabase);
  setUp(() => LocalDateEnvironment.instance.setDeviceTimezone('Etc/UTC'));

  group('toolbar capability gating', () {
    testWidgets('local-date action and Ctrl+Shift+. follow the site setting', (
      tester,
    ) async {
      const tooltip = 'Insert date/time  Ctrl Shift .';
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
      expect(find.byTooltip(tooltip), findsNothing);

      final enabled = await _openComposer(
        api: FakeDiscourseApi(
          user: const DiscourseUser(id: 7, username: 'reader'),
          feeds: const {'/latest.json': <Topic>[]},
          topics: {7: topicPayload(id: 7, title: 'Lunch', canCreatePost: true)},
          siteConfigs: {_site: _localDatesConfig},
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
      expect(find.byTooltip(tooltip), findsOneWidget);

      await tester.tap(find.byType(TextField).last);
      await tester.pump();

      // Bare Shift+. must remain available to the text input plugin as `>`.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      expect(
        await tester.sendKeyDownEvent(
          LogicalKeyboardKey.period,
          character: '>',
        ),
        isFalse,
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.period);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(enabled.visibleComposer!.text.text, isEmpty);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '>',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      await tester.pump();
      expect(enabled.visibleComposer!.text.text, '>');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.period);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(enabled.visibleComposer!.text.text, contains('[date='));
      expect(find.byType(LocalDateComposerPill), findsOneWidget);
      await _closeComposerAfterAssertions(tester, enabled);
      disabled.closeComposer();
    });

    testWidgets(
      'poll action waits for and reacts to a fresh session capability',
      (tester) async {
        final api = _GatedCurrentUserApi();
        final shell = await _openComposer(api: api, storedUser: _pollUser);
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

        api.response.complete(_pollUser);
        for (var frame = 0; frame < 4; frame++) {
          await tester.pump(const Duration(milliseconds: 1));
        }

        expect(find.byTooltip('Add poll'), findsOneWidget);
      },
    );
  });

  group('poll editor activation and lifecycle', () {
    testWidgets('tap opens the editor without exposing projected source', (
      tester,
    ) async {
      final shell = await _openComposer();
      addTearDown(shell.dispose);
      final composer = shell.visibleComposer!;
      composer.text.value = const TextEditingValue(
        text: _source,
        selection: TextSelection.collapsed(offset: _source.length),
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
      final gesture = await tester.startGesture(tester.getCenter(pill));
      final block = composer.text.pollBlocks.single;
      // EditableText may rebuild before or after its desktop tap callback.
      composer.text.selection = TextSelection.collapsed(
        offset: block.start + 1,
      );
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
      expect(find.text('Edit as raw'), findsNothing);
      expect(composer.text.text, _source);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await _closeComposerAfterAssertions(tester, shell);
    });

    testWidgets('arrow-key traversal and Enter preserve atomic selection', (
      tester,
    ) async {
      final shell = await _openComposer();
      addTearDown(shell.dispose);
      final composer = shell.visibleComposer!;
      composer.text.value = const TextEditingValue(
        text: _source,
        selection: TextSelection.collapsed(offset: _source.length),
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
      final block = composer.text.pollBlocks.single;

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
      expect(composer.text.selection.extentOffset, block.start);
      expect(composer.text.keyboardSelectedPoll, isNull);
      expect(tester.widget<PollComposerPill>(pill).highlighted, isFalse);
      expect(_composerEditable(tester).showCursor, isTrue);
      expect(find.byType(PollComposerPill), findsOneWidget);

      composer.text.selection = TextSelection.collapsed(offset: block.start);
      await tester.pump();
      expect(
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight),
        isTrue,
      );
      await tester.pump();
      expect(composer.text.selection.extentOffset, block.start);
      expect(tester.widget<PollComposerPill>(pill).highlighted, isTrue);
      expect(_composerEditable(tester).showCursor, isFalse);

      expect(
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight),
        isTrue,
      );
      await tester.pump();
      expect(composer.text.selection.extentOffset, afterPoll);
      expect(composer.text.keyboardSelectedPoll, isNull);
      expect(tester.widget<PollComposerPill>(pill).highlighted, isFalse);
      expect(_composerEditable(tester).showCursor, isTrue);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);

      composer.text.selection = TextSelection.collapsed(
        offset: block.start - 1,
      );
      await tester.pump();
      expect(
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight),
        isTrue,
      );
      await tester.pump();
      expect(composer.text.selection.extentOffset, block.start);
      expect(composer.text.keyboardSelectedPoll, isNull);
      expect(find.byType(PollComposerPill), findsOneWidget);

      expect(
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight),
        isTrue,
      );
      await tester.pump();
      expect(composer.text.selection.extentOffset, block.start);
      expect(composer.text.keyboardSelectedPoll, isNotNull);
      expect(tester.widget<PollComposerPill>(pill).highlighted, isTrue);

      expect(
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight),
        isTrue,
      );
      await tester.pump();
      expect(composer.text.selection.extentOffset, afterPoll);
      expect(composer.text.keyboardSelectedPoll, isNull);
      expect(tester.widget<PollComposerPill>(pill).highlighted, isFalse);
      expect(find.byType(PollComposerPill), findsOneWidget);

      expect(
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight),
        isTrue,
      );
      await tester.pump();
      expect(composer.text.selection.extentOffset, afterPoll + 1);
      expect(find.byType(PollComposerPill), findsOneWidget);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);

      composer.text.selection = TextSelection.collapsed(offset: afterPoll + 1);
      expect(
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft),
        isTrue,
      );
      await tester.pump();
      expect(composer.text.selection.extentOffset, afterPoll);
      expect(composer.text.keyboardSelectedPoll, isNull);

      expect(
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowLeft),
        isTrue,
      );
      await tester.pump();
      expect(composer.text.selection.extentOffset, afterPoll);
      expect(composer.text.keyboardSelectedPoll, isNotNull);
      expect(tester.widget<PollComposerPill>(pill).highlighted, isTrue);

      expect(
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowLeft),
        isTrue,
      );
      await tester.pump();
      expect(composer.text.selection.extentOffset, block.start);
      expect(composer.text.keyboardSelectedPoll, isNull);
      expect(find.byType(PollComposerPill), findsOneWidget);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);

      composer.text.selection = TextSelection.collapsed(offset: block.start);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(composer.text.keyboardSelectedPoll, isNotNull);

      final selectedValue = composer.text.value;
      final selectedCaret = selectedValue.selection.extentOffset;
      expect(await tester.sendKeyDownEvent(LogicalKeyboardKey.enter), isTrue);
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: selectedValue.text.replaceRange(
            selectedCaret,
            selectedCaret,
            '\n',
          ),
          selection: TextSelection.collapsed(offset: selectedCaret + 1),
        ),
      );
      expect(await tester.sendKeyUpEvent(LogicalKeyboardKey.enter), isTrue);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Edit poll'), findsOneWidget);
      Navigator.of(tester.element(find.text('Edit poll'))).pop();
      await tester.pumpAndSettle();
      expect(find.text('Edit poll'), findsNothing);
      expect(composer.text.value, selectedValue);
      expect(composer.text.keyboardSelectedPoll, isNotNull);
      expect(
        composer.text.isPollCollapsed(composer.text.pollBlocks.single),
        true,
      );
      expect(tester.widget<PollComposerPill>(pill).highlighted, isTrue);
      expect(_composerEditable(tester).showCursor, isFalse);
      await _closeComposerAfterAssertions(tester, shell);
    });

    testWidgets('vertical arrows leave a selected projected component', (
      tester,
    ) async {
      final shell = await _openComposer();
      addTearDown(shell.dispose);
      final composer = shell.visibleComposer!;
      composer.text.value = const TextEditingValue(
        text: _source,
        selection: TextSelection.collapsed(offset: _source.length),
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

      final block = composer.text.pollBlocks.single;
      final occurrence = composer.text.syntaxBlocks.singleWhere(
        (candidate) => candidate.start == block.start,
      );
      composer.focus.requestFocus();
      for (final (key, expectedOffset) in [
        (LogicalKeyboardKey.arrowUp, block.start),
        (LogicalKeyboardKey.arrowDown, composer.text.pollCaretAfter(block)),
      ]) {
        composer.text.selectPillForKeyboard(occurrence);
        await tester.pump();
        expect(composer.text.keyboardSelectedPoll, isNotNull);
        expect(_composerEditable(tester).showCursor, isFalse);

        await tester.sendKeyEvent(key);
        await tester.pump();

        expect(
          composer.text.selection,
          TextSelection.collapsed(offset: expectedOffset),
        );
        expect(composer.text.keyboardSelectedPoll, isNull);
        expect(_composerEditable(tester).showCursor, isTrue);
      }

      await _closeComposerAfterAssertions(tester, shell);
    });

    testWidgets('closing the composer during a poll edit is disposal-safe', (
      tester,
    ) async {
      await _closeComposerDuringProjectedEdit(
        tester,
        poll: true,
        source: _source,
        dialogTitle: 'Edit poll',
      );
    });

    testWidgets('desktop mouse click opens the poll editor', (tester) async {
      final shell = await _openComposer();
      addTearDown(shell.dispose);
      final navigatorObserver = _RecordingNavigatorObserver();
      final composer = shell.visibleComposer!;
      composer.text.value = const TextEditingValue(
        text: _source,
        selection: TextSelection.collapsed(offset: _source.length),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          navigatorObservers: [navigatorObserver],
          home: ShellScope(
            controller: shell,
            child: Scaffold(body: ComposerPanel(composer: composer)),
          ),
        ),
      );
      await tester.pump();
      expect(navigatorObserver.pushedRoutes, hasLength(1));

      final pill = find.byType(PollComposerPill);
      final poll = composer.text.pollBlocks.single;
      composer.text.selection = TextSelection.collapsed(
        offset: composer.text.pollCaretAfter(poll),
      );
      await tester.pump();
      final position = tester.getCenter(pill);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: position);
      addTearDown(mouse.removePointer);
      await tester.pump();
      await mouse.down(position);
      await tester.pump();
      await mouse.up();
      await Future<void>.value();
      expect(navigatorObserver.pushedRoutes, hasLength(2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Edit poll'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await _closeComposerAfterAssertions(tester, shell);
    });
  });

  group('poll pill pointer and caret behavior', () {
    testWidgets('tapping immediately after the pill moves to the next line', (
      tester,
    ) async {
      final shell = await _openComposer();
      addTearDown(shell.dispose);
      final composer = shell.visibleComposer!;
      composer.text.value = const TextEditingValue(
        text: _source,
        selection: TextSelection.collapsed(offset: _source.length),
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
      final block = composer.text.pollBlocks.single;
      final gesture = await tester.startGesture(
        Offset(pillRect.right + 1, pillRect.center.dy),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(find.byType(PollComposerPill), findsOneWidget);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(PollComposerPill), findsOneWidget);
      expect(find.text('Edit poll'), findsNothing);
      expect(composer.text.text, _source);
      expect(
        composer.text.selection.extentOffset,
        composer.text.pollCaretAfter(block),
      );
      expect(composer.text.keyboardSelectedPoll, isNull);
      expect(_composerEditable(tester).showCursor, isTrue);
      await _closeComposerAfterAssertions(tester, shell);
    });

    testWidgets('rapid clicks after the pill never reveal or activate it', (
      tester,
    ) async {
      final shell = await _openComposer();
      addTearDown(shell.dispose);
      final composer = shell.visibleComposer!;
      composer.text.value = const TextEditingValue(
        text: _source,
        selection: TextSelection.collapsed(offset: _source.length),
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
      final block = composer.text.pollBlocks.single;
      final pillRect = tester.getRect(pill);
      final position = Offset(pillRect.right + 1, pillRect.center.dy);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: position);
      addTearDown(mouse.removePointer);

      for (var click = 0; click < 3; click++) {
        await mouse.down(position);
        await tester.pump(kPressTimeout + const Duration(milliseconds: 1));
        expect(
          find.byType(PollComposerPill),
          findsOneWidget,
          reason: 'the pill expanded on pointer-down ${click + 1}',
        );
        expect(composer.text.isPollCollapsed(block), isTrue);
        expect(find.text('Edit poll'), findsNothing);
        await mouse.up();
        await tester.pump();
        await tester.pump();
        expect(find.byType(PollComposerPill), findsOneWidget);
        expect(find.text('Edit poll'), findsNothing);
      }
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 1));

      expect(find.byType(PollComposerPill), findsOneWidget);
      expect(find.text('Edit poll'), findsNothing);
      expect(composer.text.text, _source);
      expect(
        composer.text.selection,
        TextSelection.collapsed(offset: composer.text.pollCaretAfter(block)),
      );
      await _closeComposerAfterAssertions(tester, shell);
    });

    for (final lineEnding in const {'LF': '\n', 'CRLF': '\r\n'}.entries) {
      testWidgets(
        'rapid clicks after an EOF poll keep the ${lineEnding.key} caret line',
        (tester) async {
          final poll = [
            '[poll]',
            '* Soup',
            '* Salad',
            '[/poll]',
          ].join(lineEnding.value);
          final shell = await _openComposer();
          addTearDown(shell.dispose);
          final composer = shell.visibleComposer!;
          composer.text.value = TextEditingValue(
            text: poll,
            selection: TextSelection.collapsed(offset: poll.length),
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

          final pillRect = tester.getRect(find.byType(PollComposerPill));
          final position = Offset(pillRect.right + 1, pillRect.center.dy);
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: position);
          addTearDown(mouse.removePointer);

          await mouse.down(position);
          await tester.pump(kPressTimeout + const Duration(milliseconds: 1));
          expect(find.byType(PollComposerPill), findsOneWidget);
          await mouse.up();

          // Re-click before the appended source line has been laid out.
          final expected = '$poll${lineEnding.value}';
          expect(composer.text.text, expected);

          await mouse.down(position);
          await tester.pump(kPressTimeout + const Duration(milliseconds: 1));
          expect(find.byType(PollComposerPill), findsOneWidget);
          expect(find.text('Edit poll'), findsNothing);
          await mouse.up();
          await tester.pump();
          await tester.pump();

          final block = composer.text.pollBlocks.single;
          expect(find.byType(PollComposerPill), findsOneWidget);
          expect(find.text('Edit poll'), findsNothing);
          expect(composer.text.text, expected);
          expect(composer.text.selection.extentOffset, expected.length);
          expect(composer.text.pollCaretAfter(block), expected.length);
          expect(composer.text.isPollCollapsed(block), isTrue);
          await _closeComposerAfterAssertions(tester, shell);
        },
      );
    }

    for (final lineEnding in const {'LF': '\n', 'CRLF': '\r\n'}.entries) {
      testWidgets(
        'tapping after an EOF poll creates its ${lineEnding.key} caret line',
        (tester) async {
          final poll = [
            '[poll]',
            '* Soup',
            '* Salad',
            '[/poll]',
          ].join(lineEnding.value);
          final shell = await _openComposer();
          addTearDown(shell.dispose);
          final composer = shell.visibleComposer!;
          composer.text.value = TextEditingValue(
            text: poll,
            selection: TextSelection.collapsed(offset: poll.length),
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
          final gesture = await tester.startGesture(
            Offset(pillRect.right + 1, pillRect.center.dy),
            kind: PointerDeviceKind.mouse,
          );
          await tester.pump();
          expect(find.byType(PollComposerPill), findsOneWidget);
          await gesture.up();
          await tester.pump(const Duration(milliseconds: 500));

          final expected = '$poll${lineEnding.value}';
          final block = composer.text.pollBlocks.single;
          expect(find.text('Edit poll'), findsNothing);
          expect(composer.text.text, expected);
          expect(composer.text.selection.extentOffset, expected.length);
          expect(composer.text.pollCaretAfter(block), expected.length);
          expect(composer.text.isPollCollapsed(block), isTrue);
          expect(composer.text.keyboardSelectedPoll, isNull);
          expect(_composerEditable(tester).showCursor, isTrue);
          await _closeComposerAfterAssertions(tester, shell);
        },
      );
    }

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
        const TextEditingValue(
          text: '$poll\nNext line',
          selection: TextSelection.collapsed(offset: '$poll\nNext line'.length),
        ),
      );
      await tester.pump();

      expect(find.byType(PollComposerPill), findsOneWidget);
      expect(composer.text.pollBlocks, hasLength(1));
      expect(composer.text.text, '$poll\nNext line');
      await _closeComposerAfterAssertions(tester, shell);
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
      await _closeComposerAfterAssertions(tester, shell);
    });

    testWidgets('hovering the pill changes its fill without opening a menu', (
      tester,
    ) async {
      final shell = await _openComposer();
      addTearDown(shell.dispose);
      final composer = shell.visibleComposer!;
      composer.text.value = const TextEditingValue(
        text: _source,
        selection: TextSelection.collapsed(offset: _source.length),
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

      final theme = Theme.of(tester.element(find.byType(PollComposerPill)));
      final expectedHover = Color.alphaBlend(
        theme.colorScheme.onSurface.withValues(alpha: 0.08),
        theme.shell.mention,
      );
      final sourceBefore = composer.text.value;
      final rectBefore = tester.getRect(find.byType(Pill));
      expect(_pollPillDecoration(tester).color, theme.shell.mention);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byType(PollComposerPill)));
      await tester.pump();

      expect(_pollPillDecoration(tester).color, expectedHover);
      expect(tester.getRect(find.byType(Pill)), rectBefore);
      expect(composer.text.value, sourceBefore);
      expect(find.byTooltip('Edit poll'), findsNothing);
      expect(find.byTooltip('Remove poll'), findsNothing);
      expect(
        composer.text.isPollCollapsed(composer.text.pollBlocks.single),
        isTrue,
      );
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(_pollPillDecoration(tester).color, theme.shell.mention);
      expect(tester.getRect(find.byType(Pill)), rectBefore);
      await _closeComposerAfterAssertions(tester, shell);
    });
  });

  group('poll selection and editing guards', () {
    testWidgets('a selected poll blocks deletion keys and text input', (
      tester,
    ) async {
      final shell = await _openComposer();
      addTearDown(shell.dispose);
      final composer = shell.visibleComposer!;
      composer.text.value = const TextEditingValue(
        text: _source,
        selection: TextSelection.collapsed(offset: _source.length),
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
      for (final key in [LogicalKeyboardKey.delete, LogicalKeyboardKey.keyA]) {
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
      expect(
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.delete),
        isTrue,
      );
      expect(await tester.sendKeyUpEvent(LogicalKeyboardKey.delete), isTrue);
      await tester.pump();
      expectLocked();

      // Editing shortcuts would otherwise delete collapsed source markup.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.backspace), isTrue);
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.delete), isTrue);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
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
      await _closeComposerAfterAssertions(tester, shell);
    });

    testWidgets(
      'keep the keyboard submit shortcut active while a poll pill is selected',
      (tester) async {
        final api = FakeDiscourseApi(
          user: _pollUser,
          feeds: const {'/latest.json': <Topic>[]},
          topics: {7: topicPayload(id: 7, title: 'Lunch', canCreatePost: true)},
          siteConfigs: const {_site: SiteConfig.unknown()},
        );
        final shell = await _openComposer(api: api);
        addTearDown(shell.dispose);
        final composer = shell.visibleComposer!;
        composer.text.value = const TextEditingValue(
          text: _source,
          selection: TextSelection.collapsed(offset: _source.length),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: ShellScope(
              controller: shell,
              child: Scaffold(
                body: ListenableBuilder(
                  listenable: shell,
                  builder: (context, _) {
                    final visible = shell.visibleComposer;
                    return visible == null
                        ? const SizedBox.shrink()
                        : ComposerPanel(composer: visible);
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final poll = composer.text.pollBlocks.single;
        composer.text.selection = TextSelection.collapsed(
          offset: composer.text.pollCaretAfter(poll),
        );
        composer.focus.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(composer.text.keyboardSelectedPoll, isNotNull);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        for (var frame = 0; frame < 6; frame++) {
          await tester.pump();
        }

        expect(api.created, hasLength(1));
        expect(api.created.single['raw'], _source);
        expect(shell.visibleComposer, isNull);
        expect(find.byType(ComposerPanel), findsNothing);
      },
    );

    testWidgets('undo remains available while a poll pill is selected', (
      tester,
    ) async {
      final shell = await _openComposer();
      addTearDown(shell.dispose);
      final composer = shell.visibleComposer!;
      composer.text.value = const TextEditingValue(
        text: '$_source!',
        selection: TextSelection.collapsed(offset: _source.length + 1),
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
      await tester.pump(const Duration(milliseconds: 600));

      composer.text.value = const TextEditingValue(
        text: '$_source!?',
        selection: TextSelection.collapsed(offset: _source.length + 2),
      );
      await tester.pump(const Duration(milliseconds: 600));

      final poll = composer.text.pollBlocks.single;
      composer.text.selection = TextSelection.collapsed(
        offset: composer.text.pollCaretAfter(poll),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(composer.text.keyboardSelectedPoll, isNotNull);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(composer.text.text, '$_source!');
      expect(composer.text.keyboardSelectedPoll, isNull);
      await _closeComposerAfterAssertions(tester, shell);
    });

    testWidgets(
      'escape still closes the composer while a poll pill is selected',
      (tester) async {
        final shell = await _openComposer();
        addTearDown(shell.dispose);
        final composer = shell.visibleComposer!;
        composer.text.value = const TextEditingValue(
          text: _source,
          selection: TextSelection.collapsed(offset: _source.length),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: ShellScope(
              controller: shell,
              child: Scaffold(
                body: ListenableBuilder(
                  listenable: shell,
                  builder: (context, _) {
                    final visible = shell.visibleComposer;
                    return visible == null
                        ? const SizedBox.shrink()
                        : ComposerPanel(composer: visible);
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final poll = composer.text.pollBlocks.single;
        composer.text.selection = TextSelection.collapsed(
          offset: composer.text.pollCaretAfter(poll),
        );
        composer.focus.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(composer.text.keyboardSelectedPoll, isNotNull);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();

        expect(shell.visibleComposer, isNull);
        expect(find.byType(ComposerPanel), findsNothing);
      },
    );

    for (final lineEnding in const {'LF': '\n', 'CRLF': '\r\n'}.entries) {
      testWidgets(
        'boundary deletes select polls across ${lineEnding.key} line endings',
        (tester) async {
          const poll = '[poll]\n* Soup\n* Salad\n[/poll]';
          final shell = await _openComposer();
          addTearDown(shell.dispose);
          final composer = shell.visibleComposer!;
          final source = '$poll${lineEnding.value}';
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
          expect(_composerEditable(tester).showCursor, isTrue);
          expect(composer.text.keyboardSelectedPoll, isNull);
          expect(composer.text.selection.extentOffset, afterPoll);
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
          await _closeComposerAfterAssertions(tester, shell);
        },
      );
    }

    testWidgets('backspace on a selected poll removes the whole poll', (
      tester,
    ) async {
      final shell = await _openComposer();
      addTearDown(shell.dispose);
      final composer = shell.visibleComposer!;
      composer.text.value = const TextEditingValue(
        text: _source,
        selection: TextSelection.collapsed(offset: _source.length),
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
      await _closeComposerAfterAssertions(tester, shell);
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
      expect(composer.text.selection, const TextSelection.collapsed(offset: 4));
      await _closeComposerAfterAssertions(tester, shell);
    });
  });

  group('local-date pill interaction', () {
    testWidgets('closing the composer during an edit is disposal-safe', (
      tester,
    ) async {
      await _closeComposerDuringProjectedEdit(
        tester,
        poll: false,
        source: 'Before [date=2026-08-11 time=09:00:00 timezone=UTC] after',
        dialogTitle: 'Edit date and time',
      );
    });

    testWidgets('tap opens the editor without exposing projected source', (
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
      composer.text.selection = TextSelection.collapsed(
        offset: block.start + 1,
      );
      await tester.pump();
      expect(find.byType(LocalDateComposerPill), findsOneWidget);
      await gesture.up();
      await tester.pump();
      composer.text.selection = TextSelection.collapsed(offset: block.end - 1);
      await tester.pump();
      expect(find.byType(LocalDateComposerPill), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Edit date and time'), findsOneWidget);
      expect(find.text('Edit as raw'), findsNothing);
      expect(find.byType(LocalDateComposerPill), findsOneWidget);
      expect(composer.text.text, source);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await _closeComposerAfterAssertions(tester, shell);
    });

    testWidgets('keyboard traversal and Backspace preserve atomic editing', (
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

      final block = composer.text.localDateBlocks.single;
      composer.text.selection = TextSelection.collapsed(offset: block.start);
      composer.focus.requestFocus();
      await tester.pump();
      expect(
        tester
            .widget<LocalDateComposerPill>(find.byType(LocalDateComposerPill))
            .highlighted,
        isFalse,
      );
      expect(_composerEditable(tester).showCursor, isTrue);
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
      expect(_composerEditable(tester).showCursor, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(composer.text.selection.extentOffset, block.end);
      expect(composer.text.keyboardSelectedLocalDate, isNull);
      expect(
        tester
            .widget<LocalDateComposerPill>(find.byType(LocalDateComposerPill))
            .highlighted,
        isFalse,
      );
      expect(_composerEditable(tester).showCursor, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(composer.text.keyboardSelectedLocalDate, isNotNull);
      expect(_composerEditable(tester).showCursor, isFalse);
      final selectedValue = composer.text.value;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Edit date and time'), findsOneWidget);
      Navigator.of(tester.element(find.text('Edit date and time'))).pop();
      await tester.pumpAndSettle();
      expect(composer.text.value, selectedValue);
      expect(composer.text.keyboardSelectedLocalDate, isNotNull);
      expect(
        tester
            .widget<LocalDateComposerPill>(find.byType(LocalDateComposerPill))
            .highlighted,
        isTrue,
      );
      expect(_composerEditable(tester).showCursor, isFalse);
      composer.focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(composer.text.text, 'Before  after');
      expect(find.byType(LocalDateComposerPill), findsNothing);
      await _closeComposerAfterAssertions(tester, shell);
    });
  });
}
