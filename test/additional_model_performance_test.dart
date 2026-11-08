import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_theme_library.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/models/post_checklist.dart';
import 'package:discourse_native/src/models/topic_tracking_message_filter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

import '../tool/additional_model_performance_workloads.dart';

const _baseline = bool.fromEnvironment('PERF_BASELINE');

void main() {
  test(
    'checklist transformations keep markup, quote exclusions and ownership',
    () {
      const source =
          '<p><span class="chcklst-box fa-square-o" '
          'data-chk-src="0:0" aria-checked="false"></span>A &amp; B</p>'
          '<span class="chcklst-box checked permanent"></span>Locked'
          '<aside class="quote" data-post="2">'
          '<span class="chcklst-box checked"></span>Quote</aside>';
      final document = PostChecklistDocument(source);
      final before = document.annotatedHtml;
      final fingerprint = document.fingerprint;
      final updated = document.withStates({
        0: true,
        1: false,
        2: false,
        -1: true,
      });
      expect(
        updated,
        '<p><span class="chcklst-box fa-square-check-o checked" '
        'data-chk-src="0:0" aria-checked="true"></span>A &amp; B</p>'
        '<span class="chcklst-box checked permanent"></span>Locked'
        '<aside class="quote" data-post="2">'
        '<span class="chcklst-box checked"></span>Quote</aside>',
      );
      expect(PostChecklistDocument(updated).fingerprint, fingerprint);
      expect(document.annotatedHtml, before);
      expect(document.targets.first.checked, isFalse);
      expect(document.withStates(const {}), source);
      expect(document.fingerprint, fingerprint);
    },
  );

  test('checklist copies preserve parser-normalized malformed markup', () {
    for (final source in [
      '<table><tr><td><span class="chcklst-box"></span>Cell</table>',
      '<svg><foreignObject><span class="chcklst-box"></span></foreignObject></svg>',
      '<template><span class="chcklst-box checked"></span></template>',
      '<p><span class="chcklst-box"></span>First<p>Second &amp; third',
      '<aside class="quote" data-topic="1"><div><span class="chcklst-box">'
          '</span></div></aside><span class="chcklst-box"></span>',
    ]) {
      final document = PostChecklistDocument(source);
      final reparsed = PostChecklistDocument(
        html.parseFragment(source).outerHtml,
      );
      expect(document.withStates({0: true}), reparsed.withStates({0: true}));
      expect(document.fingerprint, reparsed.fingerprint);
    }
  });

  test(
    'theme decode retains first valid duplicate and accepts repaired rows',
    () {
      final raw = forumThemePresets.first.toJson();
      final preferences = ForumThemePreferences.fromJson({
        'version': 2,
        'source': 'custom',
        'custom': 'custom-repaired',
        'customThemes': [
          {'id': 'custom-duplicate', ...raw, 'name': 'First'},
          {'id': 'custom-duplicate', ...raw, 'name': 'Ignored'},
          {'id': 'custom-repaired', ...raw, 'name': ''},
          {'id': 'custom-repaired', ...raw, 'name': 'Repaired'},
          {'id': 'preset', ...raw, 'name': 'Rejected'},
        ],
      });
      expect(preferences.customThemes.map((theme) => theme.name), [
        'First',
        'Repaired',
      ]);
      expect(preferences.customTheme?.name, 'Repaired');
      expect(preferences.source, ForumThemeSource.custom);
    },
  );

  test('theme migration retains first identity and collision ordering', () {
    final theme = forumThemePresets.first;
    final library = ForumThemeLibrary(
      themes: [
        theme.copyWith(id: 'custom-a', name: 'First'),
        theme.copyWith(id: 'custom-a', name: 'Second'),
        theme.copyWith(id: 'custom-a-2', name: 'Occupied'),
      ],
    );
    final legacy = ForumThemePreferences(
      source: ForumThemeSource.custom,
      customId: 'custom-a',
      customThemes: [
        theme.copyWith(id: 'custom-a', name: 'Incoming'),
        theme.copyWith(id: 'custom-new', name: 'New'),
      ],
    );
    final migrated = library.migrate('https://example.com', legacy);
    expect(migrated.themes.map((theme) => theme.id), [
      'custom-a',
      'custom-a',
      'custom-a-2',
      'custom-a-3',
      'custom-new',
    ]);
    expect(migrated.themes.first.name, 'First');
    expect(migrated.forSite('https://example.com').customId, 'custom-a-3');
    expect(migrated.migrate('https://example.com', legacy), same(migrated));
    final identical = library.migrate(
      'https://another.example',
      ForumThemePreferences(customThemes: [library.themes.first]),
    );
    expect(identical.themes.length, 3);
  });

  test(
    'tracking expiry follows exact boundary, refresh and clock reversals',
    () {
      var now = DateTime.utc(2026);
      final filter = TopicTrackingMessageFilter(clock: () => now);
      const user = DiscourseUser(username: 'reader', mutedCategoryIds: [1]);
      Map<String, Object?> arrival(int id) => {
        'topic_id': id,
        'message_type': 'new_topic',
        'payload': {'category_id': 1},
      };
      filter.accepts({'topic_id': 1, 'message_type': 'unmuted'});
      now = now.add(const Duration(seconds: 30));
      filter.accepts({'topic_id': 1, 'message_type': 'unmuted'});
      now = now.subtract(const Duration(seconds: 60));
      filter.accepts({'topic_id': 2, 'message_type': 'unmuted'});
      now = now.add(const Duration(seconds: 60));
      expect(filter.accepts(arrival(2), user: user), isFalse);
      expect(filter.accepts(arrival(1), user: user), isTrue);
      now = now.add(const Duration(seconds: 60));
      expect(filter.accepts(arrival(1), user: user), isFalse);
      filter.accepts({'topic_id': 3, 'message_type': 'muted'});
      filter.accepts({'topic_id': 3, 'message_type': 'unmuted'});
      expect(filter.admitsIncoming(arrival(3), user: user), isFalse);
      now = now.add(const Duration(seconds: 60));
      expect(filter.accepts(arrival(3)), isTrue);
    },
  );

  test('tracking events avoid revisiting unexpired hint entries', () {
    final counts = _DateCounts();
    final now = _CountedDate(DateTime.utc(2026), counts);
    final filter = TopicTrackingMessageFilter(clock: () => now);
    for (var i = 0; i < 1000; i++) {
      filter.accepts({'topic_id': i + 1, 'message_type': 'unmuted'});
    }
    counts.comparisons = 0;
    for (var i = 0; i < 100; i++) {
      expect(
        filter.accepts({'topic_id': i + 1, 'message_type': 'read'}),
        isTrue,
      );
    }
    if (!_baseline) expect(counts.comparisons, lessThanOrEqualTo(100));
    // ignore: avoid_print
    print('WORK tracking_hint_expiry_comparisons=${counts.comparisons}');
  });

  test('additional model workloads consume checked production results', () {
    final times = measureAdditionalModelPerformance();
    expect(times.length, 6);
    expect(times.values, everyElement(greaterThan(0)));
    // ignore: avoid_print
    print('ADDITIONAL_MODEL_TIMES $times');
  });
}

class _DateCounts {
  var comparisons = 0;
}

class _CountedDate implements DateTime {
  _CountedDate(this.value, this.counts);

  final DateTime value;
  final _DateCounts counts;

  static DateTime _unwrap(DateTime other) =>
      other is _CountedDate ? other.value : other;

  @override
  DateTime add(Duration duration) => _CountedDate(value.add(duration), counts);

  @override
  bool isAfter(DateTime other) {
    counts.comparisons++;
    return value.isAfter(_unwrap(other));
  }

  @override
  bool isBefore(DateTime other) {
    counts.comparisons++;
    return value.isBefore(_unwrap(other));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
