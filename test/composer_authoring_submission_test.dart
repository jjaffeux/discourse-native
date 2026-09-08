import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_link.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  for (final editing in [false, true]) {
    final operation = editing ? 'updatePost' : 'createPost';
    for (final (key, control) in [
      (LogicalKeyboardKey.keyB, false),
      (LogicalKeyboardKey.keyI, false),
      (LogicalKeyboardKey.keyE, false),
      (LogicalKeyboardKey.keyB, true),
      (LogicalKeyboardKey.keyI, true),
    ]) {
      testWidgets(
        '$operation rejects ${control ? 'Ctrl' : 'Meta'}+${key.keyLabel} after capture',
        (tester) async {
          final gate = Completer<void>();
          final api = FakeDiscourseApi(
            createPostGate: gate,
            updatePostGate: gate,
          );
          final shell = await _openComposer(api, editing: editing);
          final composer = shell.visibleComposer!;
          await _pumpPanel(tester, shell);
          composer.text.selection = const TextSelection(
            baseOffset: 0,
            extentOffset: 6,
          );
          composer.focus.requestFocus();
          await tester.pumpAndSettle();

          await _shortcut(tester, LogicalKeyboardKey.enter);
          await tester.pump();
          expect(composer.submitting, isTrue);
          final writes = editing ? api.updated : api.created;
          expect(writes.single['raw'], _body);
          expect(
            tester.widget<TextField>(find.byType(TextField)).readOnly,
            isTrue,
          );

          final beforeShortcut = composer.value;
          await _shortcut(tester, key, control: control);
          await tester.pump();
          final afterShortcut = composer.value;
          gate.complete();
          await tester.pumpAndSettle();
          expect(shell.visibleComposer, isNull);
          expect(composer.isDisposed, isTrue);
          expect(writes.single['raw'], _body);
          expect(
            afterShortcut,
            beforeShortcut,
            reason: 'late formatting would be cleared unsent',
          );
        },
      );
    }

    testWidgets(
      '$operation blocks link and toolbar actions, then enables retry editing',
      (tester) async {
        final gate = Completer<void>();
        final api = FakeDiscourseApi(
          createPostGate: gate,
          updatePostGate: gate,
        );
        final shell = await _openComposer(api, editing: editing);
        final composer = shell.visibleComposer!;
        await _pumpPanel(tester, shell);
        composer.text.selection = const TextSelection(
          baseOffset: 0,
          extentOffset: 6,
        );
        composer.focus.requestFocus();
        await tester.pumpAndSettle();
        final toolbar = find.byKey(
          const ValueKey('composer-selection-toolbar'),
        );
        final emoji = find.byKey(const ValueKey('composer-emoji-picker'));
        expect(toolbar, findsOneWidget);
        expect(tester.widget<IconButton>(emoji).onPressed, isNotNull);

        await _shortcut(tester, LogicalKeyboardKey.enter);
        await tester.pump();
        expect(composer.submitting, isTrue);
        expect(toolbar, findsNothing);
        expect(tester.widget<IconButton>(emoji).onPressed, isNull);
        await _shortcut(tester, LogicalKeyboardKey.keyL);
        await tester.pump();
        expect(
          find.byKey(const ValueKey('composer-link-dialog')),
          findsNothing,
        );

        gate.completeError(const WriteException(WriteFailure.conflict));
        await tester.pumpAndSettle();
        expect(composer.isEditing, isTrue);
        expect(
          tester.widget<TextField>(find.byType(TextField)).readOnly,
          isFalse,
        );
        expect(tester.widget<IconButton>(emoji).onPressed, isNotNull);
        expect(toolbar, findsOneWidget);
        await tester.tap(find.byTooltip('Bold'));
        await tester.pumpAndSettle();
        expect(composer.raw, '**A post** ready to submit');
        await composer.flushDraft();
      },
    );

    testWidgets('$operation rejects a link dialog opened before submission', (
      tester,
    ) async {
      final gate = Completer<void>();
      final api = FakeDiscourseApi(createPostGate: gate, updatePostGate: gate);
      final shell = await _openComposer(api, editing: editing);
      final composer = shell.visibleComposer!;
      await _pumpPanel(tester, shell);
      composer.text.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 6,
      );
      composer.focus.requestFocus();
      await tester.pumpAndSettle();
      await _shortcut(tester, LogicalKeyboardKey.keyL);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('composer-link-dialog')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('composer-link-url')),
        'https://discourse.org',
      );

      final submitting = shell.submitComposer();
      await tester.pump();
      expect(composer.submitting, isTrue);
      final beforeCommit = composer.value;
      await tester.tap(find.byKey(const ValueKey('composer-link-insert')));
      await tester.pump();
      expect(composer.value, beforeCommit);
      gate.complete();
      await submitting;
      await tester.pumpAndSettle();
      expect((editing ? api.updated : api.created).single['raw'], _body);
      expect(shell.visibleComposer, isNull);
    });
  }

  for (final state in [
    'loading',
    'checking',
    'closing',
    'discarding',
    'retired',
  ]) {
    testWidgets('$state rejects an open link dialog and projection removal', (
      tester,
    ) async {
      var current = true;
      final shell = await _openComposer(FakeDiscourseApi());
      final composer = ComposerController(
        _target,
        isCurrentComposer: () => current,
      );
      addTearDown(composer.dispose);
      composer.text.value = const TextEditingValue(
        text: '[Discourse](https://discourse.org)',
        selection: TextSelection.collapsed(offset: 0),
      );
      await _pumpPanel(tester, shell);
      final context = tester.element(find.byType(ComposerPanel));
      final projection = const ComposerLinkSyntaxPolicy()
          .parse(composer.raw)
          .single;
      final editing = projection.edit(context, composer);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('composer-link-url')),
        'https://example.com',
      );
      switch (state) {
        case 'loading':
          composer.beginLoadingBody();
        case 'checking':
          composer.checking();
        case 'closing':
          composer.beginClose();
        case 'discarding':
          composer.beginDiscard();
        case 'retired':
          current = false;
      }
      final before = composer.value;
      await tester.tap(find.byKey(const ValueKey('composer-link-insert')));
      await tester.pumpAndSettle();
      await editing;
      projection.remove(context, composer);
      expect(composer.value, before);
      await showComposerLinkDialog(context: context, composer: composer);
      await tester.pump();
      expect(find.byKey(const ValueKey('composer-link-dialog')), findsNothing);
    });
  }

  testWidgets('unresolved retry allows link editing and removal', (
    tester,
  ) async {
    final shell = await _openComposer(FakeDiscourseApi());
    final composer = shell.visibleComposer!;
    await _pumpPanel(tester, shell);
    composer.unresolved();
    composer.text.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 6,
    );
    composer.focus.requestFocus();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isFalse);
    await _shortcut(tester, LogicalKeyboardKey.keyL);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('composer-link-url')),
      'https://discourse.org',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('composer-link-insert')));
    await tester.pumpAndSettle();
    expect(composer.raw, '[A post](https://discourse.org) ready to submit');
    final context = tester.element(find.byType(ComposerPanel));
    const ComposerLinkSyntaxPolicy()
        .parse(composer.raw)
        .single
        .remove(context, composer);
    expect(composer.raw, 'ready to submit');
    await composer.flushDraft();
  });
}

