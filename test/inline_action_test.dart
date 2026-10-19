import 'dart:ui' show SemanticsAction;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final link in [false, true]) {
    testWidgets(
      'Native inline activation owns bounds, semantics, hover, and keys ($link)',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final focus = FocusNode();
        try {
          var activations = 0;
          final hover = <bool>[];
          const artwork = Key('inline-artwork');
          const target = Key('inline-target');
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: DefaultTextStyle.merge(
                    style: const TextStyle(fontSize: 19, height: 1.2),
                    child: DItem(
                      key: target,
                      size: DItemSize.artwork,
                      fitContent: true,
                      link: link,
                      highlightOnInteraction: false,
                      focusNode: focus,
                      onPressed: () => activations++,
                      onHoverChanged: hover.add,
                      semanticLabel: 'Open support',
                      children: const [
                        ExcludeSemantics(child: Text('Support', key: artwork)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(
            tester.getRect(find.byKey(target)),
            tester.getRect(find.byKey(artwork)),
          );
          expect(
            DefaultTextStyle.of(
              tester.element(find.byKey(artwork)),
            ).style.fontSize,
            19,
          );
          final announcement = tester
              .getSemantics(find.bySemanticsLabel('Open support'))
              .getSemanticsData();
          expect(announcement.flagsCollection.isButton, !link);
          expect(announcement.flagsCollection.isLink, link);
          expect(announcement.hasAction(SemanticsAction.tap), isTrue);
          expect(find.bySemanticsLabel('Support'), findsNothing);

          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: const Offset(700, 500));
          await mouse.moveTo(tester.getCenter(find.byKey(target)));
          await tester.pump();
          expect(hover, [true]);
          await mouse.moveTo(const Offset(700, 500));
          await tester.pump();
          expect(hover, [true, false]);
          await mouse.removePointer();

          focus.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          expect(activations, 1);
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          expect(activations, link ? 1 : 2);
          await tester.tapAt(
            tester.getRect(find.byKey(target)).bottomRight + const Offset(1, 1),
          );
          expect(activations, link ? 1 : 2);
        } finally {
          semantics.dispose();
          focus.dispose();
        }
      },
    );
  }
}
