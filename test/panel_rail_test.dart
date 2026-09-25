import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/panel_rail.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _rail = find.byType(PanelRail);
final _readOut = find.byKey(const ValueKey('panel-rail-read-out'));

void main() {
  testWidgets('pointing at the rail reads out every action with its name', (
    tester,
  ) async {
    final pressed = <String>[];
    await _pump(
      tester,
      onRestore: () => pressed.add('restore'),
      onSelect: (id) => pressed.add('select $id'),
      onNewTab: () => pressed.add('new tab'),
    );
    expect(tester.getSize(_rail).width, PanelRail.width);
    expect(_readOut, findsNothing);

    final mouse = await _mouse(tester, at: const Offset(600, 400));
    await mouse.moveTo(tester.getCenter(_rail));
    await tester.pumpAndSettle();

    expect(_readOut, findsOneWidget);
    for (final label in ['Restore panel', 'Baking', 'Plants', 'New tab']) {
      expect(
        find.descendant(of: _readOut, matching: find.text(label)),
        findsOneWidget,
        reason: label,
      );
    }
    await tester.tap(
      find.byKey(const ValueKey('panel-rail-read-out-tab-plants')),
    );
    await tester.tap(find.byKey(const ValueKey('panel-rail-read-out-restore')));
    await tester.tap(find.byKey(const ValueKey('panel-rail-read-out-new-tab')));
    expect(pressed, ['select plants', 'restore', 'new tab']);
  });

  for (final direction in TextDirection.values) {
    for (final towardStart in [false, true]) {
      testWidgets('the read-out grows from the rail '
          '${towardStart ? 'toward the start' : 'toward the end'} '
          'in $direction', (tester) async {
        await _pump(
          tester,
          direction: direction,
          opensTowardStart: towardStart,
          railAlignment: towardStart
              ? AlignmentDirectional.topEnd
              : AlignmentDirectional.topStart,
        );
        final rail = tester.getRect(_rail);
        final mouse = await _mouse(tester, at: const Offset(600, 400));
        await mouse.moveTo(rail.center);
        await tester.pump();
        final opening = tester.getRect(_readOut);
        await tester.pumpAndSettle();
        final open = tester.getRect(_readOut);

        // It starts as the rail and grows away from the edge it is docked on.
        expect(opening.width, closeTo(PanelRail.width, 1));
        expect(open.width, PanelRail.readOutWidth);
        expect(open.top, rail.top);
        expect(open.height, rail.height);
        final growsLeft = towardStart == (direction == TextDirection.ltr);
        if (growsLeft) {
          expect(open.right, rail.right);
        } else {
          expect(open.left, rail.left);
        }

        final railButton = find.byKey(const ValueKey('panel-rail-tab-baking'));
        final readOutButton = find.byKey(
          const ValueKey('panel-rail-read-out-tab-baking'),
        );
        final button = tester.widget<DButton>(readOutButton);
        expect(
          button.iconPosition,
          towardStart ? DButtonIconPosition.end : DButtonIconPosition.start,
        );
        final railIcon = find.descendant(
          of: railButton,
          matching: find.byType(DIcon),
        );
        final readOutIcon = find.descendant(
          of: readOutButton,
          matching: find.byType(DIcon),
        );
        expect(
          tester.getCenter(readOutIcon).dx,
          closeTo(tester.getCenter(railIcon).dx, 1),
          reason: 'the read-out icon stays over its rail icon',
        );
      });
    }
  }

  testWidgets('the read-out starts growing after the frame that builds it', (
    tester,
  ) async {
    await _pump(tester);
    final mouse = await _mouse(tester, at: const Offset(600, 400));
    await mouse.moveTo(tester.getCenter(_rail));
    await tester.pump();
    // Its first tick: still the rail's width, so none of the growth is lost
    // to the build.
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getSize(_readOut).width, PanelRail.width);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getSize(_readOut).width, greaterThan(PanelRail.width));
  });

  testWidgets(
    'moving from the rail onto the read-out keeps it open until it leaves',
    (tester) async {
      await _pump(tester);
      final mouse = await _mouse(tester, at: const Offset(600, 400));
      await mouse.moveTo(tester.getCenter(_rail));
      await tester.pumpAndSettle();
      expect(_readOut, findsOneWidget);

      // Past the rail's width, the pointer is only over the read-out.
      final open = tester.getRect(_readOut);
      await mouse.moveTo(Offset(open.right - 8, open.center.dy));
      await tester.pumpAndSettle();
      expect(_readOut, findsOneWidget);

      await mouse.moveTo(Offset(open.right + 40, open.center.dy));
      await tester.pumpAndSettle();
      expect(_readOut, findsNothing);
    },
  );

  testWidgets('a rail that appears under the pointer waits for it to leave', (
    tester,
  ) async {
    final mouse = await _mouse(tester, at: const Offset(19, 24));
    await _pump(tester);
    expect(tester.getRect(_rail).contains(const Offset(19, 24)), isTrue);

    await mouse.moveTo(const Offset(20, 30));
    await tester.pumpAndSettle();
    expect(_readOut, findsNothing);

    await mouse.moveTo(const Offset(300, 30));
    await tester.pump();
    await mouse.moveTo(const Offset(20, 30));
    await tester.pumpAndSettle();
    expect(_readOut, findsOneWidget);
  });

  testWidgets(
    'the rail announces each action once, whether or not it is read out',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester);

      expect(find.bySemanticsLabel('Secondary panel, minimized'), findsOne);
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('panel-rail-tab-baking')),
        ),
        matchesSemantics(
          label: 'Baking',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );

      final mouse = await _mouse(tester, at: const Offset(600, 400));
      await mouse.moveTo(tester.getCenter(_rail));
      await tester.pumpAndSettle();
      expect(_readOut, findsOneWidget);
      // Searched from the root, so a node dropped from the tree cannot match.
      expect(find.semantics.byLabel('Plants'), findsOne);
      expect(find.semantics.byLabel('Restore panel'), findsOne);
      semantics.dispose();
    },
  );

  testWidgets('a full workspace disables the new tab and says why', (
    tester,
  ) async {
    DButton button(String key) =>
        tester.widget<DButton>(find.byKey(ValueKey(key)));
    await _pump(tester, canCreateTab: false);
    expect(button('panel-rail-new-tab').onPressed, isNull);
    expect(find.byTooltip('Close a tab before opening another'), findsOne);

    final mouse = await _mouse(tester, at: const Offset(600, 400));
    await mouse.moveTo(tester.getCenter(_rail));
    await tester.pumpAndSettle();
    expect(button('panel-rail-read-out-new-tab').onPressed, isNull);
  });

  testWidgets('the read-out opens at once when motion is reduced', (
    tester,
  ) async {
    await _pump(tester, reduceMotion: true);
    final mouse = await _mouse(tester, at: const Offset(600, 400));
    await mouse.moveTo(tester.getCenter(_rail));
    await tester.pump();
    expect(tester.getSize(_readOut).width, PanelRail.readOutWidth);
  });
}