const _site = 'https://meta.discourse.org';
const _body = 'A post ready to submit';
const _target = ComposerTarget(
  siteUrl: _site,
  topicId: 7,
  slug: 'topic',
  topicTitle: 'Topic',
);

Future<ShellController> _openComposer(
  FakeDiscourseApi api, {
  bool editing = false,
}) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance(
        'meta.discourse.org',
      ).copyWith(user: const DiscourseUser(id: 7, username: 'author')),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'api-key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  addTearDown(shell.dispose);
  await shell.load();
  await shell.resolveSiteConfig(_site);
  shell.store.put(
    _site,
    const TopicDetail(id: 7, title: 'Topic', stream: [], canCreatePost: true),
  );
  shell.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
  );
  if (editing) {
    final post = const Post(
      id: 22,
      postNumber: 2,
      username: 'author',
      cooked: '<p>Original body</p>',
      canEdit: true,
    ).withRaw('Original body');
    shell.store.put(_site, post);
    shell.openEdit(post);
  } else {
    shell.openReply();
    await shell.finishComposerDraftRestore(shell.visibleComposer!);
  }
  shell.visibleComposer!.text.text = _body;
  await shell.visibleComposer!.flushDraft();
  return shell;
}

Future<void> _pumpPanel(WidgetTester tester, ShellController shell) =>
    tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
        home: ShellScope(
          controller: shell,
          child: Scaffold(
            body: ListenableBuilder(
              listenable: shell,
              builder: (context, _) {
                if (shell.visibleComposer case final composer?) {
                  return ComposerPanel(composer: composer);
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );

Future<void> _shortcut(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
}) async {
  final modifier = control
      ? LogicalKeyboardKey.controlLeft
      : LogicalKeyboardKey.metaLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(modifier);
}
