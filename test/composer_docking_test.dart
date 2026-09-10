import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/composer_layout_store.dart';
import 'package:discourse_native/src/models/composer_placement.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/composer_presentation.dart';
import 'package:discourse_native/src/shell/composer_presentation_controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'preferences restore dock sizes and ignore obsolete floating coordinates',
    () async {
      final first = ComposerPresentationController();
      final second = ComposerPresentationController();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await first.load();
      expect(first.preference.placement, ComposerPlacement.right);
      first.dock(ComposerPlacement.left);
      first.resize(
        placement: ComposerPlacement.left,
        extent: 480,
        topic: false,
      );
      first.resize(
        placement: ComposerPlacement.bottom,
        extent: 350,
        topic: false,
      );
      await first.store.write(first.preference);
      await second.load();
      expect(second.preference.placement, ComposerPlacement.left);
      expect(second.preference.sideWidth, 480);
      expect(second.preference.replyHeight, 350);
      expect(
        second.effectivePlacement(mobile: false, width: 600),
        ComposerPlacement.bottom,
      );
      expect(
        second.effectivePlacement(mobile: false, width: 900),
        ComposerPlacement.left,
      );
      expect(
        second.effectivePlacement(mobile: true, width: 1200),
        ComposerPlacement.bottom,
      );
    },
  );

  test('corrupt dimensions and unknown placement fall back to right', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      ComposerLayoutStore.storageKey,
      '{"placement":"obsolete","sideWidth":420,"replyHeight":280,"topicHeight":380}',
    );
    expect(
      (await const ComposerLayoutStore().read()).placement,
      ComposerPlacement.right,
    );
    await prefs.setString(ComposerLayoutStore.storageKey, '{invalid');
    expect((await const ComposerLayoutStore().read()).sideWidth, 420);
  });

  testWidgets(
    'placement and minimization retain the same editor state and undo history',
    (tester) async {
      final harness = await _Harness.create(tester);
      final composer = harness.shell.visibleComposer!;
      final editor = find.byType(ComposerEditor);
      final state = tester.state(editor);
      final scrollState = tester.element(
        find.byKey(const ValueKey('reader-list')),
      );
      final panel = find.byType(ComposerPanel);
      expect(tester.getSize(panel).width, 420);
      await tester.enterText(
        find.descendant(of: editor, matching: find.byType(EditableText)),
        'First draft',
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.enterText(
        find.descendant(of: editor, matching: find.byType(EditableText)),
        'First draft with more',
      );
      await tester.pump(const Duration(milliseconds: 600));
      composer.text.selection = const TextSelection(
        baseOffset: 6,
        extentOffset: 11,
      );
      final selection = composer.text.selection;
      for (final placement in [
        ComposerPlacement.left,
        ComposerPlacement.bottom,
        ComposerPlacement.right,
      ]) {
        harness.presentation.dock(placement);
        await tester.pumpAndSettle();
        expect(identical(tester.state(editor), state), isTrue);
        expect(
          identical(
            tester.element(find.byKey(const ValueKey('reader-list'))),
            scrollState,
          ),
          isTrue,
        );
        expect(composer.text.selection, selection);
        final reader = tester.getRect(
          find.byKey(const ValueKey('reader-list')),
        );
        final frame = tester.getRect(panel);
        expect(reader.overlaps(frame), isFalse);
        if (placement == ComposerPlacement.left) {
          expect(frame.right, lessThanOrEqualTo(reader.left));
        }
        if (placement == ComposerPlacement.right) {
          expect(frame.left, greaterThanOrEqualTo(reader.right));
        }
        if (placement == ComposerPlacement.bottom) {
          expect(frame.top, greaterThanOrEqualTo(reader.bottom));
        }
      }
      await tester.tap(find.byKey(const ValueKey('composer-minimize')));
      await tester.pumpAndSettle();
      expect(editor, findsNothing);
      expect(find.byKey(const ValueKey('composer-restore')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('composer-restore')));
      await tester.pumpAndSettle();
      expect(identical(tester.state(editor), state), isTrue);
      expect(tester.getSize(panel).width, 420);
      expect(composer.text.selection, selection);
      composer.focus.requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(composer.raw, 'First draft');
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'narrow windows use bottom and restore preferred side and width',
    (tester) async {
      final harness = await _Harness.create(tester);
      harness.presentation.dock(ComposerPlacement.left);
      harness.presentation.resize(
        placement: ComposerPlacement.left,
        extent: 470,
        topic: true,
      );
      await tester.pumpAndSettle();
      await tester.binding.setSurfaceSize(const Size(620, 700));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(ComposerPanel)).width, 620);
      expect(harness.presentation.preference.placement, ComposerPlacement.left);
      expect(harness.presentation.preference.sideWidth, 470);
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(ComposerPanel)).width, 470);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('divider resizes and persists the composer width', (
    tester,
  ) async {
    final harness = await _Harness.create(tester);
    final before = tester.getSize(find.byType(ComposerPanel)).width;
    await tester.drag(find.byType(DResizableHandle), const Offset(-60, 0));
    await tester.pumpAndSettle();
    final after = tester.getSize(find.byType(ComposerPanel)).width;
    expect(after, greaterThan(before));
    expect(harness.presentation.preference.sideWidth, after);
    final stored = await const ComposerLayoutStore().read();
    expect(stored.sideWidth, after);
  });

  testWidgets(
    'A menu selects physical sides in RTL and has accessible icon names',
    (tester) async {
      final harness = await _Harness.create(
        tester,
        direction: TextDirection.rtl,
      );
      final semantics = tester.ensureSemantics();

      await tester.tap(find.byKey(const ValueKey('composer-options')));
      await tester.pumpAndSettle();
      expect(find.text('Dock side'), findsOneWidget);
      expect(find.bySemanticsLabel('Separate window'), findsNothing);
      expect(find.byIcon(Icons.open_in_new), findsNothing);
      for (final placement in ComposerPlacement.values) {
        expect(find.byTooltip(placement.label), findsOneWidget);
      }
      await tester.tap(find.byTooltip('Dock left'));
      await tester.pumpAndSettle();
      expect(harness.presentation.preference.placement, ComposerPlacement.left);
      final frame = tester.getRect(find.byType(ComposerPanel));
      final reader = tester.getRect(find.byKey(const ValueKey('reader-list')));
      expect(frame.right, lessThanOrEqualTo(reader.left));
      expect(find.text('Dock side'), findsNothing);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'mobile hides placement and keeps submit above the visible keyboard',
    (tester) async {
      await _Harness.create(tester, mobile: true, size: const Size(390, 800));
      tester.view.viewInsets = FakeViewPadding(
        bottom: 330 * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      final frame = tester.getRect(find.byType(ComposerPanel));
      expect(frame.width, 390);
      expect(
        tester.getRect(find.byKey(const ValueKey('composer-submit'))).bottom,
        lessThanOrEqualTo(470),
      );
      expect(
        tester.getSize(find.byType(ComposerEditor)).height,
        greaterThan(30),
      );
      await tester.tap(find.byKey(const ValueKey('composer-options')));
      await tester.pumpAndSettle();
      expect(find.text('Dock side'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'large text and a short keyboard viewport keep editing and submission reachable',
    (tester) async {
      await _Harness.create(
        tester,
        mobile: true,
        size: const Size(390, 650),
        textScale: 2,
      );
      tester.view.viewInsets = FakeViewPadding(
        bottom: 330 * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('composer-submit'))).bottom,
        lessThanOrEqualTo(320),
      );
      expect(
        tester.getSize(find.byType(ComposerEditor)).height,
        greaterThan(30),
      );
      expect(tester.takeException(), isNull);
    },
  );
}

class _Harness {
  _Harness(this.shell, this.presentation);
  final ShellController shell;
  final ComposerPresentationController presentation;
  static Future<_Harness> create(
    WidgetTester tester, {
    bool mobile = false,
    Size size = const Size(1000, 700),
    TextDirection direction = TextDirection.ltr,
    double textScale = 1,
  }) async {
    const user = DiscourseUser(id: 7, username: 'sam', canCreateTopic: true);
    final shell = ShellController(
      instanceStore: FakeInstanceStore([
        instance('meta.discourse.org').copyWith(user: user),
      ]),
      api: FakeDiscourseApi(
        user: user,
        feeds: const {'/latest.json': []},
        creatableFeedPaths: const {'/latest.json'},
      ),
      authenticator: FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'key',
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    final presentation = ComposerPresentationController();
    addTearDown(shell.dispose);
    addTearDown(presentation.dispose);
    await shell.load();
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.light.copyWith(
            platform: mobile ? TargetPlatform.iOS : TargetPlatform.linux,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: DToaster(child: child!),
          ),
          home: Scaffold(
            body: DDirection(
              textDirection: direction,
              child: ComposerPresentationHost(
                controller: presentation,
                child: ComposerDock(
                  child: ListView(
                    key: const ValueKey('reader-list'),
                    children: [for (var i = 0; i < 100; i++) Text('Post $i')],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await shell.openNewTopicFromSidebar();
    await tester.pumpAndSettle();
    return _Harness(shell, presentation);
  }
}
