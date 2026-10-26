import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget fixture({
  double width = 390,
  bool collapsed = false,
  bool withAction = true,
  TextDirection direction = TextDirection.ltr,
  double scale = 1,
  VoidCallback? onReveal,
  List<String> labels = const [
    'Start',
    'Topics',
    'Chat',
    'Inbox',
    'Users',
    'A very long destination',
  ],
  bool hidden = false,
  ThemeData? theme,
  Color backdrop = Colors.white,
  bool highContrast = false,
  bool reducedMotion = false,
  double foot = 0,
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
          body: Align(
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
                      places: [
                        for (final name in labels)
                          DMobileDockItem(
                            key: ValueKey(name),
                            icon: const Icon(Icons.forum),
                            label: name,
                            badge: name == 'Chat'
                                ? const DBadge.overlay(child: Text('99+'))
                                : null,
                            selected: name == 'Topics',
                            onPressed: () {},
                          ),
                      ],
                      more: DMobileDockItem(
                        key: const ValueKey('more'),
                        bare: true,
                        icon: const Icon(Icons.more_vert),
                        label: 'More',
                        onPressed: () {},
                      ),
                      collapsedDestination: DMobileDockItem(
                        key: const ValueKey('reveal'),
                        collapsed: true,
                        icon: const Icon(Icons.forum),
                        label: 'Reveal navigation',
                        onPressed: onReveal ?? () {},
                      ),
                      action: withAction
                          ? DMobileDockAction(
                              icon: const Icon(Icons.add),
                              label: 'New topic',
                              onPressed: () {},
                            )
                          : null,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

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
          final more = tester.getRect(find.byKey(const ValueKey('more')));
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
        final more = tester.getRect(find.byKey(const ValueKey('more')));
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
        expect(
          tester
              .getSemantics(find.byKey(const ValueKey('more')))
              .getSemanticsData()
              .label,
          'More',
        );
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
          final more = find.byKey(const ValueKey('more'));
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
}
