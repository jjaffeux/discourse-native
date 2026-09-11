import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_title.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('status icons align to the first title line at every text size', (
    tester,
  ) async {
    for (final scale in [1.0, 2.0]) {
      for (final width in [320.0, 900.0]) {
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
        final center = paragraph.localToGlobal(firstLine.toRect().center).dy;
        for (final icon in [DIcons.lock, DIcons.thumbtack, DIcons.bookmark]) {
          final finder = find.byWidgetPredicate(
            (widget) => widget is DIcon && widget.icon == icon,
          );
          expect(
            tester.getCenter(finder).dy,
            closeTo(center, 2),
            reason: 'width $width, scale $scale',
          );
        }
        expect(tester.takeException(), isNull);
      }
    }
  });
}
