import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/draft_store.dart';
import 'package:discourse_native/src/models/composer_placement.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_header.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

final _status = find.byKey(const ValueKey('composer-draft-status'));
final _header = find.byType(ComposerHeader);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final placement in [ComposerPlacement.right, ComposerPlacement.bottom]) {
    testWidgets(
      'autosave stays in the $placement header without moving the editor',
      (tester) async {
        var saved = Completer<int?>();
        final composer = ComposerController(
          _replyTarget,
          onSaveDraft: (_) => saved.future,
        );
        final shell = await _shell();
        addTearDown(composer.dispose);
        addTearDown(shell.dispose);
        await _pump(tester, shell, composer, placement: placement);

        expect(_status, findsNothing);
        final editor = tester.getRect(find.byType(ComposerEditor));
        composer.text.text = 'A draft in progress';
        await tester.pump();
        expect(
          find.descendant(of: _header, matching: find.text('Saving…')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: _status, matching: find.byType(DSpinner)),
          findsOneWidget,
        );
        expect(find.text('Saving draft…'), findsNothing);
        expect(tester.getRect(find.byType(ComposerEditor)), editor);
        final statusBounds = tester.getRect(_status);
        expect(
          tester.getTopRight(find.byKey(const ValueKey('composer-close'))).dx,
          tester.getRect(_header).right - 8,
        );

        final pending = composer.flushDraft();
        await tester.pump();
        saved.complete(1);
        await pending;
        await tester.pump();
        expect(
          find.descendant(of: _header, matching: find.text('Saved')),
          findsOneWidget,
        );
        expect(find.byType(DSpinner), findsNothing);
        expect(find.text('Draft saved'), findsNothing);
        expect(tester.getRect(find.byType(ComposerEditor)), editor);
        expect(tester.getRect(_status), statusBounds);
        expect(tester.getSemantics(_status).label, 'Draft saved on the site');
        expect(
          tester.getSemantics(_status).flagsCollection.isLiveRegion,
          isTrue,
        );

        await _pump(tester, shell, composer, minimized: true);
        expect(_status, findsNothing);
        expect(find.byKey(const ValueKey('composer-close')), findsNothing);
        await _pump(tester, shell, composer, placement: placement);
        expect(find.text('Saved'), findsOneWidget);
        expect(find.byKey(const ValueKey('composer-close')), findsOneWidget);

        saved = Completer<int?>();
        var changes = 0;
        composer.addListener(() => changes++);
        composer.text.text = 'A newer draft in progress';
        await tester.pump();
        expect(find.text('Saved'), findsNothing);
        expect(find.text('Saving…'), findsOneWidget);
        expect(tester.getRect(_status), statusBounds);
        expect(changes, 1);
        composer.text.text = 'A newer draft with another keystroke';
        await tester.pump();
        expect(changes, 1);
        final nextSave = composer.flushDraft();
        saved.complete(2);
        await nextSave;
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final localFailed in [false, true]) {
    testWidgets('save failure remains explicit (local failed: $localFailed)', (
      tester,
    ) async {
      var fail = true;
      final composer = ComposerController(
        _replyTarget,
        onSaveDraft: (_) async {
          if (fail) {
            if (localFailed) throw const DraftWriteException();
            throw StateError('site unavailable');
          }
          return 1;
        },
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pump(tester, shell, composer, width: 320);

      composer.text.text = 'Please keep this draft';
      await composer.flushDraft();
      await tester.pump();
      final label = localFailed ? 'Not saved' : 'Device only';
      final detail = localFailed
          ? "Couldn't save this draft on this device."
          : 'Not saved on the site — kept on this device only.';
      expect(
        find.descendant(of: _header, matching: find.text(label)),
        findsOneWidget,
      );
      expect(find.text(detail), findsOneWidget);
      expect(
        find.descendant(of: _header, matching: find.text(detail)),
        findsNothing,
      );
      expect(find.text('Saved'), findsNothing);

      await _pump(tester, shell, composer, minimized: true);
      expect(_status, findsNothing);
      expect(find.byKey(const ValueKey('composer-close')), findsNothing);
      expect(find.text(detail), findsNothing);

      await _pump(tester, shell, composer);
      fail = false;
      await composer.flushDraft();
      await tester.pump();
      expect(find.text('Saved'), findsOneWidget);
      expect(find.text(label), findsNothing);
      expect(find.text(detail), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'giving up remote sync never reports a later local write as saved',
    (tester) async {
      final composer = ComposerController(
        _replyTarget,
        onSaveDraft: (save) async {
          if (!save.localOnly) throw StateError('site unavailable');
          return null;
        },
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pump(tester, shell, composer);
      composer.text.text = 'A local draft';
      for (
        var attempt = 0;
        attempt < ComposerController.maxDraftFailures;
        attempt++
      ) {
        await composer.flushDraft();
      }
      composer.text.text = 'A newer local draft';
      await tester.pump();
      expect(find.text('Device only'), findsOneWidget);
      await composer.flushDraft();
      await tester.pump();
      expect(find.text('Device only'), findsOneWidget);
      expect(find.text('Saved'), findsNothing);
      expect(find.text('Saving…'), findsNothing);
    },
  );

  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets('header status fits narrow RTL layouts at ${scale}x text', (
      tester,
    ) async {
      final composer = ComposerController(
        _replyTarget,
        onSaveDraft: (_) async => 1,
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.text = 'A saved draft';
      await composer.flushDraft();
      await _pump(
        tester,
        shell,
        composer,
        width: 320,
        scale: scale,
        direction: TextDirection.rtl,
        headerOnly: true,
      );
      expect(tester.getSemantics(_status).label, 'Draft saved on the site');
      expect(find.text('Saved'), scale < 3 ? findsOneWidget : findsNothing);
      final header = tester.getRect(_header);
      final status = tester.getRect(_status);
      expect(header.contains(status.topLeft), isTrue);
      expect(header.contains(status.bottomRight), isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('edit and non-persisted composers have no draft indicator', (
    tester,
  ) async {
    final shell = await _shell();
    addTearDown(shell.dispose);
    final composers = [
      ComposerController(_replyTarget),
      ComposerController(
        const ComposerTarget(
          siteUrl: 'https://meta.discourse.org',
          topicId: 7,
          slug: 'a-topic',
          topicTitle: 'A topic',
          editingPostId: 8,
          editingPostNumber: 2,
        ),
        onSaveDraft: (_) async => 1,
      )..loadedBody('The published post'),
    ];
    for (final composer in composers) {
      addTearDown(composer.dispose);
      await _pump(tester, shell, composer);
      expect(_status, findsNothing);
    }
  });
}

Future<void> _pump(
  WidgetTester tester,
  ShellController shell,
  ComposerController composer, {
  ComposerPlacement placement = ComposerPlacement.right,
  bool minimized = false,
  double width = 420,
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
  bool headerOnly = false,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 650));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: Directionality(textDirection: direction, child: child!),
      ),
      home: ShellScope(
        controller: shell,
        child: Scaffold(
          body: headerOnly
              ? ComposerHeader(
                  composer: composer,
                  minimized: false,
                  onClose: () {},
                  closeTooltip: 'Save and close',
                  onMinimize: () {},
                  onPlacementChanged: (_) {},
                )
              : ComposerPanel(
                  composer: composer,
                  height: 550,
                  placement: placement,
                  minimized: minimized,
                  onMinimize: () {},
                  onRestore: minimized ? () {} : null,
                  onPlacementChanged: (_) {},
                ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<ShellController> _shell() async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore(),
    api: FakeDiscourseApi(),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  return shell;
}

const _replyTarget = ComposerTarget(
  siteUrl: 'https://meta.discourse.org',
  topicId: 7,
  slug: 'a-topic',
  topicTitle: 'A topic',
);
