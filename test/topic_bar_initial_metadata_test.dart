import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart' show PluginManifest;
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/post_voting/post_voting_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' show pumpMobileShellFixture;
import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _title = 'A resumed topic with its taxonomy';
final _bar = find.byKey(const ValueKey('mobile-page-title'));
final _metadata = find.descendant(
  of: _bar,
  matching: find.byKey(const ValueKey('topic-bar-metadata')),
);
final _barTitle = find.descendant(of: _bar, matching: find.text(_title));
const _platforms = TargetPlatformVariant({
  TargetPlatform.iOS,
  TargetPlatform.android,
});
final _posts = [
  for (var number = 1; number <= 30; number++)
    Post(
      id: number,
      postNumber: number,
      username: 'reader',
      cooked: '<p>A discussion post with room to resume reading.</p>',
    ),
];

void main() {
  for (final resolveReader in [false, true]) {
    for (final privateMessage in [false, true]) {
      testWidgets(
        'cached taxonomy accompanies the first bar title (reader: $resolveReader, private: $privateMessage)',
        (tester) async {
          final gate = Completer<void>();
          addTearDown(() {
            if (!gate.isCompleted) gate.complete();
          });
          final row = Topic(
            id: 7,
            title: _title,
            slug: 'shared',
            categoryId: 1,
            privateMessage: privateMessage,
            lastReadPostNumber: 11,
            highestPostNumber: 30,
            tags: const [TopicTag(id: 1, name: 'cached-tag')],
          );
          final shell = await pumpMobileShellFixture(
            tester,
            topicGate: gate,
            topics: [row],
            sidebarCategories: const [
              TopicCategory(id: 1, name: 'Support', color: '0088cc'),
            ],
            topic: topicPayload(
              id: 7,
              title: _title,
              categoryId: 1,
              privateMessage: privateMessage,
              tags: const [TopicTag(id: 2, name: 'current-tag')],
              posts: _posts,
            ),
            pluginManifest: PluginManifest([
              ...bundledWidgetTestManifest.modules,
              if (resolveReader) postVotingModule,
            ]),
          );
          shell.openTopic(row);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
          expect(_bar.hitTestable(), findsOneWidget);
          expect(_metadata, findsOneWidget);
          final before = tester.widget<Text>(_metadata).textSpan!.toPlainText();
          expect(before, contains('#cached-tag'));
          expect(before.contains('Support'), !privateMessage);
          final titleTop = tester.getTopLeft(_barTitle).dy;
          gate.complete();
          await shell.loadTopic(7, 'shared');
          for (var frame = 0; frame < 30; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            expect(
              tester.getTopLeft(_barTitle).dy,
              closeTo(titleTop, .01),
              reason: 'resolution frame $frame',
            );
            expect(_metadata, findsOneWidget);
          }
          final loaded = tester.widget<Text>(_metadata).textSpan!.toPlainText();
          expect(loaded, contains('#current-tag'));
          expect(loaded, isNot(contains('#cached-tag')));
          expect(tester.takeException(), isNull);
        },
        variant: _platforms,
      );
    }
  }

  for (final sparsePreview in [false, true]) {
    testWidgets(
      'uncached taxonomy and title appear together (sparse preview: $sparsePreview)',
      (tester) async {
        final gate = Completer<void>();
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
        });
        final shell = await pumpMobileShellFixture(
          tester,
          topics: [
            if (sparsePreview)
              const Topic(id: 7, title: _title, slug: 'shared'),
          ],
          topicGate: gate,
          sidebarCategories: const [
            TopicCategory(id: 1, name: 'Support', color: '0088cc'),
          ],
          topic: topicPayload(
            id: 7,
            title: _title,
            categoryId: 1,
            tags: const [TopicTag(id: 1, name: 'how-to')],
            posts: _posts,
          ),
        );
        shell.pushContent(
          ContentRoute.topic(
            topicId: 7,
            slug: 'shared',
            title: _title,
            postNumber: 12,
          ),
        );
        for (var frame = 0; frame < 4; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(
            _bar.hitTestable(),
            findsNothing,
            reason: 'The unresolved title must not appear alone.',
          );
        }
        gate.complete();
        await shell.loadTopic(7, 'shared');
        var shown = false;
        double? top;
        for (var frame = 0; frame < 30; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          if (_bar.hitTestable().evaluate().isEmpty) continue;
          shown = true;
          expect(_metadata, findsOneWidget);
          final words = tester.widget<Text>(_metadata).textSpan!.toPlainText();
          expect(words, contains('Support'));
          expect(words, contains('#how-to'));
          top ??= tester.getTopLeft(_barTitle).dy;
          expect(tester.getTopLeft(_barTitle).dy, closeTo(top, .01));
        }
        expect(shown, isTrue);
        expect(tester.takeException(), isNull);
      },
      variant: _platforms,
    );
  }
}
