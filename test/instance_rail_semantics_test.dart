import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/button_surface.dart';
import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _meta = 'https://meta.discourse.org';
const _team = 'https://team.discourse.org';

// macOS and Linux expose a node's label to the screen reader, never its
// tooltip, so a rail forum must be named by its label on both.
const _desktopBridges = TargetPlatformVariant({
  TargetPlatform.macOS,
  TargetPlatform.linux,
});

Future<FakeInstanceStore> _pumpRail(WidgetTester tester) async {
  const user = DiscourseUser(id: 7, username: 'reader');
  final store = FakeInstanceStore([
    const DiscourseInstance(
      url: _meta,
      title: 'Meta',
      iconUrl: '$_meta/logo.svg',
      user: user,
    ),
    const DiscourseInstance(
      url: _team,
      title: 'Team',
      iconUrl: '$_team/logo.svg',
    ),
  ]);
  await pumpShell(
    tester,
    desktop,
    store: store,
    authenticator: FakeAuthenticator()..keys[_meta] = 'meta-key',
    api: FakeDiscourseApi(
      user: user,
      totals: const NotificationTotals(unreadNotifications: 7),
    ),
    mediaClient: MockClient(
      (_) async => http.Response(
        '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">'
        '<path d="M0 0h24v24H0z"/></svg>',
        200,
        headers: {'content-type': 'image/svg+xml'},
      ),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

Finder _railItem(String url) =>
    find.byKey(ValueKey('instance-rail-tooltip-$url'));

List<String?> _customActions(SemanticsNode node) => [
  for (final id
      in node.getSemanticsData().customSemanticsActionIds ?? const <int>[])
    CustomSemanticsAction.getAction(id)?.label,
];

void main() {
  testWidgets(
    'forum target follows artwork and retains hover marker and drag cursor',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pumpRail(tester);
        final target = find.descendant(
          of: _railItem(_team),
          matching: find.byType(DItem),
        );
        expect(target, findsOneWidget);
        final bounds = tester.getRect(target);
        expect(bounds.size, const Size.square(32));
        expect(tester.getSemantics(_railItem(_team)).rect.size, bounds.size);
        final gapDrag = await tester.startGesture(
          Offset(bounds.left - 3, bounds.center.dy),
          kind: PointerDeviceKind.mouse,
        );
        await gapDrag.moveBy(const Offset(0, -20));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('instance-rail-drag-feedback-$_team')),
          findsNothing,
        );
        await gapDrag.up();
        await gapDrag.removePointer();
        await tester.pumpAndSettle();
        final detector = tester.widget<FocusableActionDetector>(
          find.descendant(
            of: target,
            matching: find.byType(FocusableActionDetector),
          ),
        );
        expect(detector.mouseCursor, SystemMouseCursors.grab);
        final marker = find.byKey(
          const ValueKey('instance-rail-marker-$_team'),
        );
        double markerHeight() =>
            tester.widget<AnimatedContainer>(marker).constraints!.maxHeight;
        expect(markerHeight(), 8);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: const Offset(800, 500));
        await mouse.moveTo(bounds.center);
        await tester.pumpAndSettle();
        expect(markerHeight(), 16);
        await mouse.moveTo(Offset(bounds.left - 3, bounds.center.dy));
        await tester.pumpAndSettle();
        expect(markerHeight(), 8);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
    variant: _desktopBridges,
  );

  testWidgets('rail actions keep cursor-only hover and keyboard focus', (
    tester,
  ) async {
    await _pumpRail(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    for (final key in [
      'add-instance-rail-button',
      'styleguide-rail-button',
      'settings-rail-button',
    ]) {
      final button = find.byKey(ValueKey(key));
      final before = buttonSurface(tester, of: button);
      final bounds = tester.getRect(button);
      final control = find.descendant(
        of: button,
        matching: find.byType(FilledButton),
      );
      final native = tester.widget<FilledButton>(control);
      expect(before.color, Colors.transparent);
      expect(before.borderColor, Colors.transparent);
      expect(before.dashed, isFalse);
      expect(
        native.style!.mouseCursor!.resolve({WidgetState.hovered}),
        SystemMouseCursors.click,
      );
      await mouse.moveTo(bounds.center);
      await tester.pump(const Duration(milliseconds: 200));
      expect(buttonSurface(tester, of: button), before);
      expect(tester.getRect(control), bounds);
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      final focus = Focus.of(
        tester.element(
          find
              .descendant(
                of: control,
                matching: find.byWidgetPredicate(
                  (widget) => widget is DIcon || widget is Icon,
                ),
              )
              .first,
        ),
      );
      focus.requestFocus();
      await tester.pumpAndSettle();
      expect(buttonSurface(tester, of: button).ringWidth, greaterThan(0));
      focus.unfocus();
      await tester.pumpAndSettle();
    }
  }, variant: _desktopBridges);

  testWidgets('rail fallback keeps an emoji monogram intact', (tester) async {
    const title = '🧵 Discourse';
    await pumpShell(
      tester,
      desktop,
      instances: const [DiscourseInstance(url: _meta, title: title)],
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: _railItem(_meta), matching: find.text('🧵D')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  }, variant: _desktopBridges);

  testWidgets('a rail forum is a named button that says which is current', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpRail(tester);

      // Both forums draw their site icon, not the monogram fallback.
      for (final url in [_meta, _team]) {
        expect(
          find.descendant(
            of: _railItem(url),
            matching: find.byType(SvgPicture),
          ),
          findsOneWidget,
        );
      }

      final meta = tester.getSemantics(_railItem(_meta));
      expect(
        meta,
        isSemantics(isButton: true, isSelected: true, isImage: false),
      );
      final label = meta.getSemanticsData().label;
      expect(label, startsWith('Meta'));
      expect(label, contains('7 unread notifications'));
      expect(
        _customActions(meta),
        unorderedEquals(['Show forum actions', 'Move down']),
      );

      final team = tester.getSemantics(_railItem(_team));
      expect(
        team,
        isSemantics(
          label: 'Team',
          isButton: true,
          isSelected: false,
          isImage: false,
        ),
      );
      expect(
        _customActions(team),
        unorderedEquals(['Show forum actions', 'Move up']),
      );
    } finally {
      semantics.dispose();
    }
  }, variant: _desktopBridges);

  testWidgets('a rail forum moves through its semantics action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final store = await _pumpRail(tester);

      final meta = tester.getSemantics(_railItem(_meta));
      tester.binding.performSemanticsAction(
        SemanticsActionEvent(
          type: SemanticsAction.customAction,
          nodeId: meta.id,
          viewId: tester.view.viewId,
          arguments: CustomSemanticsAction.getIdentifier(
            const CustomSemanticsAction(label: 'Move down'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect((await store.load()).map((site) => site.url), [_team, _meta]);
      expect(
        _customActions(tester.getSemantics(_railItem(_meta))),
        unorderedEquals(['Show forum actions', 'Move up']),
      );
    } finally {
      semantics.dispose();
    }
  }, variant: _desktopBridges);
}
