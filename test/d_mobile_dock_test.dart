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
  ValueChanged<int>? onOverflow,
  VoidCallback? onReveal,
  bool hidden = false,
  ThemeData? theme,
  Color backdrop = Colors.white,
  bool highContrast = false,
  bool reducedMotion = false,
}) => MaterialApp(
  theme: theme,
  home: MediaQuery(
    data: MediaQueryData(
      textScaler: TextScaler.linear(scale),
      highContrast: highContrast,
      disableAnimations: reducedMotion,
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
              width: width,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: DMobileDock(
                  collapsed: collapsed,
                  destinationsHidden: hidden,
                  onOverflowChanged: onOverflow ?? (_) {},
                  destinations: [
                    for (final name in [
                      'Start',
                      'Topics',
                      'Chat',
                      'Inbox',
                      'Users',
                      'A very long destination',
                    ])
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
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

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
      'actionless dock fills the capsule with navigation ($direction)',
      (tester) async {
        for (final scale in [1.0, 2.0]) {
          await tester.pumpWidget(
            fixture(withAction: false, direction: direction, scale: scale),
          );
          await tester.pumpAndSettle();
          expect(find.byType(DMobileDockAction), findsNothing);
          final surface = tester.getRect(
            find.byKey(const ValueKey('mobile-dock-surface')),
          );
          final more = tester.getRect(find.byKey(const ValueKey('more')));
          if (direction == TextDirection.ltr) {
            expect(more.right, closeTo(surface.right - 6, .01));
          } else {
            expect(more.left, closeTo(surface.left + 6, .01));
          }
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  for (final brightness in Brightness.values) {
    {
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
          final destination = tester.getRect(
            find.byKey(const ValueKey('Topics')),
          );
          final action = tester.getRect(find.byType(DMobileDockAction));
          expect(surface.height, 62);
          expect(destination.height, 50);
          expect(destination.top - surface.top, 6);
          expect(surface.bottom - destination.bottom, 6);
          expect(surface.right - action.right, 6);

          expect(tester.takeException(), isNull);
        },
      );
    }
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
      'measures labels and badges, keeps overflow and action visible ($direction)',
      (tester) async {
        var shown = 0;
        await tester.pumpWidget(
          fixture(direction: direction, onOverflow: (n) => shown = n),
        );
        await tester.pumpAndSettle();
        expect(shown, 3);
        final surface = tester.getRect(
          find.byKey(const ValueKey('mobile-dock-surface')),
        );
        for (final key in ['Start', 'Topics', 'Chat', 'more']) {
          final item = find.byKey(ValueKey(key));
          expect(item.hitTestable(), findsOneWidget);
          final rect = tester.getRect(item);
          expect(rect.left, greaterThanOrEqualTo(surface.left));
          expect(rect.right, lessThanOrEqualTo(surface.right));
        }
        expect(find.byKey(const ValueKey('Inbox')).hitTestable(), findsNothing);
        expect(find.text('More'), findsNothing);
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
  testWidgets(
    'large text spills destinations without clipping action or More',
    (tester) async {
      for (final width in [320.0, 430.0, 700.0]) {
        await tester.pumpWidget(fixture(width: width, scale: 2));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('more')).hitTestable(),
          findsOneWidget,
        );
        expect(find.byType(DMobileDockAction).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
