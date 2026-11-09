import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/foundation/icons/d_icons.dart';
import 'package:discourse_native/src/foundation/icons/d_native_icons.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_title.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('a shared row observes canonical status and bookmark changes', (
    tester,
  ) async {
    const site = 'https://example.com';
    const topic = Topic(id: 7, title: 'Topic', slug: 'topic');
    final shell = ShellController(
      instanceStore: FakeInstanceStore([instance('example.com')]),
      api: FakeDiscourseApi(
        feeds: const {
          '/latest.json': [topic],
        },
      ),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    await tester.runAsync(shell.load);
    addTearDown(shell.dispose);
    shell.store.put(site, topic);
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: TopicListRow(siteUrl: site, topic: topic, onTap: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final status = find.byKey(const ValueKey('topic-card-status-7'));
    final marks = find.descendant(of: status, matching: find.byType(DIcon));
    expect(marks, findsNothing);
    shell.store.update<Topic>(
      site,
      7,
      (row) => row.copyWith(archived: true, bookmarked: true),
    );
    await tester.pump();
    expect(tester.widgetList<DIcon>(marks).map((icon) => icon.semanticLabel), [
      'Archived',
      'Bookmarked',
    ]);
    shell.store.update<Topic>(
      site,
      7,
      (row) => row.copyWith(archived: false, bookmarked: false),
    );
    await tester.pump();
    expect(marks, findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('bookmark aligns with the timestamp at the trailing row edge', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final direction in TextDirection.values) {
      for (final width in [320.0, 900.0, 1200.0]) {
        for (final scale in [1.0, 2.0]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark,
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Directionality(
                    textDirection: direction,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: width,
                        child: TopicListRow(
                          siteUrl: 'https://example.com',
                          topic: Topic(
                            id: 1,
                            title:
                                'A closed topic with a title that can wrap ' *
                                3,
                            slug: 'closed-topic',
                            bookmarked: true,
                            bumpedAt: DateTime.now().subtract(
                              const Duration(hours: 4),
                            ),
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
          final icon = find.descendant(
            of: find.byKey(const ValueKey('topic-card-status-1')),
            matching: find.byType(DIcon),
          );
          expect(tester.widget<DIcon>(icon).icon, DIcons.bookmark);
          final time = find.byKey(const ValueKey('inbox-row-time-1'));
          final card = find.byKey(const ValueKey('topic-card-1'));
          double trailing(Finder finder) => direction == TextDirection.ltr
              ? tester.getRect(finder).right
              : tester.getRect(finder).left;
          expect(
            trailing(icon),
            closeTo(trailing(time), .01),
            reason: '$direction at width $width and text scale $scale',
          );
          expect(trailing(icon), closeTo(trailing(card), .01));
          expect(
            tester.getSize(find.byType(TopicTitle)).width,
            lessThanOrEqualTo(760),
          );
          expect(tester.takeException(), isNull);
        }
      }
    }
  });

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
                            topic: Topic(
                              id: 1,
                              title:
                                  'Fix broken workflow broke on Ask that errors at data explorer node',
                              slug: 'workflow',
                              pinned: true,
                              archived: true,
                              visible: false,
                              deletedAt: DateTime.utc(2026),
                              bookmarked: true,
                              muted: true,
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
            final icons = tester.widgetList<DIcon>(icon).toList();
            expect(icons.map((icon) => icon.icon), [
              DIcons.thumbtack,
              DNativeIcons.boxArchive,
              DNativeIcons.eyeSlash,
              DIcons.trashCan,
              DIcons.bookmark,
              DNativeIcons.bellSlash,
            ]);
            expect(icons.map((icon) => icon.semanticLabel), [
              'Pinned',
              'Archived',
              'Unlisted',
              'Deleted',
              'Bookmarked',
              'Muted',
            ]);
            expect(
              tester
                  .widgetList<DTooltip>(
                    find.descendant(
                      of: status,
                      matching: find.byType(DTooltip),
                    ),
                  )
                  .map((tooltip) => tooltip.message),
              [
                'Pinned',
                'Archived',
                'Unlisted',
                'Deleted',
                'Bookmarked',
                'Muted',
              ],
            );
            for (var i = 0; i < icons.length; i++) {
              final mark = icon.at(i);
              expect(tester.getCenter(mark).dy, closeTo(center, 2));
              expect(tester.getSize(mark), const Size(11, 11));
              if (i > 0) {
                expect(
                  tester.getRect(mark).left -
                      tester.getRect(icon.at(i - 1)).right,
                  6,
                );
              }
            }
            expect(
              tester.getTopLeft(status).dx,
              greaterThan(tester.getTopRight(title).dx),
            );
            expect(find.text('Pinned'), findsNothing);
            expect(tester.takeException(), isNull);
          }
        }
      }
    },
  );
}
