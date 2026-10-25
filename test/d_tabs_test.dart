import 'dart:ui' show SemanticsAction, Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    TargetPlatform platform = TargetPlatform.macOS,
    double width = 420,
    double scale = 1,
    bool rtl = false,
    bool reducedMotion = false,
    ThemeData? theme,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: (theme ?? AppTheme.light).copyWith(platform: platform),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          textScaler: TextScaler.linear(scale),
          disableAnimations: reducedMotion,
        ),
        child: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(width: width, child: child),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('navigation bar preserves targets in narrow RTL and large text', (
    tester,
  ) async {
    await mount(
      tester,
      const DTabs<String>(
        children: [
          DTabList<String>(
            variant: DTabListVariant.plain,
            children: [
              DTabTrigger(
                value: 'home',
                semanticLabel: 'Home',
                child: Icon(Icons.home),
              ),
              DTabTrigger(
                value: 'chat',
                semanticLabel: 'Chat',
                child: Icon(Icons.chat),
              ),
              DTabTrigger(
                value: 'voice',
                semanticLabel: 'Voice',
                child: Icon(Icons.mic),
              ),
              DTabTrigger(
                value: 'settings',
                semanticLabel: 'Settings',
                child: Icon(Icons.settings),
              ),
            ],
          ),
        ],
      ),
      platform: TargetPlatform.android,
      width: 160,
      rtl: true,
      scale: 2,
    );
    await tester.pumpAndSettle();
    for (final element in find.byType(DTabTrigger<String>).evaluate()) {
      final trigger = find.byWidget(element.widget);
      final artwork = find.descendant(
        of: trigger,
        matching: find.byType(AnimatedContainer),
      );
      expect(tester.getRect(trigger), tester.getRect(artwork));
      expect(tester.getSize(trigger).width, 38);
    }
    expect(tester.takeException(), isNull);
  });

  Widget tabs({
    bool selectFirst = true,
    bool activateOnFocus = false,
    Axis orientation = Axis.horizontal,
    ValueChanged<String?>? onChanged,
  }) => DTabs<String>(
    selectFirstOnMount: selectFirst,
    orientation: orientation,
    onChanged: onChanged,

    children: [
      DTabList<String>(
        activateOnFocus: activateOnFocus,

        children: const [
          DTabTrigger(value: 'one', child: Text('One')),
          DTabTrigger(value: 'two', child: Text('Two')),
          DTabTrigger(value: 'three', child: Text('Three')),
        ],
      ),
      const DTabPanel(value: 'one', child: Text('Panel one')),
      const DTabPanel(value: 'two', child: Text('Panel two')),
      const DTabPanel(value: 'three', child: Text('Panel three')),
    ],
  );

  for (final theme in [AppTheme.light, AppTheme.dark]) {
    testWidgets('${theme.brightness.name} pill selection moves immediately', (
      tester,
    ) async {
      await mount(
        tester,
        const DTabs<String>(
          children: [
            DTabList<String>(
              variant: DTabListVariant.pill,
              children: [
                DTabTrigger(value: 'latest', child: Text('Latest')),
                DTabTrigger(value: 'new', child: Text('New 3')),
              ],
            ),
          ],
        ),
        theme: theme,
      );
      await tester.pumpAndSettle();
      final latest = find.byType(DTabTrigger<String>).first;
      final newTopics = find.byType(DTabTrigger<String>).last;
      final tokens = DTokens.of(tester.element(latest));
      BoxDecoration decoration(Finder trigger) =>
          tester
                  .widget<DecoratedBox>(
                    find.descendant(
                      of: trigger,
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      void expectSelected(Finder trigger) {
        final painted = decoration(trigger);
        expect(painted.color, tokens.foreground.withValues(alpha: .08));
        expect(painted.borderRadius, BorderRadius.circular(DRadius.panel));
        expect(painted.border!.top.color, Colors.transparent);
        expect(painted.boxShadow, isEmpty);
      }

      expectSelected(latest);
      expect(decoration(newTopics).color, Colors.transparent);
      expect(
        decoration(newTopics).borderRadius,
        BorderRadius.circular(DRadius.pill),
      );
      expect(tester.getSize(latest).height, DControlStyle.regularHeight);
      expect(tester.getRect(newTopics).left - tester.getRect(latest).right, 4);
      expect(
        DefaultTextStyle.of(tester.element(find.text('New 3'))).style.color,
        tokens.mutedForeground,
      );

      await tester.tap(newTopics);
      await tester.pump();
      expectSelected(newTopics);
      expect(decoration(latest).color, Colors.transparent);
      await tester.pump(const Duration(milliseconds: 75));
      expectSelected(newTopics);
      expect(decoration(latest).color, Colors.transparent);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('touch backgrounds retain their inset with enlarged text', (
    tester,
  ) async {
    for (final size in DControlSize.values) {
      for (final scale in [1.0, 2.0]) {
        await mount(
          tester,
          DTabs<String>(
            children: [
              DTabList<String>(
                size: size,
                children: const [DTabTrigger(value: 'all', child: Text('All'))],
              ),
            ],
          ),
          platform: TargetPlatform.iOS,
          scale: scale,
        );
        await tester.pumpAndSettle();
        final background = find.descendant(
          of: find.byType(DTabList<String>),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container && widget.decoration is BoxDecoration,
          ),
        );
        final artwork = find.descendant(
          of: find.byType(DTabTrigger<String>),
          matching: find.byType(AnimatedContainer),
        );
        final outer = tester.getRect(background.first);
        final inner = tester.getRect(artwork);
        expect(inner.top - outer.top, greaterThanOrEqualTo(3));
        expect(outer.bottom - inner.bottom, greaterThanOrEqualTo(3));
        expect(
          tester.getSize(find.byType(DTabTrigger<String>)).height,
          tester.getSize(artwork).height,
        );
      }
    }
  });

  testWidgets('mixed labels stay centered inside inset selected artwork', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      for (final size in DControlSize.values) {
        await mount(
          tester,
          DTabs<String>(
            key: ValueKey((brightness, size)),

            children: [
              DTabList<String>(
                size: size,
                children: const [
                  DTabTrigger(value: 'all', child: Text('All')),
                  DTabTrigger(
                    value: 'topics',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Topics'),
                        SizedBox(width: 6),
                        DBadge(
                          variant: DBadgeVariant.secondary,
                          child: Text('82'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          theme: ThemeData(brightness: brightness),
        );
        await tester.pumpAndSettle();
        final list = tester.getRect(find.byType(DTabList<String>));
        final trigger = tester.getRect(find.byType(DTabTrigger<String>).first);
        expect(trigger.top - list.top, greaterThanOrEqualTo(3));
        expect(list.bottom - trigger.bottom, greaterThanOrEqualTo(3));
        expect(
          tester.getCenter(find.text('All')).dy,
          closeTo(list.center.dy, .01),
        );
        expect(
          tester.getCenter(find.text('Topics')).dy,
          closeTo(list.center.dy, .01),
        );
        final surface = tester.widget<AnimatedContainer>(
          find
              .descendant(
                of: find.byType(DTabTrigger<String>).first,
                matching: find.byType(AnimatedContainer),
              )
              .first,
        );
        expect((surface.decoration! as BoxDecoration).boxShadow, isEmpty);
        await tester.tap(find.text('Topics'));
        await tester.pumpAndSettle();
        expect(
          tester.getCenter(find.text('All')).dy,
          closeTo(tester.getCenter(find.text('Topics')).dy, .01),
        );
      }
    }
  });

  testWidgets(
    'matches compact default and line geometry on pointer platforms',
    (tester) async {
      await mount(tester, tabs());
      await tester.pumpAndSettle();
      // The regular 30px preset holds an inset trigger whose label and
      // ordinary padding determine its visible and interactive bounds.
      expect(
        tester.getSize(find.byType(DTabList<String>)).height,
        DControlStyle.regularHeight,
      );
      expect(tester.getSize(find.byType(DTabTrigger<String>).first).height, 24);

      await mount(
        tester,
        const DTabs<String>(
          children: [
            DTabList<String>(
              variant: DTabListVariant.line,
              children: [
                DTabTrigger(value: 'one', child: Text('One')),
                DTabTrigger(value: 'two', child: Text('Two')),
              ],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final first = tester.getRect(find.byType(DTabTrigger<String>).first);
      final second = tester.getRect(find.byType(DTabTrigger<String>).last);
      expect(second.left - first.right, 20);
      expect(first.height, 41);
      expect(first.left, tester.getRect(find.byType(DTabList<String>)).left);
      expect(first.width, tester.getSize(find.text('One')).width);
      expect(
        DefaultTextStyle.of(tester.element(find.text('One'))).style.fontWeight,
        FontWeight.w600,
      );
      expect(
        DefaultTextStyle.of(tester.element(find.text('Two'))).style.fontWeight,
        FontWeight.w400,
      );
      await tester.tap(find.text('Two'));
      await tester.pump();
      expect(
        DefaultTextStyle.of(tester.element(find.text('Two'))).style.fontWeight,
        FontWeight.w600,
      );
    },
  );

  testWidgets('uncontrolled pointer and semantics activation switch panels', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final values = <String?>[];
    await mount(tester, tabs(onChanged: values.add));
    await tester.pumpAndSettle();
    expect(find.text('Panel one'), findsOneWidget);
    expect(find.text('Panel two'), findsNothing);
    expect(values, ['one']);

    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(values, ['one', 'two']);
    expect(find.text('Panel one'), findsNothing);
    expect(find.text('Panel two'), findsOneWidget);
    final data = tester
        .getSemantics(find.byType(DTabTrigger<String>).at(1))
        .getSemanticsData();
    expect(data.flagsCollection.isSelected, Tristate.isTrue);
    final third = tester.getSemantics(find.byType(DTabTrigger<String>).at(2));
    third.owner!.performAction(third.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(values, ['one', 'two', 'three']);
    expect(find.text('Panel two'), findsNothing);
    expect(find.text('Panel three'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('controlled selection waits for its parent', (tester) async {
    var value = 'one';
    var calls = 0;
    late StateSetter update;
    await mount(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return DTabs<String>.controlled(
            value: value,
            onChanged: (_) => calls++,
            children: const [
              DTabList<String>(
                children: [
                  DTabTrigger(value: 'one', child: Text('One')),
                  DTabTrigger(value: 'two', child: Text('Two')),
                ],
              ),
              DTabPanel(value: 'one', child: Text('Panel one')),
              DTabPanel(value: 'two', child: Text('Panel two')),
            ],
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Two'));
    await tester.pump();
    expect(calls, 1);
    expect(find.text('Panel one'), findsOneWidget);
    update(() => value = 'two');
    await tester.pump();
    expect(find.text('Panel two'), findsOneWidget);
  });

  testWidgets('vertical tabs use up and down but ignore horizontal arrows', (
    tester,
  ) async {
    await mount(
      tester,
      tabs(orientation: Axis.vertical, activateOnFocus: true),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('One'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('Panel one'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.text('Panel two'), findsOneWidget);
  });

  testWidgets('controlled selection stays empty until user selection', (
    tester,
  ) async {
    final controller = ValueNotifier<String?>('one');
    addTearDown(controller.dispose);
    await mount(
      tester,
      ValueListenableBuilder<String?>(
        valueListenable: controller,
        builder: (context, value, _) => DTabs<String>.controlled(
          value: value,
          onChanged: (next) => controller.value = next,

          children: const [
            DTabList<String>(
              children: [
                DTabTrigger(value: 'one', child: Text('One')),
                DTabTrigger(value: 'two', child: Text('Two')),
              ],
            ),
            DTabPanel(value: 'one', child: Text('Panel one')),
            DTabPanel(value: 'two', child: Text('Panel two')),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Panel one'), findsOneWidget);

    controller.value = null;
    await tester.pumpAndSettle();
    expect(controller.value, isNull);
    expect(find.text('Panel one'), findsNothing);
    expect(find.text('Panel two'), findsNothing);

    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(controller.value, 'two');
    expect(find.text('Panel two'), findsOneWidget);
  });

  testWidgets('narrow large-text lists scroll with natural targets', (
    tester,
  ) async {
    await mount(
      tester,
      tabs(),
      width: 120,
      scale: 2,
      reducedMotion: true,
      platform: TargetPlatform.iOS,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(DTabList<String>)).height,
      greaterThanOrEqualTo(48),
    );
    final triggerSize = tester.getSize(find.byType(DTabTrigger<String>).first);
    expect(triggerSize.width, greaterThanOrEqualTo(44));
    final artwork = find.descendant(
      of: find.byType(DTabTrigger<String>).first,
      matching: find.byType(AnimatedContainer),
    );
    expect(triggerSize, tester.getSize(artwork));
    await tester.scrollUntilVisible(
      find.text('Three'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Three'));
    await tester.pumpAndSettle();
    expect(find.text('Panel three'), findsOneWidget);

    await mount(
      tester,
      tabs(orientation: Axis.vertical),
      width: 260,
      platform: TargetPlatform.iOS,
    );
    await tester.pumpAndSettle();
    for (final trigger in find.byType(DTabTrigger<String>).evaluate()) {
      final size = tester.getSize(find.byElementPredicate((e) => e == trigger));
      expect(size.width, greaterThanOrEqualTo(48));
      final artwork = find.descendant(
        of: find.byWidget(trigger.widget),
        matching: find.byType(AnimatedContainer),
      );
      expect(size.height, tester.getSize(artwork).height);
    }
  });

  testWidgets('live tokens update active surface and radius', (tester) async {
    ThemeData theme = AppTheme.light;
    late StateSetter update;
    await mount(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return Theme(data: theme, child: tabs());
        },
      ),
    );
    await tester.pumpAndSettle();
    BoxDecoration decoration() =>
        (tester
                .widget<AnimatedContainer>(find.byType(AnimatedContainer).first)
                .decoration
            as BoxDecoration);
    final light = decoration();
    update(() => theme = AppTheme.dark);
    await tester.pumpAndSettle();
    final dark = decoration();
    expect(dark.color, isNot(light.color));
    expect(dark.borderRadius, light.borderRadius);
  });
}
