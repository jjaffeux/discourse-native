import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget fixture({
  double width = 390,
  bool collapsed = false,
  bool withAction = true,
  TextDirection direction = TextDirection.ltr,
  double scale = 1,
  VoidCallback? onReveal,
  VoidCallback? onAction,
  ValueChanged<String>? onPlace,
  void Function(int from, int to)? onMoved,
  List<String> labels = const [
    'Start',
    'Topics',
    'Chat',
    'Inbox',
    'Users',
    'A very long destination',
  ],
  String? selected = 'Topics',
  DMobileDockPlace? you,
  ValueChanged<bool>? onPanelChanged,
  bool covered = false,
  bool hidden = false,
  ThemeData? theme,
  Color backdrop = Colors.white,
  bool highContrast = false,
  bool reducedMotion = false,
  double foot = 0,
  Widget? page,
}) => MaterialApp(
  theme: theme,
  home: MediaQuery(
    data: MediaQueryData(
      textScaler: TextScaler.linear(scale),
      highContrast: highContrast,
      disableAnimations: reducedMotion,
      padding: EdgeInsets.only(bottom: foot),
    ),
    child: Directionality(
      textDirection: direction,
      child: RepaintBoundary(
        key: const ValueKey('dock-capture'),
        child: Scaffold(
          backgroundColor: backdrop,
          body: Stack(
            children: [
              // The page the bar stands over, where a person may be typing.
              ?page,
              Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  key: const ValueKey('dock-frame'),
                  width: width,
                  child: Builder(
                    builder: (context) {
                      final geometry = DMobileDockGeometry.of(context);
                      return Padding(
                        padding: geometry.margin,
                        child: DMobileDock(
                          geometry: geometry,
                          collapsed: collapsed,
                          destinationsHidden: hidden,
                          covered: covered,
                          places: [
                            for (final name in labels)
                              DMobileDockPlace(
                                key: ValueKey(name),
                                icon: const Icon(Icons.forum),
                                label: name,
                                badge: name == 'Chat'
                                    ? const DBadge.overlay(child: Text('99+'))
                                    : null,
                                selected: name == selected,
                                onPressed: () => onPlace?.call(name),
                              ),
                            ?you,
                          ],
                          more: (
                            icon: const Icon(Icons.more_vert),
                            label: 'More',
                          ),
                          onPanelChanged: onPanelChanged,
                          onMoved: onMoved,
                          collapsedDestination: DMobileDockItem(
                            key: const ValueKey('reveal'),
                            collapsed: true,
                            icon: const Icon(Icons.forum),
                            label: 'Reveal navigation',
                            onPressed: onReveal ?? () {},
                          ),
                          action: withAction
                              ? DMobileDockAction(
                                  key: const ValueKey('action'),
                                  icon: const Icon(Icons.add),
                                  label: 'New topic',
                                  onPressed: onAction ?? () {},
                                )
                              : null,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);

/// You, as the shell would hand the dock: a face, a name and a presence.
DMobileDockPlace you({Color? ring, VoidCallback? onPressed}) =>
    DMobileDockPlace.avatar(
      key: const ValueKey('profile'),
      face: const ColoredBox(
        key: ValueKey('face'),
        color: Colors.orange,
        child: SizedBox.expand(),
      ),
      label: 'Jo',
      ring: ring,
      semanticLabel: 'Your account, online',
      onPressed: onPressed ?? () {},
    );

final _panel = find.byKey(DMobileDock.panelKey);
final _dim = find.byKey(DMobileDock.dimKey);
final _more = find.byKey(DMobileDock.moreKey);

/// The names on the panel's tiles, in the order a person reads them.
List<String> _tileLabels(WidgetTester tester) => [
  for (final item in tester.widgetList<DMobileDockItem>(
    find.descendant(of: _panel, matching: find.byType(DMobileDockItem)),
  ))
    item.label,
];

/// The names on the bar's places, in the order a person reads them.
List<String> _barLabels(WidgetTester tester) => [
  for (final item in tester.widgetList<DMobileDockItem>(
    find.descendant(of: _surface, matching: find.byType(DMobileDockItem)),
  ))
    if (item.key != DMobileDock.moreKey) item.label,
];

/// The place called [name] as it is drawn while a place is being moved.
Finder _moving(String name) => find.descendant(
  of: find.byKey(DMobileDock.movingKey(ValueKey(name))),
  matching: find.byType(DMobileDockItem),
);

/// The key of the place, the tile or the action holding the focus.
Key? _focusedKey() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  Key? key;
  context.visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is DMobileDockItem || widget is DMobileDockAction) {
      key = widget.key;
      return false;
    }
    return true;
  });
  return key;
}

Future<void> _tab(WidgetTester tester, {bool back = false}) async {
  if (back) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  if (back) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
}

final _frame = find.byKey(const ValueKey('dock-frame'));
final _surface = find.byKey(const ValueKey('mobile-dock-surface'));

/// A primary-filled control built as the chat composer's send button is.
Widget sendButtonFixture(ThemeData theme) => MaterialApp(
  theme: theme,
  home: Scaffold(
    body: Center(
      child: Builder(
        builder: (context) {
          final colors = DTokens.of(context).buttonTheme.primary;
          return DButton.iconOnly(
            size: DButtonSize.toolbar,
            foregroundColor: colors.foreground,
            backgroundColor: colors.background,
            interactiveBackgroundColor: colors.hover,
            icon: const Icon(Icons.send),
            tooltip: 'Send',
            onPressed: () {},
          );
        },
      ),
    ),
  ),
);

void main() {
  for (final direction in TextDirection.values) {
    testWidgets(
      'an actionless dock keeps the ⋮ at the fourth column\'s start ($direction)',
      (tester) async {
        for (final scale in [1.0, 2.0]) {
          await tester.pumpWidget(
            fixture(withAction: false, direction: direction, scale: scale),
          );
          await tester.pumpAndSettle();
          expect(find.byType(DMobileDockAction), findsNothing);
          final surface = tester.getRect(_surface);
          final more = tester.getRect(_more);
          // The capsule is 378 wide: 366 inside, columns of 88.5 and 4 gaps.
          expect(more.width, 40);
          if (direction == TextDirection.ltr) {
            expect(more.left, closeTo(surface.left + 6 + 277.5, .01));
          } else {
            expect(more.right, closeTo(surface.right - 6 - 277.5, .01));
          }
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'capsule surrounds controls with its stock material ($brightness, flat)',
      (tester) async {
        final theme = brightness == Brightness.dark
            ? AppTheme.dark
            : AppTheme.light;
        await tester.pumpWidget(fixture(theme: theme));
        await tester.pumpAndSettle();
        final capsule = find.byKey(const ValueKey('mobile-dock-surface'));
        final surface = tester.getRect(capsule);
        final frame = tester.getRect(_frame);
        final destination = tester.getRect(
          find.byKey(const ValueKey('Topics')),
        );
        final action = tester.getRect(find.byType(DMobileDockAction));
        expect(surface.height, 62);
        expect(surface.left, frame.left + 6);
        expect(surface.right, frame.right - 6);
        expect(surface.bottom, frame.bottom - 6);
        expect(destination.height, 50);
        expect(destination.top - surface.top, 6);
        expect(surface.bottom - destination.bottom, 6);
        expect(surface.right - action.right, 6);
        final decoration =
            tester.widget<AnimatedContainer>(capsule).decoration
                as BoxDecoration;
        expect(decoration.borderRadius, BorderRadius.circular(31));
        final fill = decoration.color!;
        expect(fill, DTokens.of(tester.element(capsule)).wellFill);
        expect(fill.a, 1);

        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final direction in TextDirection.values) {
    testWidgets(
      'a round screen\'s bar runs the full width down to the foot ($direction)',
      (tester) async {
        await tester.pumpWidget(fixture(foot: 34, direction: direction));
        await tester.pumpAndSettle();
        final surface = tester.getRect(_surface);
        final frame = tester.getRect(_frame);
        final destination = tester.getRect(
          find.byKey(const ValueKey('Topics')),
        );
        final action = tester.getRect(find.byType(DMobileDockAction));
        expect(surface.left, frame.left);
        expect(surface.right, frame.right);
        expect(surface.bottom, frame.bottom);
        expect(surface.height, 86);
        expect(destination.height, 50);
        expect(destination.top - surface.top, 6);
        expect(surface.bottom - destination.bottom, 30);
        if (direction == TextDirection.ltr) {
          expect(surface.right - action.right, 6);
        } else {
          expect(action.left - surface.left, 6);
        }
        final decoration =
            tester.widget<AnimatedContainer>(_surface).decoration
                as BoxDecoration;
        expect(
          decoration.borderRadius,
          const BorderRadius.vertical(top: Radius.circular(31)),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('dock content follows the theme foreground colors', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        fixture(
          theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
        ),
      );
      await tester.pumpAndSettle();
      for (final name in ['Start', 'Topics']) {
        final glyph = find.descendant(
          of: find.byKey(ValueKey(name)),
          matching: find.byIcon(Icons.forum),
        );
        expect(
          IconTheme.of(tester.element(glyph)).color,
          name == 'Topics'
              ? DTokens.of(tester.element(glyph)).foreground
              : DTokens.of(tester.element(glyph)).mutedForeground,
        );
      }
      expect(tester.takeException(), isNull);
    }
  });

  for (final direction in TextDirection.values) {
    testWidgets(
      'three places take one column each, the ⋮ and action the fourth ($direction)',
      (tester) async {
        await tester.pumpWidget(fixture(foot: 34, direction: direction));
        await tester.pumpAndSettle();
        final surface = tester.getRect(_surface);
        // 390 wide at the foot: 378 inside, columns of 91.5 and 4 gaps.
        double fromStart(Rect rect) => direction == TextDirection.ltr
            ? rect.left - surface.left - 6
            : surface.right - 6 - rect.right;
        for (final (index, key) in ['Start', 'Topics', 'Chat'].indexed) {
          final item = find.byKey(ValueKey(key));
          expect(item.hitTestable(), findsOneWidget);
          final rect = tester.getRect(item);
          expect(fromStart(rect), closeTo(index * 95.5, .01), reason: key);
          expect(rect.width, closeTo(91.5, .01), reason: key);
          expect(rect.height, 50);
        }
        final more = tester.getRect(_more);
        expect(fromStart(more), closeTo(286.5, .01));
        expect(more.width, 40);
        final action = tester.getRect(find.byType(DMobileDockAction));
        expect(fromStart(action), closeTo(328, .01));
        expect(action.size, const Size(50, 50));
        expect(find.byKey(const ValueKey('Inbox')).hitTestable(), findsNothing);
        expect(find.byKey(const ValueKey('Inbox')), findsNothing);
        expect(find.text('More'), findsNothing);
        expect(find.text('New topic'), findsNothing);
        expect(
          tester.widget<DButton>(find.byType(DButton).last).tooltip,
          'New topic',
        );
        final semantics = tester.ensureSemantics();
        expect(tester.getSemantics(_more).getSemanticsData().label, 'More');
        semantics.dispose();
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('folded dock retains only a bounded reveal target', (
    tester,
  ) async {
    var revealed = 0;
    await tester.pumpWidget(fixture());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      fixture(collapsed: true, onReveal: () => revealed++),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile-dock-surface'))),
      const Size(48, 48),
    );
    expect(find.byKey(const ValueKey('Start')).hitTestable(), findsNothing);
    expect(find.byKey(const ValueKey('reveal')).hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reveal')));
    expect(revealed, 1);
    expect(tester.takeException(), isNull);
  });
  for (final direction in TextDirection.values) {
    for (final (foot, scale, corner) in [
      (34.0, 1.0, 13.3225),
      (34.0, 2.0, 11.7116),
      (0.0, 1.0, 6.0),
    ]) {
      testWidgets('the folded circle settles into the bottom-start corner '
          '($direction, foot $foot, scale $scale)', (tester) async {
        await tester.pumpWidget(
          fixture(foot: foot, scale: scale, direction: direction),
        );
        await tester.pumpAndSettle();
        final frame = tester.getRect(_frame);
        final open = tester.getRect(_surface);
        await tester.pumpWidget(
          fixture(
            foot: foot,
            scale: scale,
            direction: direction,
            collapsed: true,
          ),
        );
        expect(tester.getRect(_surface), open);
        final widths = <double>[];
        for (var step = 0; step < 15; step++) {
          await tester.pump(const Duration(milliseconds: 30));
          widths.add(tester.getRect(_surface).width);
        }
        await tester.pumpAndSettle();
        final circle = tester.getRect(_surface);
        final diameter = 48 + (scale - 1) * 11;
        expect(circle.size, Size(diameter, diameter));
        expect(circle.bottom, closeTo(frame.bottom - corner, .001));
        if (direction == TextDirection.ltr) {
          expect(circle.left, closeTo(frame.left + corner, .001));
        } else {
          expect(circle.right, closeTo(frame.right - corner, .001));
        }
        for (var i = 1; i < widths.length; i++) {
          expect(widths[i], lessThanOrEqualTo(widths[i - 1] + .01));
        }
        expect(widths.toSet().length, greaterThan(3));
        await tester.pumpWidget(
          fixture(foot: foot, scale: scale, direction: direction),
        );
        await tester.pumpAndSettle();
        expect(tester.getRect(_surface), open);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final direction in TextDirection.values) {
    testWidgets(
      'the current page past the bar\'s columns stands where the ⋮ was ($direction)',
      (tester) async {
        await tester.pumpWidget(
          fixture(
            foot: 34,
            direction: direction,
            selected: 'A very long destination',
          ),
        );
        await tester.pumpAndSettle();
        final surface = tester.getRect(_surface);
        double fromStart(Rect rect) => direction == TextDirection.ltr
            ? rect.left - surface.left - 6
            : surface.right - 6 - rect.right;
        expect(_more, findsNothing);
        final here = find.byKey(const ValueKey('A very long destination'));
        expect(here.hitTestable(), findsOneWidget);
        expect(tester.widget<DMobileDockItem>(here).hasPopup, isTrue);
        expect(tester.widget<DMobileDockItem>(here).selected, isTrue);
        // The four share (3 * 91.5 + 40) with the three gaps kept.
        for (final (index, key) in [
          'Start',
          'Topics',
          'Chat',
          'A very long destination',
        ].indexed) {
          final rect = tester.getRect(find.byKey(ValueKey(key)));
          expect(fromStart(rect), closeTo(index * 82.625, .01), reason: key);
          expect(rect.width, closeTo(78.625, .01), reason: key);
        }
        final label = find.text('A very long destination');
        expect(label, findsOneWidget);
        final column = tester.getRect(here);
        expect(tester.getRect(label).left, greaterThanOrEqualTo(column.left));
        expect(tester.getRect(label).right, lessThanOrEqualTo(column.right));
        final action = tester.getRect(find.byType(DMobileDockAction));
        expect(fromStart(action), closeTo(328, .01));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final reduced in [false, true]) {
    testWidgets(
      'the current place is marked on the bar\'s top edge (reduced motion: $reduced)',
      (tester) async {
        Rect mark(int index) =>
            tester.getRect(find.byKey(ValueKey('mobile-dock-mark-$index')));
        double over(String key) =>
            tester.getCenter(find.byKey(ValueKey(key))).dx;
        await tester.pumpWidget(fixture(foot: 34, reducedMotion: reduced));
        await tester.pumpAndSettle();
        final surface = tester.getRect(_surface);
        expect(mark(1).size, const Size(28, 4));
        expect(mark(1).top, surface.top);
        expect(mark(1).center.dx, closeTo(over('Topics'), .01));
        expect(mark(0).width, 0);
        expect(mark(2).width, 0);
        final decoration =
            tester
                    .widget<AnimatedContainer>(
                      find.byKey(const ValueKey('mobile-dock-mark-1')),
                    )
                    .decoration
                as BoxDecoration;
        expect(
          decoration.color,
          DTokens.of(tester.element(_surface)).foreground,
        );
        expect(
          decoration.borderRadius,
          const BorderRadius.vertical(bottom: Radius.circular(3)),
        );
        // Moving to Chat: its mark grows in over 200 ms as Topics' goes, or
        // at once under reduced motion.
        await tester.pumpWidget(
          fixture(foot: 34, reducedMotion: reduced, selected: 'Chat'),
        );
        await tester.pump(const Duration(milliseconds: 100));
        if (reduced) {
          expect(mark(2).width, 28);
          expect(mark(1).width, 0);
        } else {
          expect(mark(2).width, inExclusiveRange(0, 28));
          expect(mark(1).width, inExclusiveRange(0, 28));
        }
        await tester.pumpAndSettle();
        expect(mark(2).size, const Size(28, 4));
        expect(mark(2).center.dx, closeTo(over('Chat'), .01));
        expect(mark(1).width, 0);
        // Nothing current, nothing marked.
        await tester.pumpWidget(
          fixture(foot: 34, reducedMotion: reduced, selected: null),
        );
        await tester.pumpAndSettle();
        for (final index in [0, 1, 2]) {
          expect(mark(index).width, 0, reason: '$index');
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('the page standing where the ⋮ was carries the mark', (
    tester,
  ) async {
    await tester.pumpWidget(fixture(foot: 34, selected: 'Users'));
    await tester.pumpAndSettle();
    final mark = tester.getRect(
      find.byKey(const ValueKey('mobile-dock-mark-3')),
    );
    expect(mark.size, const Size(28, 4));
    expect(mark.top, tester.getRect(_surface).top);
    expect(
      mark.center.dx,
      closeTo(tester.getCenter(find.byKey(const ValueKey('Users'))).dx, .01),
    );
    for (final index in [0, 1, 2]) {
      expect(
        tester.getRect(find.byKey(ValueKey('mobile-dock-mark-$index'))).width,
        0,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long place name stays on one line inside its column', (
    tester,
  ) async {
    await tester.pumpWidget(
      fixture(
        foot: 34,
        labels: const ['Topics', 'A very long destination', 'Chat', 'Inbox'],
      ),
    );
    await tester.pumpAndSettle();
    final label = find.text('A very long destination');
    expect(label, findsOneWidget);
    final column = tester.getRect(
      find.byKey(const ValueKey('A very long destination')),
    );
    expect(column.width, closeTo(91.5, .01));
    expect(tester.getRect(label).left, greaterThanOrEqualTo(column.left));
    expect(tester.getRect(label).right, lessThanOrEqualTo(column.right));
    expect(tester.getSize(label).height, lessThan(30));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the ⋮ and the action stay reachable side by side at every width',
    (tester) async {
      for (final width in [320.0, 430.0, 700.0]) {
        for (final scale in [1.0, 2.0]) {
          await tester.pumpWidget(fixture(width: width, scale: scale));
          await tester.pumpAndSettle();
          final more = _more;
          final action = find.byType(DMobileDockAction);
          expect(more.hitTestable(), findsOneWidget);
          expect(action.hitTestable(), findsOneWidget);
          expect(tester.getRect(more).width, 40);
          expect(
            tester.getRect(more).right,
            lessThanOrEqualTo(tester.getRect(action).left + .01),
          );
          expect(tester.getSize(action).width, tester.getSize(action).height);
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  for (final direction in TextDirection.values) {
    testWidgets('the ⋮ grows the bar into its panel of the rest ($direction)', (
      tester,
    ) async {
      final changes = <bool>[];
      await tester.pumpWidget(
        fixture(
          foot: 34,
          direction: direction,
          you: you(ring: Colors.green),
          onPanelChanged: changes.add,
        ),
      );
      await tester.pumpAndSettle();
      final frame = tester.getRect(_frame);
      final rest = tester.getRect(_surface);
      expect(_panel, findsNothing);
      expect(tester.widget<DMobileDockItem>(_more).expanded, isFalse);
      await tester.tap(_more);
      // The first frame out: the bar has not moved, so nothing jumps.
      await tester.pump();
      expect(tester.getRect(_surface), rest);
      expect(_panel, findsOneWidget);
      await tester.pumpAndSettle();
      expect(changes, [true]);
      // Three places past the columns and you: one row, 190 tall from the
      // foot, the bar risen 88 to be its head with 16 kept for the grabber.
      final geometry = const DMobileDockGeometry(foot: 34).panel(tiles: 4);
      expect(geometry.height, 190);
      final panel = tester.getRect(_panel);
      expect(panel.left, frame.left);
      expect(panel.right, frame.right);
      expect(panel.bottom, frame.bottom);
      expect(panel.height, 190);
      final head = tester.getRect(_surface);
      expect(head.top, closeTo(frame.bottom - 86 - 88, .01));
      expect(head.width, frame.width);
      final grabber = tester.getRect(find.byKey(DMobileDock.grabberKey));
      expect(grabber.size, const Size(36, 5));
      expect(grabber.top, panel.top + 6);
      expect(grabber.center.dx, closeTo(frame.center.dx, .01));
      // The dim lies over the whole screen under them both.
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(tester.getRect(_dim), Offset.zero & screen);
      final dim = tester.widget<ColoredBox>(_dim).color;
      expect(dim.a, closeTo(.32, .001));
      expect(dim.r + dim.g + dim.b, 0);
      // The tiles, on the bar's columns, you last.
      expect(_tileLabels(tester), [
        'Inbox',
        'Users',
        'A very long destination',
        'Jo',
      ]);
      double fromStart(Rect rect) => direction == TextDirection.ltr
          ? rect.left - panel.left
          : panel.right - rect.right;
      for (final (index, name) in ['Inbox', 'Users'].indexed) {
        final tile = tester.getRect(
          find.byKey(DMobileDock.tileKey(ValueKey(name))),
        );
        expect(fromStart(tile), closeTo(6 + index * 95.5, .01), reason: name);
        expect(tile.width, closeTo(91.5, .01), reason: name);
        expect(tile.height, 56, reason: name);
        expect(tile.top, panel.top + 92, reason: name);
      }
      final youTile = tester.getRect(
        find.byKey(DMobileDock.tileKey(const ValueKey('profile'))),
      );
      expect(fromStart(youTile), closeTo(6 + 3 * 95.5, .01));
      expect(find.text('Jo'), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('face'))).width, 22);
      // The head's places are tiles now, the ⋮ gone and out of reach.
      final topics = find.byKey(const ValueKey('Topics'));
      expect(tester.getSize(topics).height, 56);
      expect(tester.getSize(topics).width, closeTo(91.5, .01));
      expect(tester.widget<DMobileDockItem>(_more).expanded, isTrue);
      expect(_more.hitTestable(), findsNothing);
      expect(
        tester
            .widget<Opacity>(
              find.ancestor(of: _more, matching: find.byType(Opacity)).first,
            )
            .opacity,
        0,
      );
      // The action stands in the middle of the last column, named.
      final action = tester.getRect(find.byType(DMobileDockAction));
      expect(
        fromStart(action) + action.width / 2,
        closeTo(6 + 3 * 95.5 + 91.5 / 2, .01),
      );
      expect(find.text('New topic'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // A press on the dim, over the page, closes it.
      final gesture = await tester.startGesture(Offset(screen.width / 2, 40));
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(changes, [true, false]);
      expect(_panel, findsNothing);
      expect(_dim, findsNothing);
      expect(tester.getRect(_surface), rest);
      expect(tester.widget<DMobileDockItem>(_more).expanded, isFalse);
      expect(_more.hitTestable(), findsOneWidget);
      expect(tester.getSize(topics).height, 50);
      expect(find.text('New topic'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a tile, a head place and you close the panel and go there', (
    tester,
  ) async {
    final pressed = <String>[];
    await tester.pumpWidget(
      fixture(
        foot: 34,
        onPlace: pressed.add,
        you: you(onPressed: () => pressed.add('you')),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> open() async {
      await tester.tap(_more);
      await tester.pumpAndSettle();
      expect(_panel, findsOneWidget);
    }

    await open();
    await tester.tap(find.byKey(DMobileDock.tileKey(const ValueKey('Users'))));
    await tester.pumpAndSettle();
    expect(pressed, ['Users']);
    expect(_panel, findsNothing);
    await open();
    await tester.tap(find.byKey(const ValueKey('Topics')));
    await tester.pumpAndSettle();
    expect(pressed, ['Users', 'Topics']);
    expect(_panel, findsNothing);
    await open();
    await tester.tap(
      find.byKey(DMobileDock.tileKey(const ValueKey('profile'))),
    );
    await tester.pumpAndSettle();
    expect(pressed, ['Users', 'Topics', 'you']);
    expect(_panel, findsNothing);
    // Closed, a place goes there without a panel to close.
    await tester.tap(find.byKey(const ValueKey('Chat')));
    await tester.pumpAndSettle();
    expect(pressed, ['Users', 'Topics', 'you', 'Chat']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the action in the panel\'s head closes it, then does what it '
      'does', (tester) async {
    var acted = 0;
    await tester.pumpWidget(fixture(foot: 34, onAction: () => acted++));
    await tester.pumpAndSettle();
    await tester.tap(_more);
    await tester.pumpAndSettle();
    expect(_panel, findsOneWidget);
    await tester.tap(find.byType(DMobileDockAction));
    await tester.pumpAndSettle();
    expect(acted, 1);
    expect(_panel, findsNothing);
    expect(tester.widget<DMobileDockItem>(_more).expanded, isFalse);
    // Closed, the action does what it does without a panel to close.
    await tester.tap(find.byType(DMobileDockAction));
    await tester.pumpAndSettle();
    expect(acted, 2);
    expect(_panel, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the page in the ⋮\'s slot opens the panel and gives its room '
      'back', (tester) async {
    await tester.pumpWidget(fixture(foot: 34, selected: 'Users'));
    await tester.pumpAndSettle();
    final users = find.byKey(const ValueKey('Users'));
    expect(tester.getSize(users).width, closeTo(78.625, .01));
    await tester.tap(users);
    await tester.pumpAndSettle();
    expect(_panel, findsOneWidget);
    expect(tester.getSize(users).width, 0);
    for (final name in ['Start', 'Topics', 'Chat']) {
      expect(
        tester.getSize(find.byKey(ValueKey(name))).width,
        closeTo(91.5, .01),
        reason: name,
      );
    }
    final tile = find.byKey(DMobileDock.tileKey(const ValueKey('Users')));
    expect(tester.widget<DMobileDockItem>(tile).selected, isTrue);
    expect(
      tester
          .widget<DButton>(
            find.descendant(of: tile, matching: find.byType(DButton)),
          )
          .backgroundColor,
      DTokens.of(tester.element(tile)).foreground.withValues(alpha: .10),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('under reduced motion the panel is out at once', (tester) async {
    await tester.pumpWidget(fixture(foot: 34, reducedMotion: true));
    await tester.pumpAndSettle();
    final frame = tester.getRect(_frame);
    await tester.tap(_more);
    await tester.pump();
    expect(tester.getRect(_surface).top, closeTo(frame.bottom - 86 - 88, .01));
    expect(tester.widget<ColoredBox>(_dim).color.a, closeTo(.32, .001));
    await tester.tap(find.byKey(const ValueKey('Topics')));
    await tester.pump();
    expect(_panel, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the panel is put away with the bar, with no animation', (
    tester,
  ) async {
    final changes = <bool>[];
    await tester.pumpWidget(fixture(foot: 34, onPanelChanged: changes.add));
    await tester.pumpAndSettle();
    await tester.tap(_more);
    await tester.pumpAndSettle();
    expect(_panel, findsOneWidget);
    await tester.pumpWidget(
      fixture(foot: 34, collapsed: true, onPanelChanged: changes.add),
    );
    await tester.pump();
    expect(_panel, findsNothing);
    expect(_dim, findsNothing);
    await tester.pumpAndSettle();
    expect(changes, [true, false]);
    // Something over the bar, a composer's sheet, puts it away too.
    await tester.pumpWidget(fixture(foot: 34));
    await tester.pumpAndSettle();
    await tester.tap(_more);
    await tester.pumpAndSettle();
    expect(_panel, findsOneWidget);
    await tester.pumpWidget(fixture(foot: 34, covered: true));
    await tester.pump();
    expect(_panel, findsNothing);
    await tester.pumpWidget(fixture(foot: 34, covered: true));
    await tester.tap(_more, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    // Nor is there a panel with nothing past the bar's columns.
    await tester.pumpWidget(
      fixture(foot: 34, labels: const ['Start', 'Topics', 'Chat']),
    );
    await tester.pumpAndSettle();
    expect(_more, findsNothing);
    expect(_panel, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a dock taken out of the tree while out says the panel is in', (
    tester,
  ) async {
    final changes = <bool>[];
    await tester.pumpWidget(fixture(foot: 34, onPanelChanged: changes.add));
    await tester.pumpAndSettle();
    await tester.tap(_more);
    await tester.pumpAndSettle();
    expect(changes, [true]);
    await tester.pumpWidget(const SizedBox());
    expect(changes, [true, false]);
    await tester.pumpAndSettle();
    expect(changes, [true, false]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the scroll chrome putting its footer away takes the panel '
      'with it', (tester) async {
    final owner = Object();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(bottom: 34)),
          child: Scaffold(
            body: DScrollChrome(
              identity: 1,
              floatingFooter: true,
              footerBuilder: (hidden) => Builder(
                builder: (context) {
                  final geometry = DMobileDockGeometry.of(context);
                  return Padding(
                    padding: geometry.margin,
                    child: DMobileDock(
                      geometry: geometry,
                      collapsed: hidden,
                      places: [
                        for (final name in ['Start', 'Topics', 'Chat', 'Inbox'])
                          DMobileDockPlace(
                            key: ValueKey(name),
                            icon: const Icon(Icons.forum),
                            label: name,
                            onPressed: () {},
                          ),
                      ],
                      more: (icon: const Icon(Icons.more_vert), label: 'More'),
                      collapsedDestination: DMobileDockItem(
                        collapsed: true,
                        icon: const Icon(Icons.forum),
                        label: 'Reveal',
                        onPressed: () {},
                      ),
                    ),
                  );
                },
              ),
              child: ListView(
                key: const ValueKey('page'),
                children: [for (var i = 0; i < 40; i++) Text('Row $i')],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_more);
    await tester.pumpAndSettle();
    expect(_panel, findsOneWidget);
    final chrome = DScrollChrome.maybeOf(
      tester.element(find.byKey(const ValueKey('page'))),
    )!;
    chrome.setFooterHidden(owner, hidden: true);
    await tester.pump();
    expect(_panel, findsNothing);
    await tester.pumpAndSettle();
    chrome.setFooterHidden(owner, hidden: false);
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    expect(_more.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a sheet opened over the panel goes above it', (tester) async {
    await tester.pumpWidget(fixture(foot: 34));
    await tester.pumpAndSettle();
    await tester.tap(_more);
    await tester.pumpAndSettle();
    final tile = find.byKey(DMobileDock.tileKey(const ValueKey('Users')));
    expect(tile.hitTestable(), findsOneWidget);
    unawaited(
      Navigator.of(tester.element(_more)).push(
        PageRouteBuilder<void>(
          opaque: false,
          pageBuilder: (_, _, _) =>
              const ColoredBox(key: ValueKey('over'), color: Colors.red),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('over')).hitTestable(), findsOneWidget);
    expect(tile.hitTestable(), findsNothing);
    expect(_dim.hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the panel is a modal region of buttons, the current one '
      'selected', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      fixture(
        foot: 34,
        selected: 'Users',
        you: you(ring: Colors.green),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('Users')));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.bySemanticsLabel('Places')),
      matchesSemantics(
        label: 'Places',
        scopesRoute: true,
        namesRoute: true,
        hasDismissAction: true,
      ),
    );
    final users = tester.getSemantics(
      find.byKey(DMobileDock.tileKey(const ValueKey('Users'))),
    );
    expect(
      users,
      matchesSemantics(
        label: 'Users',
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
    expect(
      tester.getSemantics(
        find.byKey(DMobileDock.tileKey(const ValueKey('Inbox'))),
      ),
      // The first tile takes focus as the panel opens.
      matchesSemantics(
        label: 'Inbox',
        isButton: true,
        hasSelectedState: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        isFocused: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    expect(
      tester.getSemantics(
        find.byKey(DMobileDock.tileKey(const ValueKey('profile'))),
      ),
      matchesSemantics(
        label: 'Your account, online',
        isButton: true,
        hasSelectedState: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a drag up on the bar grows it under the finger, past the slop', (
    tester,
  ) async {
    final pressed = <String>[];
    await tester.pumpWidget(fixture(foot: 34, onPlace: pressed.add));
    await tester.pumpAndSettle();
    final rest = tester.getRect(_surface);
    // Three tiles: the panel is 190 tall, 104 of it above the bar's top.
    final topics = tester.getCenter(find.byKey(const ValueKey('Topics')));
    final gesture = await tester.createGesture();
    await gesture.down(topics, timeStamp: Duration.zero);
    await tester.pump();
    await gesture.moveBy(
      const Offset(0, -8),
      timeStamp: const Duration(milliseconds: 16),
    );
    await tester.pump();
    expect(_panel, findsNothing);
    expect(tester.getRect(_surface), rest);
    await gesture.moveBy(
      const Offset(0, -2),
      timeStamp: const Duration(milliseconds: 32),
    );
    await tester.pump();
    expect(_panel, findsOneWidget);
    // Ten pixels of 104: the bar has risen that share of its 88 travel.
    expect(
      tester.getRect(_surface).top,
      closeTo(rest.top - 88 * 10 / 104, .01),
    );
    expect(
      tester.widget<ColoredBox>(_dim).color.a,
      closeTo(.32 * 10 / 104, .001),
    );
    await gesture.moveBy(
      const Offset(0, -42),
      timeStamp: const Duration(milliseconds: 48),
    );
    await tester.pump();
    expect(tester.getRect(_surface).top, closeTo(rest.top - 44, .01));
    expect(tester.widget<ColoredBox>(_dim).color.a, closeTo(.16, .001));
    // Let go still, halfway: it settles open, and Topics was never pressed.
    await gesture.moveBy(
      Offset.zero,
      timeStamp: const Duration(milliseconds: 400),
    );
    await gesture.up(timeStamp: const Duration(milliseconds: 416));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getRect(_surface).top, lessThan(rest.top - 44));
    await tester.pumpAndSettle();
    expect(tester.getRect(_surface).top, closeTo(rest.top - 88, .01));
    expect(pressed, isEmpty);
    expect(tester.widget<DMobileDockItem>(_more).expanded, isTrue);

    // From open, a short push down comes back; a longer one closes.
    final head = tester.getCenter(find.byKey(const ValueKey('Topics')));
    await gesture.down(head, timeStamp: const Duration(seconds: 1));
    await tester.pump();
    await gesture.moveBy(
      const Offset(0, 20),
      timeStamp: const Duration(milliseconds: 1016),
    );
    await tester.pump();
    expect(
      tester.getRect(_surface).top,
      closeTo(rest.top - 88 * (1 - 20 / 104), .01),
    );
    await gesture.moveBy(
      Offset.zero,
      timeStamp: const Duration(milliseconds: 1400),
    );
    await gesture.up(timeStamp: const Duration(milliseconds: 1416));
    await tester.pumpAndSettle();
    expect(tester.getRect(_surface).top, closeTo(rest.top - 88, .01));
    expect(_panel, findsOneWidget);
    await gesture.down(head, timeStamp: const Duration(seconds: 2));
    await tester.pump();
    await gesture.moveBy(
      const Offset(0, 40),
      timeStamp: const Duration(milliseconds: 2016),
    );
    await tester.pump();
    await gesture.moveBy(
      Offset.zero,
      timeStamp: const Duration(milliseconds: 2400),
    );
    await gesture.up(timeStamp: const Duration(milliseconds: 2416));
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    expect(tester.getRect(_surface), rest);
    expect(pressed, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a fling up from a tenth opens; a slow release at a fifth '
      'closes', (tester) async {
    await tester.pumpWidget(fixture(foot: 34));
    await tester.pumpAndSettle();
    final rest = tester.getRect(_surface);
    final topics = tester.getCenter(find.byKey(const ValueKey('Topics')));
    final gesture = await tester.createGesture();
    // 20 of 104 in 20 ms, a pixel a millisecond: a flick, short of a
    // quarter of the way.
    await gesture.down(topics, timeStamp: Duration.zero);
    for (var step = 1; step <= 4; step++) {
      await gesture.moveBy(
        const Offset(0, -5),
        timeStamp: Duration(milliseconds: 5 * step),
      );
    }
    await tester.pump();
    expect(
      tester.getRect(_surface).top,
      closeTo(rest.top - 88 * 20 / 104, .01),
    );
    await gesture.up(timeStamp: const Duration(milliseconds: 24));
    await tester.pumpAndSettle();
    expect(tester.getRect(_surface).top, closeTo(rest.top - 88, .01));
    await tester.tap(find.byKey(const ValueKey('Topics')));
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    // 20.8 of 104 over 300 ms, then still: not a flick, and short of a
    // quarter.
    await gesture.down(topics, timeStamp: const Duration(seconds: 1));
    for (var step = 1; step <= 4; step++) {
      await gesture.moveBy(
        const Offset(0, -5.2),
        timeStamp: Duration(milliseconds: 1000 + 75 * step),
      );
    }
    await tester.pump();
    expect(tester.getRect(_surface).top, closeTo(rest.top - 17.6, .01));
    await gesture.moveBy(
      Offset.zero,
      timeStamp: const Duration(milliseconds: 1500),
    );
    await gesture.up(timeStamp: const Duration(milliseconds: 1516));
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    expect(tester.getRect(_surface), rest);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a touch starting in the home band is the system\'s, not the '
      'bar\'s', (tester) async {
    await tester.pumpWidget(fixture(foot: 34));
    await tester.pumpAndSettle();
    final frame = tester.getRect(_frame);
    // Inside the bar's own bottom padding, 10 above the screen's edge.
    final foot = Offset(frame.center.dx, frame.bottom - 10);
    for (final (kind, grows) in [
      (PointerDeviceKind.touch, false),
      (PointerDeviceKind.mouse, true),
    ]) {
      final gesture = await tester.createGesture(kind: kind);
      await gesture.down(foot, timeStamp: Duration.zero);
      await tester.pump();
      await gesture.moveBy(
        const Offset(0, -60),
        timeStamp: const Duration(milliseconds: 16),
      );
      await tester.pump();
      expect(_panel, grows ? findsOneWidget : findsNothing, reason: '$kind');
      await gesture.up(timeStamp: const Duration(milliseconds: 32));
      await tester.pumpAndSettle();
      if (grows) {
        await tester.tap(find.byKey(const ValueKey('Topics')));
        await tester.pumpAndSettle();
      }
      expect(_panel, findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the panel itself is dragged closed, and a folded bar is not '
      'dragged', (tester) async {
    await tester.pumpWidget(fixture(foot: 34));
    await tester.pumpAndSettle();
    final rest = tester.getRect(_surface);
    await tester.tap(_more);
    await tester.pumpAndSettle();
    final tile = tester.getCenter(
      find.byKey(DMobileDock.tileKey(const ValueKey('Users'))),
    );
    final gesture = await tester.createGesture();
    await gesture.down(tile, timeStamp: Duration.zero);
    await tester.pump();
    await gesture.moveBy(
      const Offset(0, 60),
      timeStamp: const Duration(milliseconds: 16),
    );
    await tester.pump();
    expect(
      tester.getRect(_surface).top,
      closeTo(rest.top - 88 * (1 - 60 / 104), .01),
    );
    await gesture.moveBy(
      const Offset(0, 40),
      timeStamp: const Duration(milliseconds: 32),
    );
    await gesture.up(timeStamp: const Duration(milliseconds: 40));
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    expect(tester.getRect(_surface), rest);

    await tester.pumpWidget(fixture(foot: 34, collapsed: true));
    await tester.pumpAndSettle();
    final circle = tester.getCenter(_surface);
    await gesture.down(circle, timeStamp: const Duration(seconds: 1));
    await tester.pump();
    await gesture.moveBy(
      const Offset(0, -60),
      timeStamp: const Duration(milliseconds: 1016),
    );
    await tester.pump();
    expect(_panel, findsNothing);
    await gesture.up(timeStamp: const Duration(milliseconds: 1032));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a second finger carries the drag on from where the first has '
      'it, and one on the panel moves nothing', (tester) async {
    await tester.pumpWidget(fixture(foot: 34));
    await tester.pumpAndSettle();
    final rest = tester.getRect(_surface);
    final topics = find.byKey(const ValueKey('Topics'));
    // Three tiles: 104 of the panel stands above the bar's top, and the bar
    // rises 88 over it.
    void expectPulled(double pulled) => expect(
      tester.getRect(_surface).top,
      closeTo(rest.top - 88 * pulled / 104, .01),
    );
    final first = await tester.createGesture(pointer: 1);
    await first.down(tester.getCenter(topics), timeStamp: Duration.zero);
    await tester.pump();
    await first.moveBy(
      const Offset(0, -40),
      timeStamp: const Duration(milliseconds: 16),
    );
    await tester.pump();
    expectPulled(40);
    // A second finger lands lower on the risen bar and takes the drag over:
    // the bar goes on from where it is, by how far that finger moves.
    final second = await tester.createGesture(pointer: 2);
    await second.down(
      tester.getCenter(topics) + const Offset(0, 10),
      timeStamp: const Duration(milliseconds: 32),
    );
    await tester.pump();
    await second.moveBy(
      const Offset(0, -15),
      timeStamp: const Duration(milliseconds: 48),
    );
    await tester.pump();
    expectPulled(55);
    await first.up(timeStamp: const Duration(milliseconds: 64));
    await tester.pump();
    expectPulled(55);
    await second.moveBy(
      const Offset(0, -10),
      timeStamp: const Duration(milliseconds: 80),
    );
    await tester.pump();
    expectPulled(65);
    await second.moveBy(
      Offset.zero,
      timeStamp: const Duration(milliseconds: 400),
    );
    await second.up(timeStamp: const Duration(milliseconds: 416));
    await tester.pumpAndSettle();
    expect(_panel, findsOneWidget);
    expectPulled(104);

    // Open, a finger pushing the head down owns the growth; another landing
    // on a tile of the panel meanwhile moves nothing, before or after the
    // first lets go.
    final head = await tester.createGesture(pointer: 3);
    await head.down(
      tester.getCenter(topics),
      timeStamp: const Duration(seconds: 1),
    );
    await tester.pump();
    await head.moveBy(
      const Offset(0, 10),
      timeStamp: const Duration(milliseconds: 1016),
    );
    await tester.pump();
    expectPulled(94);
    final tile = await tester.createGesture(pointer: 4);
    await tile.down(
      tester.getCenter(
        find.byKey(DMobileDock.tileKey(const ValueKey('Users'))),
      ),
      timeStamp: const Duration(milliseconds: 1032),
    );
    await tester.pump();
    await tile.moveBy(
      const Offset(0, 30),
      timeStamp: const Duration(milliseconds: 1048),
    );
    await tester.pump();
    expectPulled(94);
    await head.moveBy(
      const Offset(0, 5),
      timeStamp: const Duration(milliseconds: 1064),
    );
    await tester.pump();
    expectPulled(89);
    await head.moveBy(
      Offset.zero,
      timeStamp: const Duration(milliseconds: 1400),
    );
    await head.up(timeStamp: const Duration(milliseconds: 1416));
    await tester.pumpAndSettle();
    expect(_panel, findsOneWidget);
    expectPulled(104);
    await tile.moveBy(
      const Offset(0, 30),
      timeStamp: const Duration(milliseconds: 1432),
    );
    await tester.pump();
    expectPulled(104);
    await tile.up(timeStamp: const Duration(milliseconds: 1448));
    await tester.pumpAndSettle();
    expect(_panel, findsOneWidget);
    expectPulled(104);
    expect(tester.takeException(), isNull);
  });

  for (final direction in TextDirection.values) {
    testWidgets('a place held still lifts and follows the finger, the places '
        'it crosses make room, and let go it settles where it was put '
        '($direction)', (tester) async {
      final moves = <(int, int)>[];
      final pressed = <String>[];
      var labels = [
        'Start',
        'Topics',
        'Chat',
        'Inbox',
        'Users',
        'A very long destination',
      ];
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => fixture(
            foot: 34,
            direction: direction,
            labels: labels,
            you: you(),
            onPlace: pressed.add,
            onMoved: (from, to) {
              moves.add((from, to));
              setState(
                () => labels = DMobileDockReorder.moved(labels, from, to),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(_more);
      await tester.pumpAndSettle();
      final panel = tester.getRect(_panel);
      final ltr = direction == TextDirection.ltr;
      double fromStart(Rect rect) =>
          ltr ? rect.left - panel.left : panel.right - rect.right;
      // The centre of the slot [start] in from the panel's start edge and
      // [top] below its top edge: the head's tiles at 19, the grid's at 92.
      Offset slotCentre(double start, double top) => Offset(
        ltr ? panel.left + start + 91.5 / 2 : panel.right - start - 91.5 / 2,
        panel.top + top + 28,
      );
      final users = find.byKey(DMobileDock.tileKey(const ValueKey('Users')));
      final grabbed = tester.getCenter(users);
      expect(grabbed, within(distance: .01, from: slotCentre(101.5, 92)));
      final gesture = await tester.createGesture();
      await gesture.down(grabbed, timeStamp: Duration.zero);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Held still, but not yet for the whole hold.
      expect(_moving('Users'), findsNothing);
      await tester.pump(const Duration(milliseconds: 20));
      // Lifted: a tile of its own under the finger, grown to 1.06, raised and
      // shadowed, and the bar's mark stays hidden.
      expect(_moving('Users'), findsOneWidget);
      var lifted = tester.getRect(_moving('Users'));
      expect(lifted.center, within(distance: .01, from: grabbed));
      expect(lifted.width, closeTo(91.5 * 1.06, .01));
      expect(lifted.height, closeTo(56 * 1.06, .01));
      final raised =
          tester
                  .widget<DecoratedBox>(
                    find
                        .ancestor(
                          of: _moving('Users'),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(raised.borderRadius, BorderRadius.circular(16));
      expect(raised.boxShadow, isNull);
      expect(
        tester
            .widget<CustomPaint>(
              find
                  .ancestor(
                    of: find.byWidget(
                      tester.widget<DecoratedBox>(
                        find
                            .ancestor(
                              of: _moving('Users'),
                              matching: find.byType(DecoratedBox),
                            )
                            .first,
                      ),
                    ),
                    matching: find.byType(CustomPaint),
                  )
                  .first,
            )
            .painter,
        isNotNull,
        reason: 'its shadow, DMobileDockReorder.shadow, is cast under it',
      );
      expect(
        tester
            .widget<AnimatedOpacity>(
              find
                  .ancestor(
                    of: find.byKey(const ValueKey('mobile-dock-mark-1')),
                    matching: find.byType(AnimatedOpacity),
                  )
                  .first,
            )
            .opacity,
        0,
      );
      // Brought over Start's slot, off its centre: the tile keeps the offset
      // it was grabbed at, and every place from Start to Inbox makes room,
      // sliding over 220 ms to the slot after its own.
      final start = slotCentre(6, 19) + const Offset(10, 5);
      await gesture.moveTo(start, timeStamp: const Duration(milliseconds: 340));
      await tester.pump();
      lifted = tester.getRect(_moving('Users'));
      expect(lifted.center, within(distance: .01, from: start));
      await tester.pump(const Duration(milliseconds: 110));
      final halfway = fromStart(tester.getRect(_moving('Start')));
      expect(halfway, greaterThan(6));
      expect(halfway, lessThan(101.5));
      await tester.pump(const Duration(milliseconds: 110));
      for (final (name, slot, top) in [
        ('Start', 101.5, 19.0),
        ('Topics', 197.0, 19.0),
        ('Chat', 6.0, 92.0),
        ('Inbox', 101.5, 92.0),
        ('A very long destination', 197.0, 92.0),
      ]) {
        final rect = tester.getRect(_moving(name));
        expect(fromStart(rect), closeTo(slot, .01), reason: name);
        expect(rect.top, closeTo(panel.top + top, .01), reason: name);
        expect(rect.width, closeTo(91.5, .01), reason: name);
      }
      expect(moves, isEmpty);
      // A second finger on the panel meanwhile moves nothing: the lifted
      // place has the panel's drag suspended.
      final second = await tester.createGesture(pointer: 2);
      await second.down(
        Offset(panel.center.dx, panel.top + 8),
        timeStamp: const Duration(milliseconds: 580),
      );
      await tester.pump();
      await second.moveBy(
        const Offset(0, 40),
        timeStamp: const Duration(milliseconds: 596),
      );
      await tester.pump();
      expect(tester.getRect(_surface).top, closeTo(panel.top + 16, .01));
      await second.up(timeStamp: const Duration(milliseconds: 612));
      await tester.pump();
      // Let go, it settles into Start's slot over 200 ms, shrinking back,
      // and the move is told once; then the bar and the panel show the new
      // order, the panel still open and nothing pressed.
      await gesture.up(timeStamp: const Duration(milliseconds: 700));
      await tester.pump();
      expect(moves, [(4, 0)]);
      await tester.pump(const Duration(milliseconds: 100));
      lifted = tester.getRect(_moving('Users'));
      expect(lifted.width, lessThan(91.5 * 1.06));
      expect(lifted.width, greaterThan(91.5));
      final left = (lifted.center - slotCentre(6, 19)).distance;
      expect(left, greaterThan(0));
      expect(left, lessThan(const Offset(10, 5).distance));
      await tester.pumpAndSettle();
      expect(_moving('Users'), findsNothing);
      expect(_barLabels(tester), ['Users', 'Start', 'Topics']);
      expect(_tileLabels(tester), [
        'Chat',
        'Inbox',
        'A very long destination',
        'Jo',
      ]);
      expect(
        fromStart(tester.getRect(find.byKey(const ValueKey('Users')))),
        closeTo(6, .01),
      );
      expect(pressed, isEmpty);
      expect(_panel, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a screen reader moves a place a slot earlier or later while '
      'the panel is out', (tester) async {
    final semantics = tester.ensureSemantics();
    final moves = <(int, int)>[];
    var labels = ['Start', 'Topics', 'Chat', 'Inbox', 'Users', 'Last'];
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => fixture(
          foot: 34,
          labels: labels,
          you: you(),
          onMoved: (from, to) {
            moves.add((from, to));
            setState(() => labels = DMobileDockReorder.moved(labels, from, to));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    const earlier = CustomSemanticsAction(label: 'Move earlier');
    const later = CustomSemanticsAction(label: 'Move later');
    Matcher place(
      String label, {
      bool selected = false,
      bool focused = false,
      List<CustomSemanticsAction> actions = const [],
    }) => matchesSemantics(
      label: label,
      isButton: true,
      hasSelectedState: true,
      isSelected: selected,
      hasEnabledState: true,
      isEnabled: true,
      isFocusable: true,
      isFocused: focused,
      hasTapAction: true,
      hasFocusAction: true,
      customActions: actions,
    );
    // As a bar, its places go nowhere but where they lead.
    expect(
      tester.getSemantics(find.byKey(const ValueKey('Topics'))),
      place('Topics', selected: true),
    );
    await tester.tap(_more);
    await tester.pumpAndSettle();
    // Every place, including the profile, can move; the action stays fixed.
    expect(
      tester.getSemantics(find.byKey(const ValueKey('Start'))),
      place('Start', actions: [later]),
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('Topics'))),
      place('Topics', selected: true, actions: [earlier, later]),
    );
    expect(
      tester.getSemantics(
        find.byKey(DMobileDock.tileKey(const ValueKey('Users'))),
      ),
      place('Users', actions: [earlier, later]),
    );
    expect(
      tester.getSemantics(
        find.byKey(DMobileDock.tileKey(const ValueKey('Last'))),
      ),
      place('Last', actions: [earlier, later]),
    );
    expect(
      tester.getSemantics(
        find.byKey(DMobileDock.tileKey(const ValueKey('profile'))),
      ),
      place('Your account, online', actions: [earlier]),
    );
    expect(
      tester.getSemantics(find.byType(DMobileDockAction)),
      isNot(matchesSemantics(customActions: [earlier])),
    );
    // Asked of a place as a screen reader asks it.
    void move(Finder finder, CustomSemanticsAction action) {
      final node = tester.getSemantics(finder);
      node.owner!.performAction(
        node.id,
        SemanticsAction.customAction,
        CustomSemanticsAction.getIdentifier(action),
      );
    }

    move(find.byKey(DMobileDock.tileKey(const ValueKey('Users'))), earlier);
    await tester.pumpAndSettle();
    expect(moves, [(4, 3)]);
    expect(_tileLabels(tester), ['Users', 'Inbox', 'Last', 'Jo']);
    expect(_panel, findsOneWidget);
    move(find.byKey(const ValueKey('Chat')), later);
    await tester.pumpAndSettle();
    expect(moves, [(4, 3), (2, 3)]);
    expect(_barLabels(tester), ['Start', 'Topics', 'Users']);
    expect(_tileLabels(tester), ['Chat', 'Inbox', 'Last', 'Jo']);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a hold that moves before it lifts drags the panel instead', (
    tester,
  ) async {
    final moves = <(int, int)>[];
    final pressed = <String>[];
    await tester.pumpWidget(
      fixture(
        foot: 34,
        you: you(),
        onPlace: pressed.add,
        onMoved: (from, to) => moves.add((from, to)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_more);
    await tester.pumpAndSettle();
    final panel = tester.getRect(_panel);
    final gesture = await tester.createGesture();
    await gesture.down(
      tester.getCenter(
        find.byKey(DMobileDock.tileKey(const ValueKey('Users'))),
      ),
      timeStamp: Duration.zero,
    );
    await tester.pump();
    await gesture.moveBy(
      const Offset(0, 10),
      timeStamp: const Duration(milliseconds: 100),
    );
    await tester.pump();
    // Four tiles: 104 of the panel stands above the bar's top, and the bar
    // has come down that share of its 88 rise.
    expect(
      tester.getRect(_surface).top,
      closeTo(panel.top + 16 + 88 * 10 / 104, .01),
    );
    await tester.pump(const Duration(milliseconds: 320));
    expect(_moving('Users'), findsNothing);
    await gesture.moveBy(
      Offset.zero,
      timeStamp: const Duration(milliseconds: 500),
    );
    await gesture.up(timeStamp: const Duration(milliseconds: 516));
    await tester.pumpAndSettle();
    expect(_panel, findsOneWidget);
    expect(tester.getRect(_surface).top, closeTo(panel.top + 16, .01));
    expect(moves, isEmpty);
    expect(pressed, isEmpty);
    // Moved as far sideways, which is no drag of the panel, the hold is
    // given up all the same, and the release is the tap it always was.
    await gesture.down(
      tester.getCenter(
        find.byKey(DMobileDock.tileKey(const ValueKey('Users'))),
      ),
      timeStamp: const Duration(seconds: 1),
    );
    await tester.pump();
    await gesture.moveBy(
      const Offset(10, 0),
      timeStamp: const Duration(milliseconds: 1100),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(_moving('Users'), findsNothing);
    expect(tester.getRect(_surface).top, closeTo(panel.top + 16, .01));
    await gesture.up(timeStamp: const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(moves, isEmpty);
    expect(pressed, ['Users']);
    expect(_panel, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a place lifted and let go where it was is not pressed', (
    tester,
  ) async {
    final moves = <(int, int)>[];
    final pressed = <String>[];
    await tester.pumpWidget(
      fixture(
        foot: 34,
        you: you(),
        onPlace: pressed.add,
        onMoved: (from, to) => moves.add((from, to)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_more);
    await tester.pumpAndSettle();
    final gesture = await tester.createGesture();
    await gesture.down(
      tester.getCenter(
        find.byKey(DMobileDock.tileKey(const ValueKey('Users'))),
      ),
      timeStamp: Duration.zero,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(_moving('Users'), findsOneWidget);
    await gesture.up(timeStamp: const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(_moving('Users'), findsNothing);
    expect(pressed, isEmpty);
    expect(moves, isEmpty);
    expect(_panel, findsOneWidget);
    expect(_tileLabels(tester), [
      'Inbox',
      'Users',
      'A very long destination',
      'Jo',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('under reduced motion a moved place and the places it displaces '
      'are in their slots at once', (tester) async {
    var labels = ['Start', 'Topics', 'Chat', 'Inbox', 'Users', 'Last'];
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => fixture(
          foot: 34,
          reducedMotion: true,
          labels: labels,
          you: you(),
          onMoved: (from, to) => setState(
            () => labels = DMobileDockReorder.moved(labels, from, to),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_more);
    await tester.pumpAndSettle();
    final panel = tester.getRect(_panel);
    final gesture = await tester.createGesture();
    await gesture.down(
      tester.getCenter(
        find.byKey(DMobileDock.tileKey(const ValueKey('Users'))),
      ),
      timeStamp: Duration.zero,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    await gesture.moveTo(
      Offset(panel.left + 6 + 91.5 / 2, panel.top + 19 + 28),
      timeStamp: const Duration(milliseconds: 340),
    );
    await tester.pump();
    expect(
      tester.getRect(_moving('Start')).left,
      closeTo(panel.left + 101.5, .01),
    );
    await gesture.up(timeStamp: const Duration(milliseconds: 400));
    await tester.pump();
    expect(_moving('Users'), findsNothing);
    expect(_barLabels(tester), ['Users', 'Start', 'Topics']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the panel closing under a lifted place sets it down unmoved', (
    tester,
  ) async {
    final moves = <(int, int)>[];
    await tester.pumpWidget(
      fixture(
        foot: 34,
        you: you(),
        onMoved: (from, to) => moves.add((from, to)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_more);
    await tester.pumpAndSettle();
    final gesture = await tester.createGesture();
    await gesture.down(
      tester.getCenter(
        find.byKey(DMobileDock.tileKey(const ValueKey('Users'))),
      ),
      timeStamp: Duration.zero,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(_moving('Users'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(_moving('Users'), findsNothing);
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    await gesture.moveBy(
      const Offset(0, -30),
      timeStamp: const Duration(milliseconds: 500),
    );
    await gesture.up(timeStamp: const Duration(milliseconds: 516));
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    expect(moves, isEmpty);
    expect(_barLabels(tester), ['Start', 'Topics', 'Chat']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the same places come in another order under a lifted place, '
      'and it is set down with nothing moved', (tester) async {
    final moves = <(int, int)>[];
    final pressed = <String>[];
    var labels = ['Start', 'Topics', 'Chat', 'Inbox', 'Users', 'Last'];
    late StateSetter rebuild;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return fixture(
            foot: 34,
            labels: labels,
            you: you(),
            onPlace: pressed.add,
            onMoved: (from, to) {
              moves.add((from, to));
              setState(
                () => labels = DMobileDockReorder.moved(labels, from, to),
              );
            },
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_more);
    await tester.pumpAndSettle();
    final panel = tester.getRect(_panel);
    final gesture = await tester.createGesture();
    await gesture.down(
      tester.getCenter(
        find.byKey(DMobileDock.tileKey(const ValueKey('Users'))),
      ),
      timeStamp: Duration.zero,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(_moving('Users'), findsOneWidget);
    // A stored order read late, or a screen reader's move, brings the same
    // places in another order: the lifted place is of an order no longer
    // shown, and carrying it to Start's slot and letting go moves nothing.
    rebuild(
      () => labels = ['Last', 'Start', 'Topics', 'Chat', 'Inbox', 'Users'],
    );
    await tester.pump();
    await gesture.moveTo(
      Offset(panel.left + 6 + 91.5 / 2, panel.top + 19 + 28),
      timeStamp: const Duration(milliseconds: 340),
    );
    await tester.pump();
    await gesture.up(timeStamp: const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(moves, isEmpty);
    expect(pressed, isEmpty);
    expect(_barLabels(tester), ['Last', 'Start', 'Topics']);
    expect(_tileLabels(tester), ['Chat', 'Inbox', 'Users', 'Jo']);
    expect(_moving('Users'), findsNothing);
    expect(_panel, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a place moved by a screen reader is the same tile after, to the '
      'reader and to the keyboard, in the grid and in the head', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var labels = ['Start', 'Topics', 'Chat', 'Inbox', 'Users', 'Last'];
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => fixture(
          foot: 34,
          labels: labels,
          you: you(),
          onMoved: (from, to) => setState(
            () => labels = DMobileDockReorder.moved(labels, from, to),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_more);
    await tester.pumpAndSettle();
    void moveLater(Finder finder) {
      final node = tester.getSemantics(finder);
      node.owner!.performAction(
        node.id,
        SemanticsAction.customAction,
        CustomSemanticsAction.getIdentifier(
          const CustomSemanticsAction(label: 'Move later'),
        ),
      );
    }

    // The panel open, its first tile, Inbox, has the focus. Moved later it
    // is the tile it was: the same node to a reader, who need not find it
    // again, and still the one with the focus.
    final inbox = find.byKey(DMobileDock.tileKey(const ValueKey('Inbox')));
    expect(_focusedKey(), DMobileDock.tileKey(const ValueKey('Inbox')));
    final inboxNode = tester.getSemantics(inbox).id;
    final inboxElement = tester.element(inbox);
    moveLater(inbox);
    await tester.pumpAndSettle();
    expect(_tileLabels(tester), ['Users', 'Inbox', 'Last', 'Jo']);
    expect(tester.getSemantics(inbox).id, inboxNode);
    expect(tester.element(inbox), same(inboxElement));
    expect(tester.getSemantics(inbox), isSemantics(isFocused: true));
    expect(_focusedKey(), DMobileDock.tileKey(const ValueKey('Inbox')));
    // In the head likewise.
    final topics = find.byKey(const ValueKey('Topics'));
    final topicsNode = tester.getSemantics(topics).id;
    final topicsElement = tester.element(topics);
    moveLater(topics);
    await tester.pumpAndSettle();
    expect(_barLabels(tester), ['Start', 'Chat', 'Topics']);
    expect(tester.getSemantics(topics).id, topicsNode);
    expect(tester.element(topics), same(topicsElement));
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape closes the panel and gives the ⋮ its focus back', (
    tester,
  ) async {
    await tester.pumpWidget(fixture(foot: 34));
    await tester.pumpAndSettle();
    final moreFocus = tester.widget<DMobileDockItem>(_more).focusNode!;
    await tester.tap(_more);
    await tester.pumpAndSettle();
    expect(_panel, findsOneWidget);
    expect(moreFocus.hasFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    expect(moreFocus.hasFocus, isTrue);
    // A page standing in the ⋮'s slot opened it, and takes the focus back.
    await tester.pumpWidget(fixture(foot: 34, selected: 'Users'));
    await tester.pumpAndSettle();
    final users = find.byKey(const ValueKey('Users'));
    final usersFocus = tester.widget<DMobileDockItem>(users).focusNode!;
    await tester.tap(users);
    await tester.pumpAndSettle();
    expect(_panel, findsOneWidget);
    expect(usersFocus.hasFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    expect(usersFocus.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a drag that settles closed leaves the focus where it was; one '
      'that settles open takes it, and gives it back', (tester) async {
    final field = FocusNode(debugLabel: 'field');
    addTearDown(field.dispose);
    await tester.pumpWidget(
      fixture(
        foot: 34,
        page: Focus(focusNode: field, child: const SizedBox(height: 40)),
      ),
    );
    await tester.pumpAndSettle();
    field.requestFocus();
    await tester.pump();
    expect(field.hasFocus, isTrue);
    final topics = tester.getCenter(find.byKey(const ValueKey('Topics')));
    final gesture = await tester.createGesture();
    await gesture.down(topics, timeStamp: Duration.zero);
    await tester.pump();
    await gesture.moveBy(
      const Offset(0, -20),
      timeStamp: const Duration(milliseconds: 16),
    );
    await tester.pump();
    expect(_panel, findsOneWidget);
    // Under the finger the panel is not open: what was typed in keeps the
    // focus, and the keyboard with it.
    expect(field.hasFocus, isTrue);
    await gesture.moveBy(
      Offset.zero,
      timeStamp: const Duration(milliseconds: 400),
    );
    await gesture.up(timeStamp: const Duration(milliseconds: 416));
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    expect(field.hasFocus, isTrue);
    // Let go to settle open, the panel takes the focus to its first tile,
    // and gives it back to the field as it closes.
    await gesture.down(topics, timeStamp: const Duration(seconds: 1));
    await tester.pump();
    await gesture.moveBy(
      const Offset(0, -60),
      timeStamp: const Duration(milliseconds: 1016),
    );
    await tester.pump();
    expect(field.hasFocus, isTrue);
    await gesture.moveBy(
      Offset.zero,
      timeStamp: const Duration(milliseconds: 1400),
    );
    await gesture.up(timeStamp: const Duration(milliseconds: 1416));
    await tester.pumpAndSettle();
    expect(_panel, findsOneWidget);
    expect(field.hasFocus, isFalse);
    expect(_focusedKey(), DMobileDock.tileKey(const ValueKey('Inbox')));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    expect(field.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the keyboard reaches the head and the action from the grid, '
      'and never the ⋮ while the panel is out', (tester) async {
    await tester.pumpWidget(fixture(foot: 34, you: you()));
    await tester.pumpAndSettle();
    final moreFocus = tester.widget<DMobileDockItem>(_more).focusNode!;
    await tester.tap(_more);
    await tester.pumpAndSettle();
    final inbox = DMobileDock.tileKey(const ValueKey('Inbox'));
    expect(_focusedKey(), inbox);
    await _tab(tester, back: true);
    expect(_focusedKey(), const ValueKey('action'));
    await _tab(tester, back: true);
    expect(_focusedKey(), const ValueKey('Chat'));
    await _tab(tester, back: true);
    expect(_focusedKey(), const ValueKey('Topics'));
    await _tab(tester);
    await _tab(tester);
    await _tab(tester);
    expect(_focusedKey(), inbox);
    await _tab(tester);
    expect(_focusedKey(), DMobileDock.tileKey(const ValueKey('Users')));
    await _tab(tester);
    await _tab(tester);
    expect(_focusedKey(), DMobileDock.tileKey(const ValueKey('profile')));
    // Past the last tile, the head comes round again.
    await _tab(tester);
    expect(_focusedKey(), const ValueKey('Start'));
    expect(moreFocus.hasFocus, isFalse);
    // Nothing in particular had the focus before the ⋮ was pressed, so the
    // ⋮ takes it as the panel closes.
    await tester.tapAt(tester.getTopLeft(_dim) + const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    expect(moreFocus.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a trackpad swipe grows the bar and settles once it rests', (
    tester,
  ) async {
    await tester.pumpWidget(fixture(foot: 34));
    await tester.pumpAndSettle();
    final rest = tester.getRect(_surface);
    final bar = tester.getCenter(find.byKey(const ValueKey('Topics')));
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    // Fingers moving up the trackpad push the bar up: 20 of 104, then 60.
    await gesture.panZoomStart(bar, timeStamp: Duration.zero);
    await gesture.panZoomUpdate(
      bar,
      pan: const Offset(0, -20),
      timeStamp: const Duration(milliseconds: 16),
    );
    await tester.pump();
    expect(_panel, findsOneWidget);
    expect(
      tester.getRect(_surface).top,
      closeTo(rest.top - 88 * 20 / 104, .01),
    );
    await gesture.panZoomUpdate(
      bar,
      pan: const Offset(0, -60),
      timeStamp: const Duration(milliseconds: 32),
    );
    await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 40));
    await tester.pump();
    expect(
      tester.getRect(_surface).top,
      closeTo(rest.top - 88 * 60 / 104, .01),
    );
    // It rests 180 ms after the last movement, then settles the way it went.
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.getRect(_surface).top,
      closeTo(rest.top - 88 * 60 / 104, .01),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(tester.getRect(_surface).top, closeTo(rest.top - 88, .01));
    expect(tester.widget<DMobileDockItem>(_more).expanded, isTrue);

    // Momentum arriving within 160 ms of settling is the same swipe.
    final head = tester.getCenter(find.byKey(const ValueKey('Topics')));
    await gesture.panZoomStart(
      head,
      timeStamp: const Duration(milliseconds: 250),
    );
    await gesture.panZoomUpdate(
      head,
      pan: const Offset(0, 30),
      timeStamp: const Duration(milliseconds: 266),
    );
    await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 270));
    await tester.pump();
    expect(tester.getRect(_surface).top, closeTo(rest.top - 88, .01));
    await tester.pumpAndSettle();
    expect(_panel, findsOneWidget);

    // A short push down from open comes back; a longer one closes.
    await gesture.panZoomStart(head, timeStamp: const Duration(seconds: 2));
    await gesture.panZoomUpdate(
      head,
      pan: const Offset(0, 1),
      timeStamp: const Duration(milliseconds: 2016),
    );
    await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 2020));
    await tester.pump();
    expect(
      tester.getRect(_surface).top,
      closeTo(rest.top - 88 * (1 - 1 / 104), .01),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(_panel, findsOneWidget);
    expect(tester.getRect(_surface).top, closeTo(rest.top - 88, .01));
    await gesture.panZoomStart(head, timeStamp: const Duration(seconds: 3));
    await gesture.panZoomUpdate(
      head,
      pan: const Offset(0, 10),
      timeStamp: const Duration(milliseconds: 3016),
    );
    await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 3020));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    expect(tester.getRect(_surface), rest);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wheel turned down over the bar grows it as a swipe does', (
    tester,
  ) async {
    await tester.pumpWidget(fixture(foot: 34));
    await tester.pumpAndSettle();
    final rest = tester.getRect(_surface);
    final bar = tester.getCenter(find.byKey(const ValueKey('Topics')));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: bar,
        scrollDelta: const Offset(0, 30),
        timeStamp: const Duration(milliseconds: 16),
      ),
    );
    await tester.pump();
    expect(_panel, findsOneWidget);
    expect(
      tester.getRect(_surface).top,
      closeTo(rest.top - 88 * 30 / 104, .01),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(tester.getRect(_surface).top, closeTo(rest.top - 88, .01));
    // A turn up over the dim, over the page, closes it.
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(400, 40),
        scrollDelta: Offset(0, -60),
        timeStamp: Duration(seconds: 1),
      ),
    );
    await tester.pump();
    expect(
      tester.getRect(_surface).top,
      closeTo(rest.top - 88 * (1 - 60 / 104), .01),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
