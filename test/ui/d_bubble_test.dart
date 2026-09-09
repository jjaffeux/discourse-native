import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(
    Widget child, {
    TextDirection direction = TextDirection.ltr,
    TargetPlatform platform = TargetPlatform.macOS,
    double width = 400,
    double scale = 1,
    ThemeData? theme,
  }) => MaterialApp(
    theme:
        theme ??
        ThemeData(
          platform: platform,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
          extensions: const [
            DTokens(
              colors: ColorScheme.light(
                primary: Color(0xff222222),
                onPrimary: Colors.white,
                error: Color(0xffba1a1a),
              ),
              background: Colors.white,
              surface: Color(0xfffafafa),
              muted: Color(0xffeeeeee),
              border: Color(0xffd6d6d6),
              hover: Color(0xffe5e5e5),
              selected: Color(0xffdddddd),
              selectedForeground: Color(0xff111111),
              radius: 10,
            ),
          ],
        ),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    ),
  );

  testWidgets('matches content geometry, width, alignment and group spacing', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DBubble(
              children: [
                DBubbleContent(
                  key: ValueKey('start'),
                  child: Text('A long bubble that uses the width available'),
                ),
              ],
            ),
            DBubbleGroup(
              children: [
                DBubble(
                  align: DBubbleAlign.end,
                  children: [
                    DBubbleContent(
                      key: ValueKey('first'),
                      child: Text('First'),
                    ),
                  ],
                ),
                DBubble(
                  align: DBubbleAlign.end,
                  children: [
                    DBubbleContent(
                      key: ValueKey('second'),
                      child: Text('Second'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final start = tester.getRect(find.byKey(const ValueKey('start')));
    final first = tester.getRect(find.byKey(const ValueKey('first')));
    final second = tester.getRect(find.byKey(const ValueKey('second')));
    expect(start.width, lessThanOrEqualTo(320));
    expect(start.left, 0);
    expect(first.right, 400);
    expect(second.right, 400);
    expect(second.top - first.bottom, 8);
    expect(start.height, greaterThanOrEqualTo(39));
  });

  testWidgets('all variants render and ghost can use the full row', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final variant in DBubbleVariant.values)
              DBubble(
                variant: variant,
                children: [
                  DBubbleContent(
                    key: ValueKey(variant),
                    child: const SizedBox(width: 400, child: Text('Variant')),
                  ),
                ],
              ),
          ],
        ),
      ),
    );

    for (final variant in DBubbleVariant.values) {
      expect(find.byKey(ValueKey(variant)), findsOneWidget);
    }
    expect(
      tester.getSize(find.byKey(const ValueKey(DBubbleVariant.primary))).width,
      320,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey(DBubbleVariant.ghost))).width,
      400,
    );
  });

  testWidgets(
    'reaction positions are logical and grouped semantics are clear',
    (tester) async {
      Future<void> pump(TextDirection direction) => tester.pumpWidget(
        host(
          const DBubble(
            children: [
              DBubbleContent(key: ValueKey('content'), child: Text('A bubble')),
              DBubbleReactions(
                key: ValueKey('reactions'),
                align: DBubbleAlign.start,
                semanticLabel: 'Reactions: thumbs up and fire',
                children: [Text('👍'), Text('🔥')],
              ),
            ],
          ),
          direction: direction,
        ),
      );

      await pump(TextDirection.ltr);
      final ltrContent = tester.getRect(find.byKey(const ValueKey('content')));
      final ltrReaction = tester.getRect(
        find.byKey(const ValueKey('reactions')),
      );
      expect(ltrReaction.left, closeTo(ltrContent.left + 12, 0.01));
      expect(ltrReaction.center.dy, greaterThan(ltrContent.bottom));
      expect(
        tester.getSemantics(find.byKey(const ValueKey('reactions'))),
        matchesSemantics(
          isImage: true,
          label: 'Reactions: thumbs up and fire',
          textDirection: TextDirection.ltr,
        ),
      );

      await pump(TextDirection.rtl);
      final rtlContent = tester.getRect(find.byKey(const ValueKey('content')));
      final rtlReaction = tester.getRect(
        find.byKey(const ValueKey('reactions')),
      );
      expect(rtlReaction.right, closeTo(rtlContent.right - 12, 0.01));
    },
  );

  testWidgets('interactive content supports pointer and keyboard roles', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      host(
        DBubble(
          variant: DBubbleVariant.muted,
          children: [
            DBubbleContent(
              key: const ValueKey('action'),
              action: DBubbleContentAction.button,
              onPressed: () => presses++,
              semanticLabel: 'Reply with password help',
              child: const Text('I forgot my password'),
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('action')));
    await tester.pump();
    expect(presses, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(presses, 2);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('action'))),
      matchesSemantics(
        hasEnabledState: true,
        isEnabled: true,
        isButton: true,
        hasSelectedState: true,
        isFocusable: true,
        isFocused: true,
        hasFocusAction: true,
        hasTapAction: true,
        label: 'Reply with password help',
        textDirection: TextDirection.ltr,
      ),
    );
  });

  testWidgets('link uses Enter while disabled and busy state stay truthful', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      host(
        Column(
          children: [
            DBubble(
              children: [
                DBubbleContent(
                  key: const ValueKey('link'),
                  action: DBubbleContentAction.link,
                  onPressed: () => presses++,
                  selected: true,
                  semanticLabel: 'Open help center',
                  child: const Text('Help center'),
                ),
              ],
            ),
            const DBubble(
              children: [
                DBubbleContent(
                  key: ValueKey('busy'),
                  action: DBubbleContentAction.button,
                  onPressed: _noop,
                  busy: true,
                  busyLabel: 'Sending reply',
                  semanticLabel: 'Send reply',
                  child: Text('Send'),
                ),
              ],
            ),
            const DBubble(
              variant: DBubbleVariant.destructive,
              children: [
                DBubbleContent(
                  key: ValueKey('error'),
                  action: DBubbleContentAction.button,
                  disabled: true,
                  invalid: true,
                  errorLabel: 'Network unavailable',
                  semanticLabel: 'Retry failed message',
                  child: Text('Message failed. Retry unavailable.'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('link')));
    expect(presses, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(presses, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(presses, 2);
    expect(find.byType(DSpinner), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('busy'))),
      matchesSemantics(
        hasEnabledState: true,
        isButton: true,
        hasSelectedState: true,
        isFocusable: true,
        isLiveRegion: true,
        hasFocusAction: true,
        label: 'Send reply',
        value: 'Sending reply',
        textDirection: TextDirection.ltr,
      ),
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('error'))),
      matchesSemantics(
        hasEnabledState: true,
        isButton: true,
        hasSelectedState: true,
        isFocusable: true,
        isLiveRegion: true,
        hasFocusAction: true,
        label: 'Retry failed message',
        value: 'Network unavailable',
        textDirection: TextDirection.ltr,
      ),
    );
  });

  testWidgets('touch target, large text and narrow RTL layouts do not overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const SingleChildScrollView(
          child: DBubble(
            align: DBubbleAlign.end,
            children: [
              DBubbleContent(
                key: ValueKey('touch-action'),
                action: DBubbleContentAction.button,
                onPressed: _noop,
                child: Text(
                  'A long actionable response that wraps without losing its accessible target.',
                ),
              ),
            ],
          ),
        ),
        direction: TextDirection.rtl,
        platform: TargetPlatform.iOS,
        width: 240,
        scale: 2,
      ),
    );

    final size = tester.getSize(find.byKey(const ValueKey('touch-action')));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(size.width, lessThanOrEqualTo(192));
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}
