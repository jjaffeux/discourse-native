import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_title.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'trailing status stays beside the first title line at every text size',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final scale in [1.0, 2.0]) {
        for (final width in [320.0, 900.0]) {
          for (final titleStyle in [
            null,
            const TextStyle(fontSize: 22, height: 1.6),
          ]) {
            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.dark,
                home: Scaffold(
                  body: MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: SingleChildScrollView(
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: width,
                          child: TopicListRow(
                            siteUrl: 'https://example.com',
                            titleStyle: titleStyle,
                            topic: const Topic(
                              id: 1,
                              title:
                                  'Fix broken workflow broke on Ask that errors at data explorer node',
                              slug: 'workflow',
                              closed: true,
                              pinned: true,
                              bookmarked: true,
                              unreadPosts: 3,
                            ),
                            onTap: () {},
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final title = find.byType(TopicTitle);
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(of: title, matching: find.byType(RichText)).first,
            );
            final firstLine = paragraph
                .getBoxesForSelection(
                  const TextSelection(baseOffset: 0, extentOffset: 1),
                )
                .first;
            final center = paragraph
                .localToGlobal(firstLine.toRect().center)
                .dy;
            final status = find.byKey(const ValueKey('topic-card-status-1'));
            final icon = find.descendant(
              of: status,
              matching: find.byType(DIcon),
            );
            expect(icon, findsOneWidget);
            expect(tester.widget<DIcon>(icon).icon, DIcons.thumbtack);
            expect(
              tester.widget<DIcon>(icon).semanticLabel,
              'Pinned, Closed, Bookmarked',
            );
            expect(
              tester
                  .widget<DTooltip>(
                    find.descendant(
                      of: status,
                      matching: find.byType(DTooltip),
                    ),
                  )
                  .message,
              'Pinned, Closed, Bookmarked',
            );
            expect(
              tester.getCenter(icon).dy,
              closeTo(center, 2),
              reason:
                  'text scale $scale at width $width with style $titleStyle',
            );
            expect(
              tester.getTopLeft(status).dx,
              greaterThan(tester.getTopRight(title).dx),
            );
            expect(tester.getSize(icon).height, 11);
            expect(tester.getSize(icon).width, greaterThan(0));
            expect(find.text('Pinned'), findsNothing);
            expect(tester.takeException(), isNull);
          }
        }
      }
    },
  );
}
