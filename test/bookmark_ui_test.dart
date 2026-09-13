import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/bookmark_reminder_store.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/foundation/timezone_environment.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/bookmark_ui.dart';
import 'package:discourse_native/src/shell/post_actions.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Fault injection at shared_preferences' platform boundary is test-only.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _site = 'https://meta.example';
const _lastCustomKey = 'bookmark.last-custom.https%3A%2F%2Fmeta.example.reader';
const _post = Post(
  id: 12,
  postNumber: 2,
  username: 'sam',
  cooked: '<p>Post body</p>',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TimezoneEnvironment.instance.ensureDatabase();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'footer bookmark opens quick-create and saves editor changes once',
    (tester) async {
      final (controller, api) = await _controller();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _postActionsHost(
          controller,
          platform: TargetPlatform.macOS,
          post: _post,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('post-more-actions-2')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(DDropdownMenuItem, 'Bookmark'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('post-more-actions-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Bookmark this post'));
      await tester.pumpAndSettle();

      expect(api.createdBookmarks, hasLength(1));
      expect(find.text('Bookmarked!'), findsOneWidget);
      expect(find.text('In 2 hours'), findsOneWidget);
      expect(find.text('More options'), findsOneWidget);

      await tester.tap(find.text('More options'));
      await tester.pumpAndSettle();

      expect(find.text('Times use Europe/Paris.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'Follow up');
      await tester.tap(find.text('Tomorrow').last);
      await _scrollEditorToEnd(tester, 'Save');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(api.updatedBookmarks, hasLength(1));
      expect(api.updatedBookmarks.single.name, 'Follow up');
      expect(api.updatedBookmarks.single.reminderAt, isNotNull);
    },
  );

  testWidgets('touch long-press exposes the same bookmark action', (
    tester,
  ) async {
    final (controller, api) = await _controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _postActionsHost(
        controller,
        platform: TargetPlatform.android,
        post: _post,
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Post body'));
    await tester.pumpAndSettle();
    expect(find.text('Bookmark'), findsOneWidget);

    await tester.tap(find.text('Bookmark'));
    await tester.pumpAndSettle();

    expect(api.createdBookmarks, hasLength(1));
    expect(find.text('Bookmarked!'), findsOneWidget);
  });

  testWidgets('a saved bookmark stays tinted beside Reply', (tester) async {
    final (controller, _) = await _controller();
    addTearDown(controller.dispose);
    const bookmarkedPost = Post(
      id: 12,
      postNumber: 2,
      username: 'sam',
      cooked: '<p>Post body</p>',
      bookmark: Bookmark(
        id: 81,
        bookmarkableId: 12,
        bookmarkableType: 'Post',
        postNumber: 2,
      ),
    );
    await tester.pumpWidget(
      _postActionsHost(
        controller,
        platform: TargetPlatform.macOS,
        post: bookmarkedPost,
      ),
    );
    await tester.pumpAndSettle();

    final action = find.byTooltip('Edit this post bookmark');
    expect(action, findsOneWidget);
    final button = find.byKey(
      const ValueKey(('post-footer-action', 2, 'Edit bookmark')),
    );
    final icon = tester.widget<DIcon>(
      find.descendant(of: button, matching: find.byType(DIcon)),
    );
    expect(icon.icon, DIcons.bookmark);
    expect(icon.color, Theme.of(tester.element(action)).colorScheme.primary);
    expect(
      tester.getRect(button).left,
      greaterThanOrEqualTo(tester.getRect(find.text('Reply')).right),
    );
    expect(
      tester.getSize(button).width,
      DButton.iconOnlyDimensionFor(DButtonSize.small),
    );
    await tester.tap(find.byKey(const ValueKey('post-more-actions-2')));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(DDropdownMenuItem, 'Edit bookmark'),
      findsNothing,
    );
  });

  testWidgets('editor prefill is local and cancel discards it', (tester) async {
    final (controller, api) = await _controller();
    addTearDown(controller.dispose);
    const bookmark = Bookmark(
      id: 81,
      bookmarkableId: 12,
      bookmarkableType: 'Post',
      postNumber: 2,
      name: 'Original note',
    );
    await tester.pumpWidget(
      _host(
        controller,
        TargetPlatform.macOS,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => unawaited(
              showBookmarkEditor(
                context: context,
                controller: controller.bookmarkTarget(BookmarkTargetType.post),
                siteUrl: _site,
                topicId: 7,
                bookmark: bookmark,
              ),
            ),
            child: const Text('Open editor'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    expect(find.text('Original note'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'Changed locally');
    await _scrollEditorToEnd(tester, 'Cancel');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(api.updatedBookmarks, isEmpty);
  });

  testWidgets(
    'editor opens and saves with a wrong-typed last custom preference',
    (tester) => _withBookmarkDiagnostics((diagnostics) async {
      const malformed = <String>['private reminder suggestion'];
      SharedPreferences.setMockInitialValues({_lastCustomKey: malformed});
      final reminder = DateTime.utc(2026, 4, 17, 8);

      final api = await _openEditor(
        tester,
        now: DateTime.utc(2026, 4, 15, 12),
        reminder: reminder,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Last custom time'), findsNothing);
      expect(find.text('Tomorrow'), findsOneWidget);
      expect(
        diagnostics.events.whereType<ErrorDiagnosticEvent>().where(
          (event) => event.operation == 'bookmarkReminders.read',
        ),
        hasLength(1),
      );
      final preferences = await SharedPreferences.getInstance();
      await preferences.reload();
      expect(preferences.get(_lastCustomKey), malformed);

      await _saveEditor(tester);

      expect(tester.takeException(), isNull);
      expect(api.updatedBookmarks.single.reminderAt, reminder);
      expect(find.text('Open editor'), findsOneWidget);
    }),
  );

  for (final throwsError in [true, false]) {
    testWidgets(
      'custom reminder stays usable when preference write ${throwsError ? 'throws' : 'is rejected'}',
      (tester) => _withBookmarkDiagnostics((diagnostics) async {
        final now = DateTime.utc(2026, 4, 15, 12);
        final api = await _openEditor(tester, now: now);
        final preferences = _FailingBookmarkPreferences(
          throwsError: throwsError,
        );
        SharedPreferencesStorePlatform.instance = preferences;

        await _openCustomPicker(tester);
        await _confirmPicker(tester);
        await _confirmPicker(tester);

        expect(preferences.writes, 1);
        expect(find.text('Last custom time'), findsOneWidget);
        final warning = diagnostics.events
            .whereType<ErrorDiagnosticEvent>()
            .where((event) => event.operation == 'bookmarkReminders.write')
            .single;
        expect(warning.operation, 'bookmarkReminders.write');
        expect(warning.handled, isTrue);
        expect(warning.severity, DiagnosticSeverity.warning);

        await tester.ensureVisible(find.text('No reminder'));
        await tester.tap(find.text('No reminder'));
        await tester.pump();
        await tester.ensureVisible(find.text('Last custom time'));
        await tester.tap(find.text('Last custom time'));
        await tester.pump();
        await _saveEditor(tester);

        expect(tester.takeException(), isNull);
        expect(
          api.updatedBookmarks.single.reminderAt,
          now.add(const Duration(hours: 1)),
        );
        expect(find.text('Open editor'), findsOneWidget);
        final cached = await SharedPreferences.getInstance();
        await cached.reload();
        expect(cached.containsKey(_lastCustomKey), isFalse);
      }),
    );
  }

  testWidgets('custom picker clamps a past reminder to the account day', (
    tester,
  ) async {
    final api = await _openEditor(
      tester,
      now: DateTime.utc(2026, 4, 15, 8),
      reminder: DateTime.utc(2026, 4, 14, 10),
    );

    await _openCustomPicker(tester);
    final picker = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(picker.initialDate, DateTime(2026, 4, 15));
    expect(picker.firstDate, DateTime(2026, 4, 15));
    await _confirmPicker(tester);
    expect(
      tester
          .widget<TimePickerDialog>(find.byType(TimePickerDialog))
          .initialTime,
      const TimeOfDay(hour: 12, minute: 0),
    );
    await _confirmPicker(tester);
    expect(api.updatedBookmarks, isEmpty);
    await _saveEditor(tester);

    expect(
      api.updatedBookmarks.single.reminderAt,
      DateTime.utc(2026, 4, 15, 10),
    );
  });

  for (final scenario in [
    (
      label: 'a future reminder on the previous account day',
      timezone: 'America/Los_Angeles',
      now: DateTime.utc(2026, 1, 2, 0, 30),
      reminder: DateTime.utc(2026, 1, 2, 1, 30),
      day: DateTime(2026, 1, 1),
      hour: 17,
    ),
    (
      label: 'a new reminder on the previous account day',
      timezone: 'America/Los_Angeles',
      now: DateTime.utc(2026, 1, 2, 0, 30),
      reminder: null,
      day: DateTime(2026, 1, 1),
      hour: 17,
    ),
    (
      label: 'a future reminder on the next account day',
      timezone: 'Pacific/Kiritimati',
      now: DateTime.utc(2026, 1, 1, 23, 30),
      reminder: DateTime.utc(2026, 1, 2, 0, 30),
      day: DateTime(2026, 1, 2),
      hour: 14,
    ),
  ]) {
    testWidgets('custom picker uses ${scenario.label}', (tester) async {
      final environment = TimezoneEnvironment.instance;
      final originalDeviceTimezone = environment.deviceTimezone;
      environment.setDeviceTimezone('Etc/UTC');
      addTearDown(() => environment.setDeviceTimezone(originalDeviceTimezone));
      final api = await _openEditor(
        tester,
        now: scenario.now,
        reminder: scenario.reminder,
        timezone: scenario.timezone,
      );

      await _openCustomPicker(tester);
      final picker = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      expect(picker.initialDate, scenario.day);
      expect(picker.firstDate, scenario.day);
      expect(picker.currentDate, scenario.day);
      expect(
        picker.lastDate,
        DateTime(scenario.day.year + 10, scenario.day.month, scenario.day.day),
      );
      await _confirmPicker(tester);
      expect(
        tester
            .widget<TimePickerDialog>(find.byType(TimePickerDialog))
            .initialTime,
        TimeOfDay(hour: scenario.hour, minute: 30),
      );
      await _confirmPicker(tester);
      await _saveEditor(tester);

      expect(
        api.updatedBookmarks.single.reminderAt,
        scenario.now.add(const Duration(hours: 1)),
      );
    });
  }

  testWidgets('custom picker clamps a reminder beyond its upper bound', (
    tester,
  ) async {
    final api = await _openEditor(
      tester,
      now: DateTime.utc(2026, 4, 15, 12),
      reminder: DateTime.utc(2046, 4, 15, 8),
      timezone: 'Asia/Kolkata',
    );

    await _openCustomPicker(tester);
    final picker = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(picker.initialDate, DateTime(2036, 4, 15));
    expect(picker.initialDate, picker.lastDate);
    await _confirmPicker(tester);
    expect(
      tester
          .widget<TimePickerDialog>(find.byType(TimePickerDialog))
          .initialTime,
      const TimeOfDay(hour: 13, minute: 30),
    );
    await _confirmPicker(tester);
    await _saveEditor(tester);

    expect(
      api.updatedBookmarks.single.reminderAt,
      DateTime.utc(2036, 4, 15, 8),
    );
  });

  for (final scenario in [
    (
      label: 'past',
      reminder: DateTime.utc(2026, 4, 14, 8),
      error: 'Choose a reminder in the future.',
    ),
    (label: 'future', reminder: DateTime.utc(2026, 4, 17, 8), error: null),
    (
      label: 'beyond the upper bound',
      reminder: DateTime.utc(2046, 4, 15, 8),
      error: 'Choose a reminder no more than 10 years away.',
    ),
  ]) {
    for (final stage in ['date', 'time']) {
      testWidgets(
        'cancel custom $stage picker preserves a ${scenario.label} reminder',
        (tester) async {
          const store = BookmarkReminderStore();
          final lastCustom = DateTime.utc(2026, 4, 20, 10);
          await store.write(_site, 'reader', lastCustom);
          final api = await _openEditor(
            tester,
            now: DateTime.utc(2026, 4, 15, 12),
            reminder: scenario.reminder,
          );
          final originalLabel = tester
              .widget<Text>(find.textContaining('Reminder: '))
              .data;

          await _openCustomPicker(tester);
          await _enterPickerDate(tester, DateTime(2026, 4, 18));
          if (stage == 'time') {
            await _confirmPicker(tester);
            expect(find.byType(TimePickerDialog), findsOneWidget);
          }
          await tester.tap(find.text('Cancel').last);
          await tester.pumpAndSettle();

          expect(find.byType(DatePickerDialog), findsNothing);
          expect(find.byType(TimePickerDialog), findsNothing);
          expect(find.text(originalLabel!), findsOneWidget);
          expect(await store.read(_site, 'reader'), lastCustom);
          expect(api.updatedBookmarks, isEmpty);
          await _saveEditor(tester);
          if (scenario.error case final error?) {
            expect(find.text(error), findsOneWidget);
            expect(api.updatedBookmarks, isEmpty);
          } else {
            expect(api.updatedBookmarks.single.reminderAt, scenario.reminder);
          }
        },
      );
    }
  }

  for (final scenario in [
    (
      label: 'rejects a DST gap without changing the reminder',
      now: DateTime.utc(2026, 3, 28),
      reminder: DateTime.utc(2026, 3, 28, 1, 30),
      date: DateTime(2026, 3, 29),
      expected: null,
    ),
    (
      label: 'converts a valid time across the spring DST change',
      now: DateTime.utc(2026, 3, 28),
      reminder: DateTime.utc(2026, 3, 28, 2, 30),
      date: DateTime(2026, 3, 29),
      expected: DateTime.utc(2026, 3, 29, 1, 30),
    ),
    (
      label: 'resolves a DST overlap deterministically',
      now: DateTime.utc(2026, 10, 24),
      reminder: DateTime.utc(2026, 10, 24, 0, 30),
      date: DateTime(2026, 10, 25),
      expected: DateTime.utc(2026, 10, 25, 1, 30),
    ),
  ]) {
    testWidgets('custom picker ${scenario.label}', (tester) async {
      final api = await _openEditor(
        tester,
        now: scenario.now,
        reminder: scenario.reminder,
      );
      await _openCustomPicker(tester);
      await _enterPickerDate(tester, scenario.date);
      await _confirmPicker(tester);
      await _confirmPicker(tester);

      if (scenario.expected == null) {
        expect(
          find.text(
            'That local time does not exist because of daylight saving time.',
          ),
          findsOneWidget,
        );
      }
      expect(
        await const BookmarkReminderStore().read(_site, 'reader'),
        scenario.expected,
      );
      expect(api.updatedBookmarks, isEmpty);
      await _saveEditor(tester);
      expect(
        api.updatedBookmarks.single.reminderAt,
        scenario.expected ?? scenario.reminder,
      );
    });
  }

  for (final scenario in [
    (
      reminder: DateTime.utc(2026, 4, 15, 12),
      error: 'Choose a reminder in the future.',
    ),
    (
      reminder: DateTime.utc(2036, 4, 15, 12, 1),
      error: 'Choose a reminder no more than 10 years away.',
    ),
  ]) {
    testWidgets('custom picker keeps instant validation: ${scenario.error}', (
      tester,
    ) async {
      final api = await _openEditor(
        tester,
        now: DateTime.utc(2026, 4, 15, 12),
        reminder: scenario.reminder,
      );
      await _openCustomPicker(tester);
      await _confirmPicker(tester);
      await _confirmPicker(tester);
      await _saveEditor(tester);

      expect(find.text(scenario.error), findsOneWidget);
      expect(api.updatedBookmarks, isEmpty);
    });
  }

  testWidgets('grouped topic bookmarks are ordered by post number', (
    tester,
  ) async {
    const later = Bookmark(
      id: 83,
      bookmarkableId: 14,
      bookmarkableType: 'Post',
      postNumber: 4,
      name: 'Later',
    );
    const earlier = Bookmark(
      id: 82,
      bookmarkableId: 13,
      bookmarkableType: 'Post',
      postNumber: 3,
      name: 'Earlier',
    );
    final topic = _topic(bookmarks: const [later, earlier]).detail;
    final (controller, _) = await _controller(topic: topic);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        controller,
        TargetPlatform.macOS,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => unawaited(
              showTopicBookmarkMenu(
                context: context,
                controller: controller,
                siteUrl: _site,
                topic: topic,
              ),
            ),
            child: const Text('Manage bookmarks'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Manage bookmarks'));
    await tester.pumpAndSettle();

    expect(find.text('Post #3'), findsOneWidget);
    expect(find.text('Post #4'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Post #3')).dy,
      lessThan(tester.getTopLeft(find.text('Post #4')).dy),
    );
    expect(find.text('Delete all bookmarks'), findsOneWidget);
  });
}

Future<void> _withBookmarkDiagnostics(
  Future<void> Function(DiagnosticsController diagnostics) runTest,
) async {
  final diagnostics = await DiagnosticsController.create(
    persistence: MemoryDiagnosticsPersistence(),
    sessionId: 'bookmark-editor-preferences',
  );
  final binding = DiagnosticsSink.install(diagnostics);
  try {
    await runTest(diagnostics);
  } finally {
    binding.close();
    await diagnostics.close();
  }
}

final class _FailingBookmarkPreferences extends InMemorySharedPreferencesStore {
  _FailingBookmarkPreferences({required this.throwsError}) : super.empty();

  final bool throwsError;
  int writes = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key != 'flutter.$_lastCustomKey') {
      return super.setValue(valueType, key, value);
    }
    writes++;
    if (throwsError) throw PlatformException(code: 'unavailable');
    return false;
  }
}

Future<(ShellController, FakeDiscourseApi)> _controller({
  TopicDetail? topic,
  String timezone = 'Europe/Paris',
}) async {
  final payload = topic == null
      ? _topic()
      : (detail: topic, posts: const [_post]);
  final user = DiscourseUser(username: 'reader', timezone: timezone);
  final api = FakeDiscourseApi(
    user: user,
    feeds: const {
      '/latest.json': [Topic(id: 7, title: 'Topic', slug: 'topic')],
    },
    topics: {7: payload},
    siteConfigs: const {_site: SiteConfig.unknown()},
    bookmarkList: const [],
  );
  final authenticator = FakeAuthenticator()..keys[_site] = 'api-key';
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.example').copyWith(user: user),
    ]),
    api: api,
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    plugins: installedPlugins,
  );
  await controller.load();
  controller.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
  );
  await controller.loadTopic(7, 'topic');
  return (controller, api);
}

TopicPayload _topic({List<Bookmark> bookmarks = const []}) => (
  detail: TopicDetail(
    id: 7,
    title: 'Topic',
    stream: const [12],
    postsCount: 1,
    canCreatePost: true,
    bookmarks: bookmarks,
  ),
  posts: const [_post],
);

Widget _postActionsHost(
  ShellController controller, {
  required TargetPlatform platform,
  required Post post,
}) => _host(
  controller,
  platform,
  SizedBox(
    width: 240,
    // Accommodate the final Button touch targets in both action rows.
    height: 120,
    child: PostActions(
      siteUrl: _site,
      post: post,
      persistent: true,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Post body'),
          PostActionsFooter(child: SizedBox.shrink()),
        ],
      ),
    ),
  ),
);

Widget _host(
  ShellController controller,
  TargetPlatform platform,
  Widget child,
) => ShellScope(
  controller: controller,
  child: MaterialApp(
    theme: AppTheme.light.copyWith(platform: platform),
    home: Scaffold(body: Center(child: child)),
  ),
);

Future<void> _scrollEditorToEnd(WidgetTester tester, String action) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  final scrollable = find.ancestor(
    of: find.text(action),
    matching: find.byType(Scrollable),
  );
  final position = tester.state<ScrollableState>(scrollable).position;
  expect(position.maxScrollExtent, greaterThan(0));
  position.jumpTo(position.maxScrollExtent);
  await tester.pump();
}

