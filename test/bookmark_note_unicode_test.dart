import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/bookmark_ui.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _site = 'https://meta.example';
const _post = Post(
  id: 12,
  postNumber: 2,
  username: 'sam',
  cooked: '<p>Post body</p>',
);
const _bookmark = Bookmark(
  id: 81,
  bookmarkableId: 12,
  bookmarkableType: 'Post',
  postNumber: 2,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final create in [true, false]) {
    testWidgets(
      '${create ? 'new' : 'existing'} bookmark note accepts 51 emoji through real HTTP validation',
      (tester) async {
        final (shell, requests) = await _openEditor(tester, create: create);
        addTearDown(shell.dispose);
        final note = List.filled(51, '🧵').join();
        await tester.enterText(find.byType(EditableText).first, note);
        await tester.pump();
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText).first)
              .controller
              .text,
          note,
        );

        await _save(tester);

        final updates = requests.where((request) => request.method == 'PUT');
        expect(updates, hasLength(1));
        expect(
          (jsonDecode(updates.single.body) as Map<String, dynamic>)['name'],
          note,
        );
        expect(find.text('Save'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'bookmark note blocks over 100 scalar values and recovers after editing',
    (tester) async {
      final (shell, requests) = await _openEditor(tester, create: false);
      addTearDown(shell.dispose);
      final note = List.filled(51, 'e\u0301').join();
      final input = find.byType(EditableText).first;
      await tester.enterText(input, note);
      await tester.pump();
      expect(tester.widget<EditableText>(input).controller.text, note);
      expect(
        find.text('Bookmark notes must be 100 characters or fewer.'),
        findsOneWidget,
      );
      final save = tester.widget<DButton>(find.widgetWithText(DButton, 'Save'));
      expect(save.onPressed, isNull);
      expect(requests, isEmpty);

      await tester.enterText(input, List.filled(100, '🧵').join());
      await tester.pump();
      expect(
        find.text('Bookmark notes must be 100 characters or fewer.'),
        findsNothing,
      );
      expect(
        tester.widget<DButton>(find.widgetWithText(DButton, 'Save')).onPressed,
        isNotNull,
      );
      await _save(tester);
      expect(
        (jsonDecode(requests.single.body) as Map<String, dynamic>)['name'],
        List.filled(100, '🧵').join(),
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Future<(ShellController, List<http.Request>)> _openEditor(
  WidgetTester tester, {
  required bool create,
}) async {
  final requests = <http.Request>[];
  final wireApi = DiscourseApi(
    client: MockClient((request) async {
      requests.add(request);
      return http.Response(request.method == 'POST' ? '{"id":81}' : '{}', 200);
    }),
  );
  addTearDown(wireApi.close);
  const user = DiscourseUser(username: 'reader', timezone: 'Europe/Paris');
  final api = _BookmarkWireApi(
    wireApi,
    user: user,
    topics: {
      7: (
        detail: TopicDetail(
          id: 7,
          title: 'Topic',
          stream: const [12],
          postsCount: 1,
          canCreatePost: true,
          bookmarks: create ? const [] : const [_bookmark],
        ),
        posts: const [_post],
      ),
    },
  );
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.example').copyWith(user: user),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'synthetic-key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    plugins: installedPlugins,
  );
  await shell.load();
  shell.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
  );
  await shell.loadTopic(7, 'topic');
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: Builder(
            builder: (context) => DButton(
              label: const Text('Open bookmark'),
              onPressed: () => unawaited(
                create
                    ? showPostBookmarkMenu(
                        context: context,
                        controller: shell,
                        siteUrl: _site,
                        topicId: 7,
                        post: _post,
                      )
                    : showBookmarkEditor(
                        context: context,
                        controller: shell.bookmarkTarget(
                          BookmarkTargetType.post,
                        ),
                        siteUrl: _site,
                        topicId: 7,
                        bookmark: _bookmark,
                      ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.runAsync(() async {
    await tester.tap(find.text('Open bookmark'));
    await pumpEventQueue();
  });
  await tester.pumpAndSettle();
  if (create) {
    expect(requests.single.method, 'POST');
    await tester.runAsync(() async {
      await tester.tap(find.text('More options'));
      await pumpEventQueue();
    });
    await tester.pumpAndSettle();
  }
  expect(find.text('Save'), findsOneWidget);
  return (shell, requests);
}

Future<void> _save(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await tester.ensureVisible(find.text('Save'));
  await tester.runAsync(() async {
    await tester.tap(find.text('Save'));
    await pumpEventQueue();
  });
  await tester.pumpAndSettle();
}

/// Keep reader/bootstrap fixtures local while exercising production bookmark
/// preflight, JSON encoding and HTTP writes from the actual editor.
final class _BookmarkWireApi extends FakeDiscourseApi {
  _BookmarkWireApi(this.wireApi, {super.user, super.topics})
    : super(
        feeds: const {
          '/latest.json': [Topic(id: 7, title: 'Topic', slug: 'topic')],
        },
      );

  final DiscourseApi wireApi;

  @override
  Future<int> createBookmark({
    required String siteUrl,
    required String apiKey,
    required BookmarkTargetType targetType,
    required int targetId,
    String? name,
    DateTime? reminderAt,
    BookmarkAutoDeletePreference? autoDeletePreference,
    String? clientId,
  }) => wireApi.createBookmark(
    siteUrl: siteUrl,
    apiKey: apiKey,
    targetType: targetType,
    targetId: targetId,
    name: name,
    reminderAt: reminderAt,
    autoDeletePreference: autoDeletePreference,
    clientId: clientId,
  );

  @override
  Future<void> updateBookmark({
    required String siteUrl,
    required String apiKey,
    required int bookmarkId,
    String? name,
    DateTime? reminderAt,
    required BookmarkAutoDeletePreference autoDeletePreference,
    String? clientId,
  }) => wireApi.updateBookmark(
    siteUrl: siteUrl,
    apiKey: apiKey,
    bookmarkId: bookmarkId,
    name: name,
    reminderAt: reminderAt,
    autoDeletePreference: autoDeletePreference,
    clientId: clientId,
  );
}
