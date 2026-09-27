import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'inline metadata keeps activation and scales on $platform/$scale',
        (tester) async {
          var tags = 0;
          var categories = 0;
          var rows = 0;
          final tagFocus = FocusNode();
          addTearDown(tagFocus.dispose);
          final semantics = tester.ensureSemantics();
          try {
            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.light.copyWith(platform: platform),
                home: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                    body: DItem(
                      onPressed: () => rows++,
                      children: [
                        DItemContent(
                          children: [
                            Wrap(
                              spacing: 5,
                              children: [
                                DBreadcrumbLink(
                                  compact: true,
                                  onPressed: () => categories++,
                                  child: const Text('Community'),
                                ),
                                DBadge.link(
                                  size: DBadgeSize.tag,
                                  focusNode: tagFocus,
                                  semanticLabel: 'Tag: design',
                                  onPressed: () => tags++,
                                  child: const Text('design'),
                                ),
                                const DBadge(
                                  size: DBadgeSize.unread,
                                  semanticLabel: '128 unread posts',
                                  child: Text('128'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
            final tag = find.byWidgetPredicate(
              (w) => w is DBadge && w.size == DBadgeSize.tag,
            );
            final unread = find.byWidgetPredicate(
              (w) => w is DBadge && w.size == DBadgeSize.unread,
            );
            expect(
              tester.getSize(tag).height,
              (16.5 * scale).ceilToDouble() + 6,
            );
            expect(
              tester.getSize(unread).height,
              (16.5 * scale).ceilToDouble() + 2,
            );
            expect(
              tester.getSize(find.byType(DBreadcrumbLink)).height,
              (16.5 * scale).ceilToDouble(),
            );
            expect(find.bySemanticsLabel('Tag: design'), findsOneWidget);
            expect(find.bySemanticsLabel('128 unread posts'), findsOneWidget);
            await tester.tap(tag);
            tagFocus.requestFocus();
            await tester.pump();
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            // Pointer activation and independent category activation never open the row.
            await tester.tap(find.text('Community'));
            expect(tags, 2);
            expect(categories, 1);
            expect(rows, 0);
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }

  testWidgets('filled selection uses the accent without a border or stripe', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: DItem(
            selected: true,
            selectionStyle: DItemSelectionStyle.filled,
            showSelectionIndicator: false,
            onPressed: () {},
            children: const [
              DItemContent(children: [Text('Topic')]),
            ],
          ),
        ),
      ),
    );
    final surfaces = tester.widgetList<Container>(
      find.descendant(of: find.byType(DItem), matching: find.byType(Container)),
    );
    final surface = surfaces.singleWhere((w) => w.decoration is BoxDecoration);
    final decoration = surface.decoration! as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(10));
    expect((decoration.border! as Border).top.color, Colors.transparent);
    expect(surface.foregroundDecoration, isNull);
    expect(
      decoration.color,
      DTokens.of(
        tester.element(find.byType(DItem)),
      ).primary.withValues(alpha: .12),
    );
  });
}