Future<FakeDiscourseApi> _openEditor(
  WidgetTester tester, {
  required DateTime now,
  DateTime? reminder,
  String timezone = 'Europe/Paris',
}) async {
  final bookmark = Bookmark(
    id: 81,
    bookmarkableId: 12,
    bookmarkableType: 'Post',
    postNumber: 2,
    reminderAt: reminder,
  );
  final (controller, api) = await _controller(
    topic: _topic(bookmarks: [bookmark]).detail,
    timezone: timezone,
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    _host(
      controller,
      TargetPlatform.macOS,
      Builder(
        builder: (context) => FilledButton(
          onPressed: () => unawaited(
            showBookmarkEditor(
              context: context,
              controller: controller.bookmarkTarget(BookmarkTargetType.post),
              siteUrl: _site,
              topicId: 7,
              bookmark: bookmark,
              now: () => now,
            ),
          ),
          child: const Text('Open editor'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
  return api;
}

Future<void> _openCustomPicker(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Custom date and time'));
  await tester.tap(find.text('Custom date and time'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  expect(find.byType(DatePickerDialog), findsOneWidget);
}

Future<void> _confirmPicker(WidgetTester tester) async {
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _enterPickerDate(WidgetTester tester, DateTime date) async {
  final localizations = MaterialLocalizations.of(
    tester.element(find.byType(DatePickerDialog)),
  );
  await tester.tap(find.byTooltip(localizations.inputDateModeButtonLabel));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(
      of: find.byType(DatePickerDialog),
      matching: find.byType(TextFormField),
    ),
    localizations.formatCompactDate(date),
  );
}

Future<void> _saveEditor(WidgetTester tester) async {
  await _scrollEditorToEnd(tester, 'Save');
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}
