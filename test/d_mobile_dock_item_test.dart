import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('dock actions and destinations scale together on $platform', (
      tester,
    ) async {
      var presses = 0;
      for (final scale in [1.0, 17 / 14, 2.0, 3.0]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light.copyWith(platform: platform),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Row(
                  children: [
                    DMobileDockItem(
                      icon: const DIcon(DIcons.comment),
                      label: 'Chat',
                      onPressed: () {},
                    ),
                    DButton.iconOnly(
                      key: const ValueKey('action'),
                      density: DButtonDensity.mobileDockAction,
                      shape: DButtonShape.pill,
                      icon: const DIcon(DIcons.plus),
                      tooltip: 'New chat',
                      onPressed: () => presses++,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final action = find.byKey(const ValueKey('action'));
        final actionIcon = find.descendant(
          of: action,
          matching: find.byType(DIcon),
        );
        final destinationIcon = find.descendant(
          of: find.byType(DMobileDockItem),
          matching: find.byType(DIcon),
        );
        expect(
          tester.getSize(actionIcon).height,
          tester.getSize(destinationIcon).height,
        );
        expect(
          tester.getSize(actionIcon).height,
          scale == 1 ? 20 : greaterThan(20),
        );
        expect(tester.getCenter(actionIcon), tester.getCenter(action));
        final surface = find.descendant(
          of: action,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container && widget.decoration is DButtonDecoration,
          ),
        );
        expect(tester.getRect(action), tester.getRect(surface));
        expect(tester.getSize(action).width, tester.getSize(action).height);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(presses, 4);
    });
  }

  for (final direction in TextDirection.values) {
    testWidgets('a bare item is its glyph alone, its count on the glyph\'s '
        'corner ($direction)', (tester) async {
      var presses = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
          home: Directionality(
            textDirection: direction,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 72,
                  child: DMobileDockItem(
                    bare: true,
                    icon: const Icon(Icons.chat_bubble),
                    label: 'Chat',
                    badge: DBadge.unreadChip(count: 32),
                    onPressed: () => presses++,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final item = tester.getRect(find.byType(DMobileDockItem));
      final count = tester.getRect(find.byType(DBadge));
      final glyph = tester.getRect(
        find.byKey(const ValueKey('mobile-dock-glyph')),
      );
      expect(find.text('Chat'), findsNothing);
      expect(item.height, 50);
      expect(glyph.center.dy, item.center.dy);
      expect(count.top, item.top + 6);
      expect(count.height, 20);
      expect(count.width, tester.getSize(find.text('32')).width + 14);
      if (direction == TextDirection.ltr) {
        expect(count.left, item.center.dx + 6);
      } else {
        expect(count.right, item.center.dx - 6);
      }
      // The count is drawn over the item's own target: pressed, the item is.
      await tester.tapAt(count.center);
      await tester.pump();
      expect(presses, 1);
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel(RegExp('Chat')), findsOneWidget);
      semantics.dispose();
      expect(tester.takeException(), isNull);
    });
  }

  for (final (platform, chipHeight) in [
    (TargetPlatform.iOS, 20.0),
    (TargetPlatform.macOS, 16.0),
  ]) {
    testWidgets('a grown item keeps its unread chip whole beside an unmoved '
        'label on $platform', (tester) async {
      Future<void> pump({required bool counted}) => tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: platform),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 96,
                child: DMobileDockItem(
                  growth: 1,
                  icon: const Icon(Icons.chat_bubble),
                  label: 'Chat',
                  badge: counted ? DBadge.unreadChip(count: 32) : null,
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      );

      await pump(counted: false);
      final label = find.text('Chat');
      final alone = tester.getRect(label).top;
      await pump(counted: true);
      final item = tester.getRect(find.byType(DMobileDockItem));
      final chip = tester.getRect(find.byType(DBadge));
      final figures = tester.getRect(find.text('32'));
      expect(chip.height, chipHeight);
      expect(figures.top, greaterThanOrEqualTo(chip.top));
      expect(figures.bottom, lessThanOrEqualTo(chip.bottom));
      expect(chip.center.dy, tester.getRect(label).center.dy);
      expect(chip.top, greaterThanOrEqualTo(item.top));
      expect(chip.bottom, lessThanOrEqualTo(item.bottom));
      expect(tester.getRect(label).top, alone);
      expect(
        tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    testWidgets('dock item keeps one target and an inline count on $platform', (
      tester,
    ) async {
      var presses = 0;
      Future<void> pump({bool selected = false, double scale = 1}) =>
          tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light.copyWith(platform: platform),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: 72,
                      child: DMobileDockItem(
                        icon: const Icon(Icons.chat_bubble),
                        label: 'Chat',
                        selected: selected,
                        badge: const DBadge.overlay(child: Text('32')),
                        onPressed: () => presses++,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );

      await pump();
      final item = find.byType(DMobileDockItem);
      final label = find.text('Chat');
      final count = find.text('32');
      final capsule = find.descendant(
        of: item,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container && widget.decoration is DButtonDecoration,
        ),
      );
      expect(tester.getSize(item).width, 72);
      expect(tester.getSize(item).height, 50);
      expect(tester.getRect(capsule), tester.getRect(item));
      expect(
        tester.getRect(count).left,
        greaterThan(tester.getRect(label).right),
      );
      expect(
        tester.getRect(count).center.dy,
        closeTo(tester.getRect(label).center.dy, 1),
      );
      await tester.tapAt(tester.getCenter(count));
      await tester.pump();
      expect(presses, 1);

      await pump(selected: true);
      await tester.pumpAndSettle();
      // The bar marks the current place on its own edge; the item keeps no
      // fill and says it by weight and colour.
      final decoration =
          tester.widget<Container>(capsule).decoration as DButtonDecoration;
      expect(decoration.color, Colors.transparent);
      expect(tester.widget<Text>(label).style?.fontWeight, FontWeight.w600);

      await pump(selected: true, scale: 2);
      await tester.pumpAndSettle();
      expect(tester.getSize(item).height, greaterThan(48));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a focused item keeps the focus as its count comes and goes and '
      'as it is named again', (tester) async {
    var presses = 0;
    Future<void> pump({required bool counted, bool bare = true}) =>
        tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 72,
                  child: DMobileDockItem(
                    bare: bare,
                    growth: bare ? 0 : 1,
                    icon: const Icon(Icons.inbox),
                    label: 'Notifications',
                    badge: counted ? DBadge.unreadChip(count: 3) : null,
                    onPressed: () => presses++,
                  ),
                ),
              ),
            ),
          ),
        );

    await pump(counted: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focused = FocusManager.instance.primaryFocus!;
    expect(
      find.descendant(
        of: find.byType(DMobileDockItem),
        matching: find.byWidget(focused.context!.widget),
      ),
      findsOneWidget,
    );
    for (final (counted, bare) in [
      (false, true),
      (true, true),
      (true, false),
    ]) {
      await pump(counted: counted, bare: bare);
      expect(
        focused.hasPrimaryFocus,
        isTrue,
        reason: 'counted $counted, bare $bare',
      );
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(presses, 1);
    expect(tester.takeException(), isNull);
  });
}
