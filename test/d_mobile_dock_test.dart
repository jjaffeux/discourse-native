import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/dock_panel.dart';

Widget fixture({
  double width = 390,
  bool collapsed = false,
  bool withAction = true,
  String actionLabel = 'New topic',
  bool notifications = true,
  int notificationsCount = 3,
  bool notificationsOpen = false,
  VoidCallback? onNotifications,
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
  DMobileDockPeek? peek,
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
                          peek: peek,
                          places: [
                            for (final name in labels)
                              DMobileDockPlace(
                                key: ValueKey(name),
                                icon: const Icon(Icons.forum),
                                label: name,
                                badge: name == 'Chat'
                                    ? DBadge.unreadChip(
                                        count: 100,
                                        semanticLabel: '100 urgent messages',
                                      )
                                    : null,
                                selected: name == selected,
                                onPressed: () => onPlace?.call(name),
                              ),
                            ?you,
                          ],
                          notifications: notifications
                              ? DMobileDockPlace(
                                  key: const ValueKey('notifications'),
                                  icon: const Icon(Icons.inbox),
                                  label: 'Notifications',
                                  badge:
                                      notificationsOpen ||
                                          notificationsCount == 0
                                      ? null
                                      : DBadge.unreadChip(
                                          count: notificationsCount,
                                          semanticLabel:
                                              '$notificationsCount unread items',
                                        ),
                                  selected: notificationsOpen,
                                  onPressed: onNotifications ?? () {},
                                )
                              : null,
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
                                  label: actionLabel,
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
final _notifications = find.byKey(const ValueKey('notifications'));

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
    if (item.key != const ValueKey('notifications')) item.label,
];

/// The place called [name] as it is drawn while a place is being moved.
Finder _moving(String name) => find.descendant(
  of: find.byKey(DMobileDock.movingKey(ValueKey(name))),
  matching: find.byType(DMobileDockItem),
);

/// The key of the place, the tile, the action or the grabber holding the
/// focus.
Key? _focusedKey() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  Key? key;
  context.visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is DMobileDockItem ||
        widget is DMobileDockAction ||
        widget.key == DMobileDock.grabberKey) {
      key = widget.key;
      return false;
    }
    return true;
  });
  return key;
}

/// The count a bare place wears on its glyph's corner, or beside its name.
Finder _countIn(Finder place) =>
    find.descendant(of: place, matching: find.byType(DBadge));

