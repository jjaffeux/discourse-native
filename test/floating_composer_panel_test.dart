import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/composer_geometry_store.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('floats at the bottom and stays in bounds while moving', (
    tester,
  ) async {
    final composer = ComposerController(_replyTarget);
    final shell = await _shell();
    addTearDown(composer.dispose);
    addTearDown(shell.dispose);
    await _pumpFloatingPanel(tester, shell, composer);

    final initial = tester.getRect(find.byType(ComposerPanel));
    expect(initial.width, 760);
    expect(initial.height, 220);
    expect(initial.center.dx, 450);
    expect(initial.bottom, 634);

    await tester.drag(
      find.byKey(const ValueKey('composer-drag-handle')),
      const Offset(-48, -72),
    );
    await tester.pump();

    final moved = tester.getRect(find.byType(ComposerPanel));
    expect(moved.left, closeTo(initial.left - 48, 1));
    expect(moved.top, closeTo(initial.top - 72, 1));

    await tester.drag(
      find.byKey(const ValueKey('composer-drag-handle')),
      const Offset(-1000, -1000),
    );
    await tester.pump();

    final constrained = tester.getRect(find.byType(ComposerPanel));
    expect(constrained.left, 16);
    expect(constrained.top, 16);
  });

  testWidgets('resizes from every edge without a visible affordance', (
    tester,
  ) async {
    final composer = ComposerController(_replyTarget);
    final shell = await _shell();
    addTearDown(composer.dispose);
    addTearDown(shell.dispose);
    await _pumpFloatingPanel(tester, shell, composer);

    final initial = tester.getRect(find.byType(ComposerPanel));
    expect(find.byIcon(Icons.open_in_full), findsNothing);

    await tester.drag(
      find.byKey(const ValueKey('composer-resize-left')),
      const Offset(40, 0),
    );
    await tester.pump();
    final fromLeft = tester.getRect(find.byType(ComposerPanel));
    expect(fromLeft.left, closeTo(initial.left + 40, 1));
    expect(fromLeft.right, closeTo(initial.right, 1));

    await tester.drag(
      find.byKey(const ValueKey('composer-resize-right')),
      const Offset(-40, 0),
    );
    await tester.pump();
    final fromRight = tester.getRect(find.byType(ComposerPanel));
    expect(fromRight.left, closeTo(fromLeft.left, 1));
    expect(fromRight.right, closeTo(fromLeft.right - 40, 1));

    await tester.drag(
      find.byKey(const ValueKey('composer-resize-top')),
      const Offset(0, -80),
    );
    await tester.pump();
    final fromTop = tester.getRect(find.byType(ComposerPanel));
    expect(fromTop.top, closeTo(initial.top - 80, 1));
    expect(fromTop.bottom, closeTo(initial.bottom, 1));

    await tester.drag(
      find.byKey(const ValueKey('composer-resize-bottom')),
      const Offset(0, -40),
    );
    await tester.pump();
    final fromBottom = tester.getRect(find.byType(ComposerPanel));
    expect(fromBottom.top, closeTo(fromTop.top, 1));
    expect(fromBottom.bottom, closeTo(fromTop.bottom - 40, 1));
  });

  testWidgets('shows bold and italic only beside selected text', (
    tester,
  ) async {
    final composer = ComposerController(_newTopicTarget);
    final shell = await _shell();
    addTearDown(composer.dispose);
    addTearDown(shell.dispose);
    await _pumpFloatingPanel(tester, shell, composer);

    expect(find.byTooltip('Bold'), findsNothing);
    expect(find.byTooltip('Italic'), findsNothing);

    composer.text.value = const TextEditingValue(
      text: 'format me',
      selection: TextSelection(baseOffset: 0, extentOffset: 6),
    );
    composer.focus.requestFocus();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('composer-selection-toolbar')),
      findsOneWidget,
    );
    expect(find.byTooltip('Bold'), findsOneWidget);
    expect(find.byTooltip('Italic'), findsOneWidget);

    final click = await tester.startGesture(
      tester.getCenter(find.byTooltip('Bold')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await click.up();
    await tester.pump();

    expect(composer.text.text, '**format** me');
    final create = tester.getCenter(
      find.widgetWithText(FilledButton, 'Create topic'),
    );
    final panel = tester.getRect(find.byType(ComposerPanel));

    expect(create.dy, greaterThan(panel.bottom - 52));
  });

  testWidgets('uses the available width in a narrow content pane', (
    tester,
  ) async {
    final composer = ComposerController(_replyTarget);
    final shell = await _shell();
    addTearDown(composer.dispose);
    addTearDown(shell.dispose);
    await _pumpFloatingPanel(
      tester,
      shell,
      composer,
      size: const Size(340, 600),
    );

    final panel = tester.getRect(find.byType(ComposerPanel));
    expect(panel.left, 16);
    expect(panel.right, 324);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a private-message composer addressed to the group', (
    tester,
  ) async {
    final composer = ComposerController(_privateMessageTarget);
    final shell = await _shell();
    addTearDown(composer.dispose);
    addTearDown(shell.dispose);
    await _pumpFloatingPanel(tester, shell, composer);

    expect(find.text('Message tech-leads'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('composer-private-message-recipients')),
      findsOneWidget,
    );
    expect(find.text('tech-leads'), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Send message'), findsOneWidget);
    expect(find.text('Category'), findsNothing);
    expect(find.text('Tags'), findsNothing);
    expect(find.text('Write your message…'), findsOneWidget);
  });

  testWidgets('restores the last completed move and resize', (tester) async {
    final firstComposer = ComposerController(_replyTarget);
    final shell = await _shell();
    addTearDown(firstComposer.dispose);
    addTearDown(shell.dispose);
    await _pumpFloatingPanel(tester, shell, firstComposer);

    await tester.drag(
      find.byKey(const ValueKey('composer-drag-handle')),
      const Offset(-48, -72),
    );
    await tester.pump();
    await tester.drag(
      find.byKey(const ValueKey('composer-resize-top')),
      const Offset(0, -80),
    );
    await tester.pump();
    final preferred = tester.getRect(find.byType(ComposerPanel));
    final stored = await const ComposerGeometryStore().read();
    expect(stored, isNotNull);
    expect(stored!.width, closeTo(preferred.width, 1));
    expect(stored.height, closeTo(preferred.height, 1));

    await tester.pumpWidget(const SizedBox.shrink());
    final reopenedComposer = ComposerController(_replyTarget);
    addTearDown(reopenedComposer.dispose);
    await _pumpFloatingPanel(tester, shell, reopenedComposer);
    await tester.pumpAndSettle();

    final restored = tester.getRect(find.byType(ComposerPanel));
    expect(restored, preferred);
  });

  testWidgets('waits for restored geometry before showing the panel', (
    tester,
  ) async {
    final persistence = _DelayedComposerGeometryPersistence();
    final composer = ComposerController(_newTopicTarget);
    final shell = await _shell();
    addTearDown(composer.dispose);
    addTearDown(shell.dispose);
    await _pumpFloatingPanel(
      tester,
      shell,
      composer,
      geometryStore: ComposerGeometryStore(persistence: persistence),
    );

    expect(find.byType(ComposerPanel), findsNothing);

    const preference = ComposerGeometryPreference(
      width: 640,
      height: 360,
      horizontalPosition: 0,
      verticalPosition: 0.5,
    );
    persistence.complete(preference);
    await tester.pumpAndSettle();

    final restored = tester.getRect(find.byType(ComposerPanel));
    expect(restored, const Rect.fromLTWH(16, 145, 640, 360));
  });

  testWidgets('shows the default panel when geometry storage never answers', (
    tester,
  ) async {
    final persistence = _DelayedComposerGeometryPersistence();
    final composer = ComposerController(_newTopicTarget);
    final shell = await _shell();
    addTearDown(composer.dispose);
    addTearDown(shell.dispose);
    await _pumpFloatingPanel(
      tester,
      shell,
      composer,
      geometryStore: ComposerGeometryStore(persistence: persistence),
    );

    expect(find.byType(ComposerPanel), findsNothing);

    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ComposerPanel), findsOneWidget);
  });
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