Future<TestGesture> _mouse(WidgetTester tester, {required Offset at}) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: at);
  addTearDown(mouse.removePointer);
  return mouse;
}

Future<void> _pump(
  WidgetTester tester, {
  TextDirection direction = TextDirection.ltr,
  bool opensTowardStart = false,
  AlignmentGeometry railAlignment = AlignmentDirectional.topStart,
  bool canCreateTab = true,
  bool reduceMotion = false,
  VoidCallback? onRestore,
  ValueChanged<String>? onSelect,
  VoidCallback? onNewTab,
}) async {
  tester.view.physicalSize = const Size(1000, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(1000, 700),
          disableAnimations: reduceMotion,
        ),
        child: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: Align(
              alignment: railAlignment,
              child: PanelRail(
                semanticLabel: 'Secondary panel, minimized',
                opensTowardStart: opensTowardStart,
                tabs: const [
                  PanelRailTab(
                    id: 'baking',
                    title: 'Baking',
                    icon: DIcon(DIcons.layerGroup),
                    selected: true,
                  ),
                  PanelRailTab(
                    id: 'plants',
                    title: 'Plants',
                    icon: DIcon(DIcons.layerGroup),
                  ),
                ],
                onRestore: onRestore ?? () {},
                onSelect: onSelect ?? (_) {},
                onNewTab: canCreateTab ? onNewTab ?? () {} : null,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