/// The opacity something is drawn at, as the nearest [AnimatedOpacity] over
/// it says.
double _opacityOver(WidgetTester tester, Finder finder) => tester
    .widget<AnimatedOpacity>(
      find.ancestor(of: finder, matching: find.byType(AnimatedOpacity)).first,
    )
    .opacity;

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
      'an actionless dock keeps notifications in the fourth column ($direction)',
      (tester) async {
        for (final scale in [1.0, 2.0]) {
          await tester.pumpWidget(
            fixture(withAction: false, direction: direction, scale: scale),
          );
          await tester.pumpAndSettle();
          expect(find.byType(DMobileDockAction), findsNothing);
          final surface = tester.getRect(_surface);
          final notifications = tester.getRect(_notifications);
          // The capsule is 378 wide: 366 inside, columns of 70 and 4 gaps.
          expect(notifications.width, closeTo(70, .01));
          if (direction == TextDirection.ltr) {
            expect(notifications.left, closeTo(surface.left + 6 + 222, .01));
          } else {
            expect(notifications.right, closeTo(surface.right - 6 - 222, .01));
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
        // The action's middle stands 37 in from the screen's edge.
        if (direction == TextDirection.ltr) {
          expect(surface.right - action.center.dx, 37);
        } else {
          expect(action.center.dx - surface.left, 37);
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
      'three places, notifications and the action take the five columns, '
      'the places their glyphs alone ($direction)',
      (tester) async {
        await tester.pumpWidget(fixture(foot: 34, direction: direction));
        await tester.pumpAndSettle();
        final surface = tester.getRect(_surface);
        // 390 wide at the foot: 378 inside, columns of 72.4 and 4 gaps.
        double fromStart(Rect rect) => direction == TextDirection.ltr
            ? rect.left - surface.left - 6
            : surface.right - 6 - rect.right;
        for (final (index, key) in [
          'Start',
          'Topics',
          'Chat',
          'notifications',
        ].indexed) {
          final item = find.byKey(ValueKey(key));
          expect(item.hitTestable(), findsOneWidget);
          final rect = tester.getRect(item);
          expect(fromStart(rect), closeTo(index * 76.4, .01), reason: key);
          expect(rect.width, closeTo(72.4, .01), reason: key);
          expect(rect.height, 50);
        }
        final action = tester.getRect(find.byType(DMobileDockAction));
        expect(fromStart(action), closeTo(322, .01));
        expect(action.size, const Size(50, 50));
        expect(find.byKey(const ValueKey('Inbox')).hitTestable(), findsNothing);
        expect(find.byKey(const ValueKey('Inbox')), findsNothing);
        expect(find.text('More'), findsNothing);
        expect(find.text('New topic'), findsNothing);
        // Closed, the places are their glyphs alone, named to a reader.
        for (final name in ['Start', 'Topics', 'Chat', 'Notifications']) {
          expect(find.text(name), findsNothing, reason: name);
        }
        expect(
          tester.widget<DButton>(find.byType(DButton).last).tooltip,
          'New topic',
        );
        final semantics = tester.ensureSemantics();
        expect(
          tester.getSemantics(find.byKey(const ValueKey('Topics'))),
          matchesSemantics(
            label: 'Topics',
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
          tester.getSemantics(_notifications).getSemanticsData().label,
          contains('Notifications'),
        );
        semantics.dispose();
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final direction in TextDirection.values) {
    testWidgets(
      'closed, a place\'s count rides its glyph\'s corner; grown, it sits '
      'beside the name ($direction)',
      (tester) async {
        await tester.pumpWidget(fixture(foot: 34, direction: direction));
        await tester.pumpAndSettle();
        final chat = find.byKey(const ValueKey('Chat'));
        final count = _countIn(chat);
        expect(count, findsOneWidget);
        expect(find.text('99+'), findsOneWidget);
        expect(find.text('Chat'), findsNothing);
        var place = tester.getRect(chat);
        var chip = tester.getRect(count);
        expect(chip.top, place.top + 6);
        if (direction == TextDirection.ltr) {
          expect(chip.left, closeTo(place.center.dx + 6, .01));
        } else {
          expect(chip.right, closeTo(place.center.dx - 6, .01));
        }
        // The glyph alone is centred on the row.
        final glyph = find.descendant(
          of: chat,
          matching: find.byKey(const ValueKey('mobile-dock-glyph')),
        );
        expect(tester.getRect(glyph).center.dy, closeTo(place.center.dy, .01));
        // The count is the place's: pressed, the place is.
        final pressed = <String>[];
        await tester.pumpWidget(
          fixture(foot: 34, direction: direction, onPlace: pressed.add),
        );
        await tester.tapAt(tester.getCenter(count));
        await tester.pump();
        expect(pressed, ['Chat']);
        // Grown, the names come back and the count stands beside its name.
        await openDockPanel(tester);
        expect(find.text('Chat'), findsOneWidget);
        place = tester.getRect(chat);
        chip = tester.getRect(count);
        final name = tester.getRect(find.text('Chat'));
        expect(chip.center.dy, closeTo(name.center.dy, 1));
        if (direction == TextDirection.ltr) {
          expect(chip.left, greaterThan(name.right));
        } else {
          expect(chip.right, lessThan(name.left));
        }
        expect(chip.top, greaterThan(place.top + 6));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('notifications is fixed before the action: its count hidden '
      'while its menu is open, which pressing it toggles', (tester) async {
    var open = false;
    var toggled = 0;
    late StateSetter rebuild;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return fixture(
            foot: 34,
            notificationsCount: 5,
            notificationsOpen: open,
            onNotifications: () {
              toggled++;
              setState(() => open = !open);
            },
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    Rect mark(int index) =>
        tester.getRect(find.byKey(ValueKey('mobile-dock-mark-$index')));
    final item = tester.widget<DMobileDockItem>(_notifications);
    expect(item.hasPopup, isTrue);
    expect(item.expanded, isFalse);
    expect(item.selected, isFalse);
    expect(find.text('5'), findsOneWidget);
    expect(mark(3).width, 0);
    // Pressed, the menu opens: the count goes and the bar marks it.
    await tester.tap(_notifications);
    await tester.pumpAndSettle();
    expect(toggled, 1);
    expect(find.text('5'), findsNothing);
    expect(tester.widget<DMobileDockItem>(_notifications).selected, isTrue);
    expect(tester.widget<DMobileDockItem>(_notifications).expanded, isTrue);
    expect(mark(3).size, const Size(28, 4));
    expect(
      mark(3).center.dx,
      closeTo(tester.getCenter(_notifications).dx, .01),
    );
    // Topics stays marked too: the menu is open over the page.
    expect(mark(1).width, 28);
    await tester.tap(_notifications);
    await tester.pumpAndSettle();
    expect(toggled, 2);
    expect(find.text('5'), findsOneWidget);
    expect(mark(3).width, 0);
    // In the panel's head, it closes the panel first, as the places do.
    await openDockPanel(tester);
    expect(find.text('Notifications'), findsOneWidget);
    await tester.tap(_notifications);
    await tester.pumpAndSettle();
    expect(toggled, 3);
    expect(_panel, findsNothing);
    // A bar with nothing to count shows no count, and a signed-out bar has
    // no notifications place at all.
    rebuild(() {});
    await tester.pumpWidget(fixture(foot: 34, notificationsCount: 0));
    await tester.pumpAndSettle();
    expect(_countIn(_notifications), findsNothing);
    await tester.pumpWidget(fixture(foot: 34, notifications: false));
    await tester.pumpAndSettle();
    expect(_notifications, findsNothing);
    expect(
      tester.getRect(find.byKey(const ValueKey('Chat'))).width,
      closeTo(72.4, .01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a phone\'s bar has no ⋮; the panel\'s grabber is a button that '
      'puts the panel away', (tester) async {
    final semantics = tester.ensureSemantics();
    final changes = <bool>[];
    await tester.pumpWidget(fixture(foot: 34, onPanelChanged: changes.add));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<DMobileDockItem>(
            find.descendant(
              of: _surface,
              matching: find.byType(DMobileDockItem),
            ),
          )
          .map((item) => item.label),
      ['Start', 'Topics', 'Chat', 'Notifications'],
    );
    expect(find.byIcon(Icons.more_vert), findsNothing);
    await openDockPanel(tester);
    expect(changes, [true]);
    final grabber = find.byKey(DMobileDock.grabberKey);
    expect(tester.getSize(grabber), const Size(36, 5));
    expect(
      tester.getSemantics(grabber),
      matchesSemantics(
        label: 'Fewer places',
        isButton: true,
        hasExpandedState: true,
        isExpanded: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    await tester.tap(grabber);
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    expect(changes, [true, false]);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a grown action\'s name takes its column at most, cut short', (
    tester,
  ) async {
    await tester.pumpWidget(
      fixture(foot: 34, actionLabel: 'A very long action name'),
    );
    await tester.pumpAndSettle();
    await openDockPanel(tester);
    final name = find.text('A very long action name');
    expect(name, findsOneWidget);
    expect(tester.getSize(name).width, lessThanOrEqualTo(72.4 - 8 + .01));
    expect(tester.widget<Text>(name).overflow, TextOverflow.ellipsis);
    expect(tester.widget<Text>(name).maxLines, 1);
    expect(tester.takeException(), isNull);
  });
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
    testWidgets('the current page past the bar\'s columns is added before '
        'notifications, the five sharing the four columns\' room, and eases '
        'away as the bar grows ($direction)', (tester) async {
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
      final here = find.byKey(const ValueKey('A very long destination'));
      expect(here.hitTestable(), findsOneWidget);
      expect(tester.widget<DMobileDockItem>(here).hasPopup, isTrue);
      expect(tester.widget<DMobileDockItem>(here).selected, isTrue);
      // (4 * 72.4 + 3 * 4 - 4 * 4) / 5, with the gaps kept.
      for (final (index, key) in [
        'Start',
        'Topics',
        'Chat',
        'A very long destination',
        'notifications',
      ].indexed) {
        final rect = tester.getRect(find.byKey(ValueKey(key)));
        expect(fromStart(rect), closeTo(index * 61.12, .01), reason: key);
        expect(rect.width, closeTo(57.12, .01), reason: key);
      }
      expect(find.text('A very long destination'), findsNothing);
      final action = tester.getRect(find.byType(DMobileDockAction));
      expect(fromStart(action), closeTo(322, .01));
      // Pressed, it grows the bar; grown, it has eased away, its gap with
      // it, and the places after it stand in their columns.
      await tester.tap(here);
      await tester.pumpAndSettle();
      expect(_panel, findsOneWidget);
      expect(tester.getSize(here).width, 0);
      expect(_opacityOver(tester, here), 0);
      expect(here.hitTestable(), findsNothing);
      for (final (index, key) in [
        'Start',
        'Topics',
        'Chat',
        'notifications',
      ].indexed) {
        final rect = tester.getRect(find.byKey(ValueKey(key)));
        expect(fromStart(rect), closeTo(index * 76.4, .01), reason: key);
        expect(rect.width, closeTo(72.4, .01), reason: key);
      }
      expect(fromStart(tester.getRect(here)), closeTo(3 * 76.4, .01));
      expect(tester.takeException(), isNull);
    });
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

  testWidgets('the page added to the bar carries the mark', (tester) async {
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
    // Named once the bar has grown.
    await openDockPanel(tester);
    final label = find.text('A very long destination');
    expect(label, findsOneWidget);
    final column = tester.getRect(
      find.byKey(const ValueKey('A very long destination')),
    );
    expect(column.width, closeTo(72.4, .01));
    expect(tester.getRect(label).left, greaterThanOrEqualTo(column.left));
    expect(tester.getRect(label).right, lessThanOrEqualTo(column.right));
    expect(tester.getSize(label).height, lessThan(30));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'notifications and the action stay reachable side by side at every width',
    (tester) async {
      for (final width in [320.0, 430.0, 700.0]) {
        for (final scale in [1.0, 2.0]) {
          await tester.pumpWidget(fixture(width: width, scale: scale));
          await tester.pumpAndSettle();
          final action = find.byType(DMobileDockAction);
          expect(_notifications.hitTestable(), findsOneWidget);
          expect(action.hitTestable(), findsOneWidget);
          expect(
            tester.getRect(_notifications).right,
            lessThanOrEqualTo(tester.getRect(action).left + .01),
          );
          expect(tester.getSize(action).width, tester.getSize(action).height);
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  for (final direction in TextDirection.values) {
    testWidgets('pulled up, the bar grows into its panel of the rest '
        '($direction)', (tester) async {
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
      await openDockPanel(tester);
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
      // The tiles, on the bar's five columns, you last.
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
        expect(fromStart(tile), closeTo(6 + index * 76.4, .01), reason: name);
        expect(tile.width, closeTo(72.4, .01), reason: name);
        expect(tile.height, 56, reason: name);
        expect(tile.top, panel.top + 92, reason: name);
      }
      final youTile = tester.getRect(
        find.byKey(DMobileDock.tileKey(const ValueKey('profile'))),
      );
      expect(fromStart(youTile), closeTo(6 + 3 * 76.4, .01));
      expect(find.text('Jo'), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('face'))).width, 22);
      // The head's places are tiles now, named again, notifications among
      // them.
      final topics = find.byKey(const ValueKey('Topics'));
      expect(tester.getSize(topics).height, 56);
      expect(tester.getSize(topics).width, closeTo(72.4, .01));
      expect(find.text('Topics'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      expect(
        fromStart(tester.getRect(_notifications)),
        closeTo(6 + 3 * 76.4, .01),
      );
      // The action stands in the middle of the last column, named.
      final action = tester.getRect(find.byType(DMobileDockAction));
      expect(
        fromStart(action) + action.width / 2,
        closeTo(6 + 4 * 76.4 + 72.4 / 2, .01),
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
      expect(tester.getSize(topics).height, 50);
      expect(find.text('Topics'), findsNothing);
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
    Future<void> open() => openDockPanel(tester);

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
    await openDockPanel(tester);
    await tester.tap(find.byType(DMobileDockAction));
    await tester.pumpAndSettle();
    expect(acted, 1);
    expect(_panel, findsNothing);
    // Closed, the action does what it does without a panel to close.
    await tester.tap(find.byType(DMobileDockAction));
    await tester.pumpAndSettle();
    expect(acted, 2);
    expect(_panel, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the page added to the bar opens the panel and gives its room '
      'back', (tester) async {
    await tester.pumpWidget(fixture(foot: 34, selected: 'Users'));
    await tester.pumpAndSettle();
    final users = find.byKey(const ValueKey('Users'));
    expect(tester.getSize(users).width, closeTo(57.12, .01));
    final rest = tester.getRect(_surface);
    await tester.tap(users);
    // The first frame out: the bar has not moved, so nothing jumps.
    await tester.pump();
    expect(tester.getRect(_surface), rest);
    expect(_panel, findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.getSize(users).width, 0);
    for (final name in ['Start', 'Topics', 'Chat', 'notifications']) {
      expect(
        tester.getSize(find.byKey(ValueKey(name))).width,
        closeTo(72.4, .01),
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
    await tester.pumpWidget(
      fixture(foot: 34, reducedMotion: true, selected: 'Users'),
    );
    await tester.pumpAndSettle();
    final frame = tester.getRect(_frame);
    await tester.tap(find.byKey(const ValueKey('Users')));
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
    await openDockPanel(tester);
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
    await openDockPanel(tester);
    await tester.pumpWidget(fixture(foot: 34, covered: true));
    await tester.pump();
    expect(_panel, findsNothing);
    await tester.pumpWidget(fixture(foot: 34, covered: true));
    await openDockPanel(tester, settlesOpen: false);
    // Nor is there a panel with nothing past the bar's columns.
    await tester.pumpWidget(
      fixture(foot: 34, labels: const ['Start', 'Topics', 'Chat']),
    );
    await tester.pumpAndSettle();
    await openDockPanel(tester, settlesOpen: false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a dock taken out of the tree while out says the panel is in', (
    tester,
  ) async {
    final changes = <bool>[];
    await tester.pumpWidget(fixture(foot: 34, onPanelChanged: changes.add));
    await tester.pumpAndSettle();
    await openDockPanel(tester);
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
    await openDockPanel(tester);
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
    expect(find.byKey(const ValueKey('Start')).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a sheet opened over the panel goes above it', (tester) async {
    await tester.pumpWidget(fixture(foot: 34));
    await tester.pumpAndSettle();
    await openDockPanel(tester);
    final tile = find.byKey(DMobileDock.tileKey(const ValueKey('Users')));
    expect(tile.hitTestable(), findsOneWidget);
    unawaited(
      Navigator.of(tester.element(find.byKey(const ValueKey('Topics')))).push(
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
    expect(find.text('Topics'), findsOneWidget);

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
    await openDockPanel(tester);
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
      await openDockPanel(tester);
      final panel = tester.getRect(_panel);
      final ltr = direction == TextDirection.ltr;
      double fromStart(Rect rect) =>
          ltr ? rect.left - panel.left : panel.right - rect.right;
      // The centre of the slot [start] in from the panel's start edge and
      // [top] below its top edge: the head's tiles at 19, the grid's at 92.
      Offset slotCentre(double start, double top) => Offset(
        ltr ? panel.left + start + 72.4 / 2 : panel.right - start - 72.4 / 2,
        panel.top + top + 28,
      );
      final users = find.byKey(DMobileDock.tileKey(const ValueKey('Users')));
      final grabbed = tester.getCenter(users);
      expect(grabbed, within(distance: .01, from: slotCentre(82.4, 92)));
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
      expect(lifted.width, closeTo(72.4 * 1.06, .01));
      expect(lifted.height, closeTo(56 * 1.06, .01));
      // What cannot be moved steps back: notifications and the action.
      expect(_opacityOver(tester, _notifications), .4);
      expect(_opacityOver(tester, find.byType(DMobileDockAction)), .4);
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
      expect(halfway, lessThan(82.4));
      await tester.pump(const Duration(milliseconds: 110));
      for (final (name, slot, top) in [
        ('Start', 82.4, 19.0),
        ('Topics', 158.8, 19.0),
        ('Chat', 6.0, 92.0),
        ('Inbox', 82.4, 92.0),
        ('A very long destination', 158.8, 92.0),
      ]) {
        final rect = tester.getRect(_moving(name));
        expect(fromStart(rect), closeTo(slot, .01), reason: name);
        expect(rect.top, closeTo(panel.top + top, .01), reason: name);
        expect(rect.width, closeTo(72.4, .01), reason: name);
      }
      // Notifications stays put, in its column, and is no slot: carried over
      // it, the lifted place is still bound where it last was.
      expect(_moving('Notifications'), findsNothing);
      expect(fromStart(tester.getRect(_notifications)), closeTo(235.2, .01));
      await gesture.moveTo(
        tester.getCenter(_notifications),
        timeStamp: const Duration(milliseconds: 560),
      );
      await tester.pump();
      expect(
        fromStart(tester.getRect(_moving('Start'))),
        closeTo(82.4, .01),
        reason: 'Start keeps making room for it',
      );
      await gesture.moveTo(start, timeStamp: const Duration(milliseconds: 570));
      await tester.pump();
      expect(moves, isEmpty);
      // A second finger on the panel meanwhile moves nothing: the lifted
      // place has the panel's drag suspended.
      final second = await tester.createGesture();
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
      expect(lifted.width, lessThan(72.4 * 1.06));
      expect(lifted.width, greaterThan(72.4));
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
    await openDockPanel(tester);
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
    await openDockPanel(tester);
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
    await openDockPanel(tester);
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
    await openDockPanel(tester);
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
      Offset(panel.left + 6 + 72.4 / 2, panel.top + 19 + 28),
      timeStamp: const Duration(milliseconds: 340),
    );
    await tester.pump();
    expect(
      tester.getRect(_moving('Start')).left,
      closeTo(panel.left + 82.4, .01),
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
    await openDockPanel(tester);
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
    await openDockPanel(tester);
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
      Offset(panel.left + 6 + 72.4 / 2, panel.top + 19 + 28),
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
    await openDockPanel(tester);
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

  testWidgets('notifications cannot be lifted, and a screen reader is not '
      'offered to move it', (tester) async {
    final semantics = tester.ensureSemantics();
    final moves = <(int, int)>[];
    await tester.pumpWidget(
      fixture(
        foot: 34,
        you: you(),
        onMoved: (from, to) => moves.add((from, to)),
      ),
    );
    await tester.pumpAndSettle();
    await openDockPanel(tester);
    expect(
      tester
          .getSemantics(_notifications)
          .getSemanticsData()
          .customSemanticsActionIds,
      anyOf(isNull, isEmpty),
    );
    final gesture = await tester.createGesture();
    await gesture.down(
      tester.getCenter(_notifications),
      timeStamp: Duration.zero,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.byKey(DMobileDock.movingKey(const ValueKey('notifications'))),
      findsNothing,
    );
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('Start'))),
      timeStamp: const Duration(milliseconds: 420),
    );
    await tester.pump();
    await gesture.up(timeStamp: const Duration(milliseconds: 440));
    await tester.pumpAndSettle();
    expect(moves, isEmpty);
    expect(_barLabels(tester), ['Start', 'Topics', 'Chat']);
    expect(_panel, findsOneWidget);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape closes the panel and gives the bar\'s first place its '
      'focus back', (tester) async {
    await tester.pumpWidget(fixture(foot: 34));
    await tester.pumpAndSettle();
    final start = find.byKey(const ValueKey('Start'));
    final startFocus = tester.widget<DMobileDockItem>(start).focusNode!;
    await openDockPanel(tester);
    expect(startFocus.hasFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    expect(startFocus.hasFocus, isTrue);
    // The page added to the bar opened it, and takes the focus back.
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

  testWidgets('the keyboard goes round the grabber, the head, notifications, '
      'the action and the grid, and never the page added while the panel '
      'is out', (tester) async {
    await tester.pumpWidget(fixture(foot: 34, you: you(), selected: 'Users'));
    await tester.pumpAndSettle();
    final users = find.byKey(const ValueKey('Users'));
    final usersFocus = tester.widget<DMobileDockItem>(users).focusNode!;
    await openDockPanel(tester);
    final inbox = DMobileDock.tileKey(const ValueKey('Inbox'));
    expect(_focusedKey(), inbox);
    await _tab(tester, back: true);
    expect(_focusedKey(), const ValueKey('action'));
    await _tab(tester, back: true);
    expect(_focusedKey(), const ValueKey('notifications'));
    await _tab(tester, back: true);
    expect(_focusedKey(), const ValueKey('Chat'));
    await _tab(tester, back: true);
    expect(_focusedKey(), const ValueKey('Topics'));
    await _tab(tester, back: true);
    expect(_focusedKey(), const ValueKey('Start'));
    await _tab(tester, back: true);
    expect(_focusedKey(), DMobileDock.grabberKey);
    for (var step = 0; step < 6; step++) {
      await _tab(tester);
    }
    expect(_focusedKey(), inbox);
    // The page added keeps its tile in the grid, lit as the current one.
    await _tab(tester);
    expect(_focusedKey(), DMobileDock.tileKey(const ValueKey('Users')));
    await _tab(tester);
    await _tab(tester);
    expect(_focusedKey(), DMobileDock.tileKey(const ValueKey('profile')));
    // Past the last tile, the grabber comes round again.
    await _tab(tester);
    expect(_focusedKey(), DMobileDock.grabberKey);
    expect(usersFocus.hasFocus, isFalse);
    // Nothing in particular had the focus before the panel was pulled out,
    // so the page added to the bar takes it as the panel closes.
    await tester.tapAt(tester.getTopLeft(_dim) + const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(_panel, findsNothing);
    expect(usersFocus.hasFocus, isTrue);
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
    expect(find.text('Topics'), findsOneWidget);

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

  group('the peek on opening', () {
    final hint = find.text('Swipe up for more');
    final peeked = find.byKey(DMobileDock.peekKey);
    const nine = [
      'Start',
      'Topics',
      'Chat',
      'Inbox',
      'Users',
      'Events',
      'Groups',
      'Badges',
      'Settings',
    ];

    double hintOpacity(WidgetTester tester) => tester
        .widget<Opacity>(
          find.ancestor(of: hint, matching: find.byType(Opacity)).first,
        )
        .opacity;

    testWidgets('the first bar given the session\'s peek lifts once, 900 ms '
        'after it can grow, and settles back; no bar given it after does', (
      tester,
    ) async {
      final peek = DMobileDockPeek();
      await tester.pumpWidget(fixture(foot: 34, peek: peek));
      final rest = tester.getRect(_surface);
      await tester.pump(const Duration(milliseconds: 899));
      expect(hint, findsNothing);
      expect(peeked, findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(hint, findsOneWidget);
      expect(hintOpacity(tester), 0);
      // On the settle spring, past its lift and back.
      await tester.pump(const Duration(milliseconds: 230));
      expect(tester.getRect(_surface).top, lessThan(rest.top - 47));
      await tester.pump(const Duration(milliseconds: 230));
      // 30, and half the foot of 34.
      expect(tester.getRect(_surface).top, closeTo(rest.top - 47, .01));
      expect(tester.getRect(peeked).top, closeTo(rest.top - 47, .01));
      expect(tester.getRect(peeked).bottom, rest.bottom);
      expect(hintOpacity(tester), 1);
      expect(_panel, findsNothing);
      expect(_dim, findsNothing);
      // Up for 3.7 s from its lift, then down the same way.
      await tester.pump(const Duration(milliseconds: 3239));
      expect(tester.getRect(_surface).top, closeTo(rest.top - 47, .01));
      expect(hintOpacity(tester), 1);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 200));
      expect(hintOpacity(tester), 0);
      // Over once the bar is back down, with nothing left to settle.
      await tester.pump(const Duration(milliseconds: 260));
      expect(tester.getRect(_surface), rest);
      await tester.pump(const Duration(milliseconds: 1));
      expect(hint, findsNothing);
      expect(peeked, findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.getRect(_surface), rest);

      // The same session's bar, built again, stays put.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(fixture(foot: 34, peek: peek));
      await tester.pump(const Duration(seconds: 5));
      expect(hint, findsNothing);
      expect(tester.getRect(_surface), rest);
      // Another session's does not.
      await tester.pumpWidget(fixture(foot: 34, peek: DMobileDockPeek()));
      await tester.pump(const Duration(milliseconds: 900));
      expect(hint, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a bar with nothing to grow into waits to peek until it has', (
      tester,
    ) async {
      final peek = DMobileDockPeek();
      await tester.pumpWidget(
        fixture(foot: 34, peek: peek, labels: const ['Start', 'Topics']),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(hint, findsNothing);
      await tester.pumpWidget(fixture(foot: 34, peek: peek));
      await tester.pump(const Duration(milliseconds: 899));
      expect(hint, findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      expect(hint, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('grown, folded, or under a drag when it is due, the bar does '
        'not peek, then or later', (tester) async {
      Future<void> stillAfterwards() async {
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 5));
        expect(hint, findsNothing);
        expect(peeked, findsNothing);
      }

      await tester.pumpWidget(fixture(foot: 34, peek: DMobileDockPeek()));
      await openDockPanel(tester);
      await tester.pump(const Duration(milliseconds: 900));
      expect(hint, findsNothing);
      await tester.tap(find.byKey(DMobileDock.grabberKey));
      await stillAfterwards();

      final folded = DMobileDockPeek();
      await tester.pumpWidget(fixture(foot: 34, peek: folded, collapsed: true));
      await tester.pump(const Duration(milliseconds: 900));
      expect(hint, findsNothing);
      await tester.pumpWidget(fixture(foot: 34, peek: folded));
      await stillAfterwards();

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(fixture(foot: 34, peek: DMobileDockPeek()));
      final gesture = await tester.createGesture();
      await gesture.down(
        tester.getCenter(find.byKey(const ValueKey('Topics'))),
        timeStamp: Duration.zero,
      );
      await gesture.moveBy(
        const Offset(0, -12),
        timeStamp: const Duration(milliseconds: 16),
      );
      await tester.pump(const Duration(milliseconds: 1000));
      expect(_panel, findsOneWidget);
      expect(hint, findsNothing);
      await gesture.up(timeStamp: const Duration(milliseconds: 1000));
      await stillAfterwards();
      expect(tester.takeException(), isNull);
    });

    for (final (foot, width) in [(34.0, 390.0), (0.0, 375.0)]) {
      testWidgets('the hint stands between the lifted glyphs and half the '
          'foot, the panel under the bar up to its top (foot $foot)', (
        tester,
      ) async {
        await tester.pumpWidget(
          fixture(foot: foot, width: width, peek: DMobileDockPeek()),
        );
        final rest = tester.getRect(_surface);
        final screen = tester.getRect(_frame);
        await tester.pump(const Duration(milliseconds: 900));
        await tester.pump(const Duration(milliseconds: 500));
        final peek = 30 + foot / 2;
        final box = tester.getRect(find.byKey(DMobileDock.hintKey));
        expect(box.left, screen.left);
        expect(box.width, width);
        expect(box.bottom, closeTo(screen.bottom - foot / 2, .01));
        // The glyphs' bottom stood 45 above the foot of 34, 27 above a
        // square screen's, and stands the peek higher now.
        final glyph = tester.getRect(
          find.descendant(
            of: find.byKey(const ValueKey('Topics')),
            matching: find.byType(Icon),
          ),
        );
        expect(
          screen.bottom - glyph.bottom,
          closeTo((foot > 0 ? 45 : 27) + peek, .01),
        );
        expect(box.top, closeTo(glyph.bottom, .01));
        expect(tester.getCenter(hint).dy, closeTo(box.center.dy, .01));
        // The panel runs the screen's width under the bar, up to the bar's
        // own lifted top.
        final panel = tester.getRect(peeked);
        expect(panel.left, screen.left);
        expect(panel.width, width);
        expect(panel.bottom, screen.bottom);
        expect(panel.top, closeTo(rest.top - peek, .01));
        expect(tester.getRect(_surface).top, closeTo(rest.top - peek, .01));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a pull during the peek carries on from where the bar has '
        'lifted, and the hint goes as it would have', (tester) async {
      await tester.pumpWidget(fixture(foot: 34, peek: DMobileDockPeek()));
      final rest = tester.getRect(_surface);
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 500));
      final gesture = await tester.createGesture();
      await gesture.down(
        tester.getCenter(find.byKey(const ValueKey('Topics'))),
        timeStamp: const Duration(seconds: 2),
      );
      await tester.pump();
      await gesture.moveBy(
        const Offset(0, -8),
        timeStamp: const Duration(milliseconds: 2016),
      );
      await tester.pump();
      expect(_panel, findsNothing);
      expect(tester.getRect(_surface).top, closeTo(rest.top - 47, .01));
      await gesture.moveBy(
        const Offset(0, -2),
        timeStamp: const Duration(milliseconds: 2032),
      );
      await tester.pump();
      // Three tiles: the lift of 47 is that share of the bar's 88 travel,
      // and the 10 pulled that share of the panel's 104 above the bar.
      expect(_panel, findsOneWidget);
      expect(
        tester.getRect(_surface).top,
        closeTo(rest.top - 47 - 88 * 10 / 104, .01),
      );
      expect(peeked, findsNothing);
      expect(hint, findsOneWidget);
      expect(hintOpacity(tester), 1);
      await tester.pump(const Duration(milliseconds: 200));
      expect(hintOpacity(tester), 0);
      await tester.pump(const Duration(milliseconds: 280));
      expect(hint, findsNothing);
      await gesture.up(timeStamp: const Duration(milliseconds: 2600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('let go still a little past where the peek had lifted it, '
        'the bar opens, as from closed', (tester) async {
      await tester.pumpWidget(
        fixture(foot: 34, peek: DMobileDockPeek(), labels: nine),
      );
      final rest = tester.getRect(_surface);
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 500));
      final gesture = await tester.createGesture();
      await gesture.down(
        tester.getCenter(find.byKey(const ValueKey('Topics'))),
        timeStamp: const Duration(seconds: 2),
      );
      await tester.pump();
      await gesture.moveBy(
        const Offset(0, -10),
        timeStamp: const Duration(milliseconds: 2016),
      );
      await tester.pump();
      // Six tiles: 47 of the bar's 158 travel, then 10 of the panel's 174
      // above the bar, about a third of the way.
      expect(
        tester.getRect(_surface).top,
        closeTo(rest.top - 47 - 158 * 10 / 174, .01),
      );
      await gesture.moveBy(
        Offset.zero,
        timeStamp: const Duration(milliseconds: 2400),
      );
      await gesture.up(timeStamp: const Duration(milliseconds: 2416));
      await tester.pumpAndSettle();
      expect(_panel, findsOneWidget);
      expect(tester.getRect(_surface).top, closeTo(rest.top - 158, .01));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a trackpad swipe during the peek carries on from it too', (
      tester,
    ) async {
      await tester.pumpWidget(fixture(foot: 34, peek: DMobileDockPeek()));
      final rest = tester.getRect(_surface);
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byKey(const ValueKey('Topics'))),
          scrollDelta: const Offset(0, 10),
          timeStamp: const Duration(seconds: 2),
        ),
      );
      await tester.pump();
      expect(_panel, findsOneWidget);
      expect(
        tester.getRect(_surface).top,
        closeTo(rest.top - 47 - 88 * 10 / 104, .01),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(tester.getRect(_surface).top, closeTo(rest.top - 88, .01));
      expect(hint, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the page added to the bar, pressed during the peek, opens '
        'the panel from where the bar has lifted', (tester) async {
      await tester.pumpWidget(
        fixture(foot: 34, peek: DMobileDockPeek(), selected: 'Users'),
      );
      final rest = tester.getRect(_surface);
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const ValueKey('Users')));
      await tester.pump();
      expect(_panel, findsOneWidget);
      expect(tester.getRect(_surface).top, closeTo(rest.top - 47, .01));
      await tester.pumpAndSettle();
      expect(tester.getRect(_surface).top, closeTo(rest.top - 88, .01));
      expect(hint, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('covered during the peek, the bar is back in its place at once '
        'and does not peek again', (tester) async {
      final peek = DMobileDockPeek();
      await tester.pumpWidget(fixture(foot: 34, peek: peek));
      final rest = tester.getRect(_surface);
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(fixture(foot: 34, peek: peek, covered: true));
      expect(hint, findsNothing);
      expect(peeked, findsNothing);
      expect(tester.getRect(_surface), rest);
      await tester.pump();
      await tester.pumpWidget(fixture(foot: 34, peek: peek));
      await tester.pump(const Duration(seconds: 5));
      expect(hint, findsNothing);
      expect(tester.getRect(_surface), rest);
      expect(tester.takeException(), isNull);
    });

    testWidgets('during the peek a place is pressed as ever, and the hint is '
        'not read', (tester) async {
      final semantics = tester.ensureSemantics();
      final pressed = <String>[];
      await tester.pumpWidget(
        fixture(foot: 34, peek: DMobileDockPeek(), onPlace: pressed.add),
      );
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 500));
      expect(hint, findsOneWidget);
      expect(find.bySemanticsLabel('Swipe up for more'), findsNothing);
      expect(find.bySemanticsLabel('Chat'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('Chat')));
      await tester.pump();
      expect(pressed, ['Chat']);
      expect(_panel, findsNothing);
      expect(hint, findsOneWidget);
      semantics.dispose();
      expect(tester.takeException(), isNull);
    });

    testWidgets('under reduced motion the bar is up and down at once, and no '
        'light passes over the hint', (tester) async {
      await tester.pumpWidget(
        fixture(foot: 34, peek: DMobileDockPeek(), reducedMotion: true),
      );
      final rest = tester.getRect(_surface);
      await tester.pump(const Duration(milliseconds: 900));
      expect(tester.getRect(_surface).top, closeTo(rest.top - 47, .01));
      expect(hintOpacity(tester), 1);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pump(const Duration(milliseconds: 3700));
      expect(tester.getRect(_surface), rest);
      await tester.pump();
      expect(hint, findsNothing);
      expect(peeked, findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('with motion, a light passes over the hint while it is up', (
      tester,
    ) async {
      await tester.pumpWidget(fixture(foot: 34, peek: DMobileDockPeek()));
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 1000));
      expect(hintOpacity(tester), 1);
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pump(const Duration(milliseconds: 2700));
      await tester.pumpAndSettle();
      expect(hint, findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