Future<void> _pumpFloatingPanel(
  WidgetTester tester,
  ShellController shell,
  ComposerController composer, {
  Size size = const Size(900, 650),
  ComposerGeometryStore geometryStore = const ComposerGeometryStore(),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: ShellScope(
        controller: shell,
        child: Scaffold(
          body: FloatingComposerPanel(
            composer: composer,
            geometryStore: geometryStore,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

final class _DelayedComposerGeometryPersistence
    implements ComposerGeometryPersistence {
  final Completer<String?> _read = Completer<String?>();

  @override
  Future<String?> readGeometry() => _read.future;

  @override
  Future<bool> writeGeometry(String encoded) async => true;

  void complete(ComposerGeometryPreference preference) {
    _read.complete(jsonEncode(preference.toJson()));
  }
}

const _replyTarget = ComposerTarget(
  siteUrl: 'https://meta.discourse.org',
  topicId: 7,
  slug: 'a-topic',
  topicTitle: 'A topic',
);

const _newTopicTarget = ComposerTarget(
  siteUrl: 'https://meta.discourse.org',
  topicId: 0,
  slug: '',
  topicTitle: '',
  mode: ComposerMode.newTopic,
);

const _privateMessageTarget = ComposerTarget(
  siteUrl: 'https://meta.discourse.org',
  topicId: 0,
  slug: '',
  topicTitle: 'New message',
  mode: ComposerMode.privateMessage,
  targetRecipients: 'tech-leads',
);
