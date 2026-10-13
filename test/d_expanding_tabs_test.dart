import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:discourse_native/src/theme/d_native_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  var selected = 'forum';
  var activations = 0;
  Finder tab(String value) => find.byKey(ValueKey(value));
  Future<void> mount(
    WidgetTester tester, {
    double width = 226,
    double scale = 1,
    bool rtl = false,
    bool reducedMotion = false,
    Widget? badge,
  }) async {
    selected = 'forum';
    activations = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reducedMotion,
          ),
          child: Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: StatefulBuilder(
                  builder: (context, setState) => DTabs<String>.controlled(
                    value: selected,
                    onChanged: (value) => setState(() {
                      selected = value!;
                      activations++;
                    }),
                    children: [
                      DTabList<String>(
                        expandSelected: true,
                        children: [
                          const DTabTrigger(
                            key: ValueKey('forum'),
                            value: 'forum',
                            semanticLabel: 'Forum',
                            selectedLabelOnly: true,
                            icon: DIcon(DIcons.layerGroup),
                            child: Text('Forum'),
                          ),
                          DTabTrigger(
                            key: const ValueKey('chat'),
                            value: 'chat',
                            semanticLabel: 'Chat',
                            selectedLabelOnly: true,
                            icon: const DIcon(DIcons.comment),
                            trailing: badge,
                            child: const Text('Chat'),
                          ),
                          const DTabTrigger(
                            key: ValueKey('shortcuts'),
                            value: 'shortcuts',
                            semanticLabel: 'Shortcuts',
                            selectedLabelOnly: true,
                            icon: DIcon(DNativeIcons.bolt),
                            child: Text('Shortcuts'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('capsules fill the track with 38px glyph choices and 3px gaps', (
    tester,
  ) async {
    await mount(tester);
    expect(tester.getSize(tab('forum')).width, 138);
    expect(tester.getSize(tab('chat')).width, 38);
    expect(tester.getSize(tab('shortcuts')).width, 38);
    final forum = tester.getRect(tab('forum'));
    final chat = tester.getRect(tab('chat'));
    expect(chat.left - forum.right, 3);
    expect(forum.height, closeTo(28.75, .01));
    final surface = tester.widget<AnimatedContainer>(
      find.descendant(
        of: tab('forum'),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect(
      (surface.decoration! as BoxDecoration).borderRadius,
      BorderRadius.circular(DRadius.pill),
    );
    expect(
      DefaultTextStyle.of(tester.element(find.text('Forum'))).style.fontSize,
      12.5,
    );
    expect(
      DefaultTextStyle.of(tester.element(find.text('Forum'))).style.fontWeight,
      FontWeight.w600,
    );
    await tester.tapAt(Offset(forum.right + 1.5, forum.center.dy));
    await tester.pumpAndSettle();
    expect(activations, 0);
  });

  testWidgets('measures actual dots and counts without fixed badge space', (
    tester,
  ) async {
    await mount(tester, badge: const DNotificationDot());
    expect(tester.getSize(tab('chat')).width, closeTo(42.5, .01));
    await mount(
      tester,
      width: 300,
      badge: const Text(
        '12345',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
    expect(tester.getSize(tab('chat')).width, greaterThan(42.5));
    expect(tester.getRect(tab('shortcuts')).right, closeTo(297, .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'label and flex expansion animate for 300ms without growing the strip',
    (tester) async {
      await mount(tester);
      await tester.tap(tab('chat'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final mid = tester.getSize(tab('chat')).width;
      expect(mid, greaterThan(38));
      expect(mid, lessThan(138));
      expect(tester.getRect(tab('shortcuts')).right, closeTo(223, .01));
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.getSize(tab('forum')).width, greaterThan(38));
      await tester.pumpAndSettle();
      expect(tester.getSize(tab('chat')).width, 138);
      expect(tester.getSize(tab('forum')).width, 38);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduced motion changes immediately and keyboard follows RTL', (
    tester,
  ) async {
    await mount(tester, rtl: true, reducedMotion: true);
    await tester.tap(tab('forum'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selected, 'chat');
    expect(tester.getSize(tab('chat')).width, 138);
    expect(
      tester.getRect(tab('forum')).left,
      greaterThan(tester.getRect(tab('chat')).left),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text scrolls and hover and press retain visible targets', (
    tester,
  ) async {
    await mount(tester, width: 130, scale: 2);
    await tester.ensureVisible(tab('shortcuts'));
    await tester.pumpAndSettle();
    await tester.tap(tab('shortcuts'));
    await tester.pumpAndSettle();
    expect(selected, 'shortcuts');
    expect(tester.getSize(tab('shortcuts')).height, closeTo(47.5, .01));
    expect(tester.takeException(), isNull);
    await mount(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 500));
    await mouse.moveTo(tester.getCenter(tab('chat')));
    await tester.pumpAndSettle();
    final surface = tester.widget<AnimatedContainer>(
      find.descendant(
        of: tab('chat'),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect((surface.decoration! as BoxDecoration).color!.a, greaterThan(0));
    await mouse.down(tester.getCenter(tab('chat')));
    await tester.pump(const Duration(milliseconds: 80));
    final press = tester.widget<AnimatedScale>(
      find.descendant(of: tab('chat'), matching: find.byType(AnimatedScale)),
    );
    expect(press.scale, .92);
    await mouse.up();
    await mouse.removePointer();
    await tester.pumpAndSettle();
    expect(selected, 'chat');
  });
}
