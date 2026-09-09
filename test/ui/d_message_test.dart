import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
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

  DMessage message({
    DMessageAlign align = DMessageAlign.start,
    bool footer = false,
  }) => DMessage(
    key: const ValueKey('message'),
    align: align,
    children: [
      const DMessageAvatar(
        child: SizedBox.square(key: ValueKey('avatar'), dimension: 32),
      ),
      DMessageContent(
        children: [
          const SizedBox(key: ValueKey('surface'), width: 120, height: 40),
          if (footer) const DMessageFooter(children: [Text('Delivered')]),
        ],
      ),
    ],
  );

  testWidgets('matches row alignment, 8px gap, and footer avatar anchoring', (
    tester,
  ) async {
    await tester.pumpWidget(host(message(footer: true)));

    var avatar = tester.getRect(find.byKey(const ValueKey('avatar')));
    var surface = tester.getRect(find.byKey(const ValueKey('surface')));
    expect(avatar.left, 0);
    expect(surface.left - avatar.right, 8);
    expect(
      tester.getRect(find.byKey(const ValueKey('message'))).bottom -
          avatar.bottom,
      32,
    );

    await tester.pumpWidget(
      host(message(align: DMessageAlign.end, footer: true)),
    );
    avatar = tester.getRect(find.byKey(const ValueKey('avatar')));
    surface = tester.getRect(find.byKey(const ValueKey('surface')));
    expect(avatar.right, 400);
    expect(avatar.left - surface.right, 8);
    expect(
      tester.getRect(find.byKey(const ValueKey('message'))).bottom -
          avatar.bottom,
      32,
    );
  });

  testWidgets('logical alignment reverses under RTL', (tester) async {
    await tester.pumpWidget(host(message(), direction: TextDirection.rtl));
    expect(tester.getRect(find.byKey(const ValueKey('avatar'))).right, 400);

    await tester.pumpWidget(
      host(message(align: DMessageAlign.end), direction: TextDirection.rtl),
    );
    expect(tester.getRect(find.byKey(const ValueKey('avatar'))).left, 0);
  });

  testWidgets('preserves direct-child order and intrinsic auxiliary width', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const DMessage(
          children: [
            DMessageAvatar(),
            DMessageContent(children: [SizedBox(height: 20)]),
            SizedBox(key: ValueKey('auxiliary'), width: 10, height: 10),
          ],
        ),
      ),
    );

    final auxiliary = tester.getRect(find.byKey(const ValueKey('auxiliary')));
    expect(auxiliary.width, 10);
    expect(auxiliary.right, 400);
  });

  testWidgets('groups consecutive rows with the reference 8px gap', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const DMessageGroup(
          children: [
            SizedBox(key: ValueKey('first'), height: 24),
            SizedBox(key: ValueKey('second'), height: 24),
          ],
        ),
      ),
    );

    final first = tester.getRect(find.byKey(const ValueKey('first')));
    final second = tester.getRect(find.byKey(const ValueKey('second')));
    expect(second.top - first.bottom, 8);
  });

  testWidgets('metadata follows message side and ghost removes its inset', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const Column(
          children: [
            DMessage(
              align: DMessageAlign.end,
              children: [
                DMessageContent(
                  children: [
                    DMessageHeader(children: [Text('Olivia')]),
                    SizedBox(width: 80, height: 10),
                    DMessageFooter(children: [Text('Read')]),
                  ],
                ),
              ],
            ),
            DMessage(
              children: [
                DMessageContent(
                  children: [
                    DMessageHeader(
                      children: [
                        SizedBox(key: ValueKey('flush'), width: 10, height: 10),
                      ],
                    ),
                    DBubble(
                      variant: DBubbleVariant.ghost,
                      children: [DBubbleContent(child: Text('Ghost'))],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final header = tester.getRect(find.text('Olivia'));
    final footer = tester.getRect(find.text('Read'));
    expect(header.left, 12);
    expect(footer.right, 388);
    expect(tester.getRect(find.byKey(const ValueKey('flush'))).left, 0);
  });

  testWidgets('header default keeps the reference zero child gap', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const DMessage(
          children: [
            DMessageContent(
              children: [
                DMessageHeader(
                  children: [
                    SizedBox(
                      key: ValueKey('header-first'),
                      width: 20,
                      height: 16,
                    ),
                    SizedBox(
                      key: ValueKey('header-second'),
                      width: 20,
                      height: 16,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final first = tester.getRect(find.byKey(const ValueKey('header-first')));
    final second = tester.getRect(find.byKey(const ValueKey('header-second')));
    expect(second.left, first.right);
  });

  testWidgets('status announcements do not merge independent action labels', (
    tester,
  ) async {
    var retried = false;
    await tester.pumpWidget(
      host(
        DMessage(
          align: DMessageAlign.end,
          children: [
            DMessageContent(
              children: [
                const DBubble(
                  align: DBubbleAlign.end,
                  children: [DBubbleContent(child: Text('Taking a look'))],
                ),
                DMessageFooter(
                  spacing: 8,
                  children: [
                    const DMessageStatus(state: DMessageDeliveryState.failed),
                    DButton.iconOnly(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Retry',
                      onPressed: () => retried = true,
                      variant: DButtonVariant.ghost,
                      size: DButtonSize.extraSmall,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final status = tester.getSemantics(find.byType(DMessageStatus));
    expect(status.label, 'Failed to send');
    expect(status.flagsCollection.isLiveRegion, isTrue);
    final retry = find.bySemanticsLabel('Retry');
    expect(retry, findsOneWidget);
    await tester.tap(retry);
    expect(retried, isTrue);
  });

  testWidgets('narrow 200% RTL rich content wraps without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const SingleChildScrollView(
          child: DMessage(
            align: DMessageAlign.end,
            children: [
              DMessageAvatar(),
              DMessageContent(
                children: [
                  DMessageHeader(
                    children: [Text('A sender with a long display name')],
                  ),
                  DBubble(
                    align: DBubbleAlign.end,
                    children: [
                      DBubbleContent(
                        child: Text(
                          'A long localized message that must wrap safely.',
                        ),
                      ),
                    ],
                  ),
                  DMessageFooter(
                    children: [Text('Delivered yesterday afternoon')],
                  ),
                ],
              ),
            ],
          ),
        ),
        width: 220,
        scale: 2,
        direction: TextDirection.rtl,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('localized message'), findsOneWidget);
  });
}
