import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/relative_time.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shell_test_harness.dart';
import 'support/tab_switch_fixture.dart';

const _site = 'https://tabs.example';

String _title(int id) => 'Discussion $id about fast navigation and reading';

// The rows `TopicListItemSerializer` answers with for /latest.json. A row
// without `bumped_at` draws no time label.
List<Topic> _latest() => TopicList.fromJson({
  'users': const [
    {
      'id': 1,
      'username': 'alice',
      'name': 'Alice',
      'avatar_template': '/user_avatar/tabs.example/alice/{size}/1_2.png',
    },
    {
      'id': 2,
      'username': 'bob',
      'name': 'Bob',
      'avatar_template': '/user_avatar/tabs.example/bob/{size}/2_2.png',
    },
  ],
  'topic_list': {
    'can_create_topic': true,
    'per_page': 30,
    'topics': [
      for (var id = 1; id <= 40; id++)
        {
          'id': id,
          'title': _title(id),
          'fancy_title': _title(id),
          'slug': 'discussion-$id',
          'posts_count': 60,
          'reply_count': 59,
          'highest_post_number': 60,
          'image_url': null,
          'created_at': '2024-01-01T10:00:00.000Z',
          'last_posted_at': '2024-02-01T10:00:00.000Z',
          'bumped': true,
          'bumped_at': '2024-02-01T10:00:00.000Z',
          'archetype': 'regular',
          'unseen': false,
          'last_read_post_number': 60,
          'unread': 0,
          'new_posts': 0,
          'unread_posts': 0,
          'pinned': false,
          'unpinned': null,
          'excerpt': 'A discussion with formatted replies.',
          'visible': true,
          'closed': id.isEven,
          'archived': false,
          'notification_level': 1,
          'bookmarked': false,
          'liked': false,
          'tags': const <String>[],
          'views': 1200,
          'like_count': 40,
          'has_summary': false,
          'last_poster_username': 'bob',
          'category_id': null,
          'pinned_globally': false,
          'featured_link': null,
          'posters': [
            {
              'extras': null,
              'description': 'Original Poster',
              'user_id': 1,
              'primary_group_id': null,
            },
            {
              'extras': 'latest',
              'description': 'Most Recent Poster',
              'user_id': 2,
              'primary_group_id': null,
            },
          ],
        },
    ],
  },
}, _site).topics;

void main() {
  setUp(() {
    const channel = MethodChannel('org.discourse.native/notification_opens');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  });

  testWidgets(
    'opening and closing a topic leaves the retained list labels alone',
    (tester) async {
      final shell = await pumpTabSwitchFixture(tester, feed: _latest());
      shell.closeTab('reader-a');
      shell.closeTab('list-b');
      shell.selectTab('list-a');
      await tester.pumpAndSettle();
      final source = tester.state(find.byType(TopicListView));
      for (final type in [RelativeTimeBuilder, DTooltip, DPopover]) {
        expect(
          find.descendant(
            of: find.byType(TopicListView),
            matching: find.byType(type),
          ),
          findsWidgets,
          reason: 'the rows must draw what this test counts',
        );
      }

      // Reads without subscribing: `valuesOf` here would make the list itself
      // rebuild on every hide and reveal this test counts.
      bool sourceTicking() =>
          TickerMode.getValuesNotifier(source.context).value.enabled;

      var phase = '';
      final built = Expando<bool>();
      final counts = <String, int>{};
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        // `builtOnce` is only maintained while debugPrintRebuildDirtyWidgets
        // is on.
        final rebuilt = built[element] ?? false;
        built[element] = true;
        if (phase.isEmpty) return;
        counts.update('${phase}_elements', (n) => n + 1, ifAbsent: () => 1);
        final tracked = switch (element.widget) {
          RelativeTimeBuilder() || DTooltip() || DPopover() => true,
          _ => false,
        };
        if (rebuilt && element.dirty && tracked) {
          counts.update(
            '${phase}_invalidated',
            (n) => n + 1,
            ifAbsent: () => 1,
          );
        }
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);

      // The first round mounts the reader's shared chrome; the second is the
      // cost of every later open and close.
      for (var round = 0; round < 2; round++) {
        phase = round == 1 ? 'open' : '';
        await tester.tap(topicListTitle(_title(1)));
        await tester.pumpAndSettle();
        expect(sourceTicking(), isFalse);
        final reader = find.byWidgetPredicate(
          (widget) => widget is TopicView && widget.route?.topicId == 1,
        );
        expect(reader, findsOneWidget);
        phase = round == 1 ? 'close' : '';
        await tester.tap(
          find.descendant(
            of: reader,
            matching: find.byKey(const ValueKey('topic-close-reader')),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(TopicListView)), same(source));
        expect(sourceTicking(), isTrue);
      }
      phase = '';
      expect(tester.takeException(), isNull);

      for (final metric in [
        'open_elements',
        'open_invalidated',
        'close_elements',
        'close_invalidated',
      ]) {
        // ignore: avoid_print
        print('PERF_PROOF ticker-mode $metric=${counts[metric] ?? 0}');
      }
      expect(counts['open_invalidated'] ?? 0, 0);
      expect(counts['close_invalidated'] ?? 0, 0);
      expect(counts['open_elements'], lessThanOrEqualTo(3288));
      expect(counts['close_elements'], lessThanOrEqualTo(1835));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
