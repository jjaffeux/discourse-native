import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/mockup_control_sizes_example.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:discourse_native/src/theme/d_native_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.iOS,
    TargetPlatform.android,
  ]) {
    testWidgets(
      '$platform retains filter and icon-chip artwork and usable targets',
      (tester) async {
        var presses = 0;
        await _mount(
          tester,
          platform,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DButton(
                key: const Key('filter'),
                size: DControlSize.filter,
                label: const Text('Latest'),
                icon: const DIcon(DNativeIcons.filterChevron, size: 10),
                iconPosition: DButtonIconPosition.end,
                onPressed: () => presses++,
              ),
              DButton.iconOnly(
                key: const Key('bookmark'),
                size: DControlSize.chip,
                icon: const DIcon(DIcons.bookmark),
                tooltip: 'Bookmark',
                onPressed: () => presses++,
              ),
            ],
          ),
        );
        expect(tester.getSize(_surface(const Key('filter'))).height, 30.75);
        // Reference Fa rounds the 384/512 bookmark viewBox to 9px, with
        // 9px side padding and a 1px border: 9 + 2 * (9 + 1) = 29.
        expect(
          tester.getSize(_surface(const Key('bookmark'))),
          const Size(29, 24),
        );
        final chevron = find.byWidgetPredicate(
          (w) => w is DIcon && w.icon == DNativeIcons.filterChevron,
        );
        expect(tester.getSize(chevron), const Size(9, 10));
        for (final key in ['filter', 'bookmark']) {
          final rect = tester.getRect(find.byKey(Key(key)));
          if (platform != TargetPlatform.macOS) {
            expect(rect.width, greaterThanOrEqualTo(48));
            expect(rect.height, greaterThanOrEqualTo(48));
          }
          await tester.tapAt(rect.topLeft + const Offset(1, 1));
        }
        expect(presses, 2);
      },
    );

    testWidgets(
      '$platform preference switch keeps reference artwork and keyboard interaction',
      (tester) async {
        var checked = false;
        await _mount(
          tester,
          platform,
          StatefulBuilder(
            builder: (context, setState) => DSwitch(
              size: DSwitchSize.preference,
              value: checked,
              autofocus: true,
              semanticLabel: 'Notifications',
              onChanged: (value) => setState(() => checked = value),
            ),
          ),
        );
        final artwork = find.descendant(
          of: find.byType(DSwitch),
          matching: find.byType(AnimatedContainer),
        );
        expect(tester.getSize(artwork), const Size(38, 22));
        expect(tester.getSize(find.byType(DSwitch)), const Size(48, 48));
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(checked, isTrue);
        final thumb = find.descendant(
          of: find.byType(AnimatedAlign),
          matching: find.byType(DecoratedBox),
        );
        expect(tester.getSize(thumb), const Size.square(18));
      },
    );
  }

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    testWidgets(
      '$platform dropdown rows paint 33.5px and accept target-edge taps',
      (tester) async {
        var picked = false;
        await _mount(
          tester,
          platform,
          DDropdownMenu(
            content: DDropdownMenuContent(
              children: [
                DDropdownMenuItem(
                  onPressed: () => picked = true,
                  child: const Text('Unread'),
                ),
              ],
            ),
            child: DDropdownMenuTrigger.button(
              size: DControlSize.filter,
              label: const Text('Latest'),
            ),
          ),
        );
        await tester.tap(find.text('Latest'));
        await tester.pumpAndSettle();
        final row = find
            .ancestor(
              of: find.text('Unread'),
              matching: find.byWidgetPredicate(
                (w) => w is Container && w.decoration is BoxDecoration,
              ),
            )
            .first;
        expect(tester.getSize(row).height, 33.5);
        final action = find
            .ancestor(
              of: find.text('Unread'),
              matching: find.byType(GestureDetector),
            )
            .first;
        expect(
          tester.getSize(action).height,
          platform == TargetPlatform.macOS ? 33.5 : 48,
        );
        await tester.tapAt(tester.getRect(action).topLeft + const Offset(2, 2));
        await tester.pumpAndSettle();
        expect(picked, isTrue);
        expect(find.text('Unread'), findsNothing);
      },
    );
  }

  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets('application specimen fits 320px at $scale text scale in RTL', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark.copyWith(platform: TargetPlatform.iOS),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: const Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: SingleChildScrollView(
                  padding: EdgeInsets.all(12),
                  child: MockupControlSizesExample(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}

Finder _surface(Key key) => find.descendant(
  of: find.byKey(key),
  matching: find.byWidgetPredicate(
    (w) => w is AnimatedContainer && w.decoration is DButtonDecoration,
  ),
);

Future<void> _mount(
  WidgetTester tester,
  TargetPlatform platform,
  Widget child,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light.copyWith(platform: platform),
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}
