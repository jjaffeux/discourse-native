import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/foundation/timezone_environment.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/chat/chat_bookmark.dart';
import 'package:discourse_native/src/plugins/chat/chat_bookmark_ui.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/shell/bookmark_ui.dart';
import 'package:discourse_native/src/shell/post_actions.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_actions.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _site = 'https://meta.example';
const _otherSite = 'https://other.example';
const _reader = DiscourseUser(username: 'reader', timezone: 'Europe/Paris');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TimezoneEnvironment.instance.ensureDatabase();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final target in _Target.values) {
    testWidgets('${target.name} editor keeps its opening account', (
      tester,
    ) async {
      final fixture = await _Fixture.load(target);
      addTearDown(fixture.shell.dispose);
      await fixture.mount(tester);
      await fixture.open(tester);
      await tester.tap(find.text('Edit bookmark').last);
      await tester.pumpAndSettle();
      expect(find.text('Times use Europe/Paris.'), findsOneWidget);
      await fixture.replaceAccount(tester);
      // Force a form rebuild; the old form must not adopt the new timezone.
      await tester.enterText(find.byType(TextFormField), 'Old account note');
      await tester.ensureVisible(find.text('No reminder'));
      await tester.tap(find.text('No reminder'));
      await tester.pumpAndSettle();
      expect(find.text('Times use Europe/Paris.'), findsOneWidget);
      final reads = fixture.auth.reads;
      await _save(tester);
      expect(fixture.auth.reads, reads);
      expect(fixture.api.writes, isEmpty);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await fixture.open(tester);
      await tester.tap(find.text('Edit bookmark').last);
      await tester.pumpAndSettle();
      expect(find.text('Times use America/New_York.'), findsOneWidget);
      await _save(tester);
      expect(fixture.api.writes.single, (
        action: 'update',
        key: 'replacement-key',
        site: _site,
      ));
      expect(fixture.api.updatedBookmarks.single.bookmarkId, 181);
    });

    testWidgets('${target.name} delayed delete cannot cross reconnect', (
      tester,
    ) async {
      final fixture = await _Fixture.load(target);
      addTearDown(fixture.shell.dispose);
      await fixture.mount(tester);
      await fixture.open(tester);
      await tester.tap(find.text('Delete bookmark'));
      await tester.pumpAndSettle();
      expect(find.text('Delete bookmark?'), findsOneWidget);
      await fixture.replaceAccount(tester);
      final reads = fixture.auth.reads;
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(fixture.auth.reads, reads);
      expect(fixture.api.writes, isEmpty);
      expect(fixture.currentBookmark?.id, 181);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await fixture.open(tester);
      await tester.tap(find.text('Delete bookmark'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(fixture.api.writes.single, (
        action: 'delete',
        key: 'replacement-key',
        site: _site,
      ));
      expect(fixture.api.deletedBookmarks, [181]);
    });

    testWidgets(
      '${target.name} stale quick menu cannot clear or open an editor',
      (tester) async {
        final fixture = await _Fixture.load(target);
        addTearDown(fixture.shell.dispose);
        await fixture.mount(tester);
        await fixture.open(tester);
        await fixture.replaceAccount(tester);
        final reads = fixture.auth.reads;
        await tester.tap(find.text('Clear reminder'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit bookmark').last);
        await tester.pumpAndSettle();
        expect(find.byType(TextFormField), findsNothing);
        expect(fixture.auth.reads, reads);
        expect(fixture.api.writes, isEmpty);
      },
    );

    testWidgets(
      '${target.name} keeps its original site after unrelated navigation',
      (tester) async {
        final fixture = await _Fixture.load(target);
        addTearDown(fixture.shell.dispose);
        await fixture.mount(tester);
        await fixture.open(tester);
        fixture.shell.selectInstance(1);
        await tester.pumpAndSettle();
        expect(fixture.shell.currentInstance?.url, _otherSite);
        await tester.tap(find.text('Edit bookmark').last);
        await tester.pumpAndSettle();
        await _save(tester);
        expect(fixture.api.writes.single, (
          action: 'update',
          key: 'opening-key',
          site: _site,
        ));
        expect(fixture.api.updatedBookmarks.single.bookmarkId, 81);
      },
    );

    testWidgets(
      '${target.name} quick create captured before reconnect never starts',
      (tester) async {
        final fixture = await _Fixture.load(target, bookmarked: false);
        addTearDown(fixture.shell.dispose);
        await fixture.mount(tester);
        // Open the route, then reconnect before its builder can start a create.
        await fixture.tapOpen(tester);
        await fixture.replaceAccount(tester);
        expect(fixture.api.writes, isEmpty);
        expect(find.text('Bookmarked!'), findsNothing);
      },
    );

    testWidgets(
      '${target.name} quick create and reminder still use the opening target',
      (tester) async {
        final fixture = await _Fixture.load(target, bookmarked: false);
        addTearDown(fixture.shell.dispose);
        await fixture.mount(tester);
        await fixture.open(tester);
        expect(find.text('Bookmarked!'), findsOneWidget);
        expect(fixture.api.createdBookmarks.single.targetType, switch (target) {
          _Target.post => BookmarkTargetType.post,
          _Target.topic => BookmarkTargetType.topic,
          _Target.chat => chatMessageBookmarkTarget,
        });
        await tester.tap(find.text('In 2 hours'));
        await tester.pumpAndSettle();
        expect(fixture.api.updatedBookmarks.single.reminderAt, isNotNull);
        expect(fixture.api.writes.map((write) => write.key), [
          'opening-key',
          'opening-key',
        ]);
        expect(find.text('Bookmarked!'), findsNothing);
      },
    );
  }

  testWidgets(
    'topic clear-all confirmation cannot delete replacement bookmarks',
    (tester) async {
      final fixture = await _Fixture.load(_Target.topic, multiple: true);
      addTearDown(fixture.shell.dispose);
      await fixture.mount(tester);
      await fixture.open(tester);
      await tester.tap(find.text('Delete all bookmarks'));
      await tester.pumpAndSettle();
      await fixture.replaceAccount(tester);
      final reads = fixture.auth.reads;
      await tester.tap(find.text('Delete all'));
      await tester.pumpAndSettle();
      expect(fixture.auth.reads, reads);
      expect(fixture.api.writes, isEmpty);
      expect(
        fixture.shell.store.read<TopicDetail>(_site, 7)!.bookmarks,
        hasLength(2),
      );
      await fixture.open(tester);
      await tester.tap(find.text('Delete all bookmarks'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete all'));
      await tester.pumpAndSettle();
      expect(fixture.api.writes.single, (
        action: 'clear-all',
        key: 'replacement-key',
        site: _site,
      ));
    },
  );

  testWidgets('grouped post delete confirmation keeps the topic menu session', (
    tester,
  ) async {
    final fixture = await _Fixture.load(_Target.topic, multiple: true);
    addTearDown(fixture.shell.dispose);
    await fixture.mount(tester);
    await fixture.open(tester);
    await tester.tap(find.byTooltip('Post bookmark actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete bookmark?'), findsOneWidget);
    await fixture.replaceAccount(tester);
    final reads = fixture.auth.reads;
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(fixture.auth.reads, reads);
    expect(fixture.api.writes, isEmpty);
  });

  testWidgets(
    'custom date confirmation cannot advance to time after reconnect',
    (tester) async {
      final fixture = await _Fixture.load(_Target.post);
      addTearDown(fixture.shell.dispose);
      await fixture.mount(tester);
      await fixture.open(tester);
      await tester.tap(find.text('Edit bookmark').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Custom date and time'));
      await tester.tap(find.text('Custom date and time'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await fixture.replaceAccount(tester);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsNothing);
      expect(find.text('Times use Europe/Paris.'), findsOneWidget);
      expect(fixture.api.writes, isEmpty);
    },
  );

  testWidgets('late create does not alter or advance a replacement editor', (
    tester,
  ) async {
    final fixture = await _Fixture.load(_Target.post, bookmarked: false);
    addTearDown(fixture.shell.dispose);
    final response = Completer<int>();
    addTearDown(() {
      if (!response.isCompleted) response.complete(91);
    });
    fixture.api.createResponse = response;
    await fixture.mount(tester);
    await fixture.tapOpen(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(fixture.api.writes.single, (
      action: 'create',
      key: 'opening-key',
      site: _site,
    ));
    await fixture.replaceAccount(tester, settle: false);
    unawaited(
      showBookmarkEditor(
        context: tester.element(find.text('Saving bookmark…')),
        controller: fixture.shell.bookmarkTarget(BookmarkTargetType.post),
        siteUrl: _site,
        topicId: 7,
        bookmark: fixture.currentBookmark!,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    response.complete(91);
    await tester.pumpAndSettle();
    expect(find.text('Bookmark 181'), findsOneWidget);
    expect(find.text('Bookmarked!'), findsNothing);
    expect(
      find.text('The bookmark was saved on the forum.', skipOffstage: false),
      findsNothing,
    );
    expect(fixture.currentBookmark?.id, 181);
    expect(fixture.api.writes, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  for (final failure in [false, true]) {
    testWidgets(
      'late ${failure ? 'failed' : 'successful'} reminder write cannot affect another dialog',
      (tester) async {
        final fixture = await _Fixture.load(_Target.post);
        addTearDown(fixture.shell.dispose);
        final response = Completer<void>();
        addTearDown(() {
          if (!response.isCompleted) response.complete();
        });
        fixture.api.updateResponse = response;
        await fixture.mount(tester);
        await fixture.open(tester);
        await tester.tap(find.text('Clear reminder'));
        await tester.pump();
        expect(fixture.api.writes.single.key, 'opening-key');
        unawaited(
          showDialog<void>(
            context: tester.element(find.text('Clear reminder')),
            builder: (_) => const AlertDialog(title: Text('Another dialog')),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        if (failure) {
          response.completeError(const WriteException(WriteFailure.forbidden));
        } else {
          response.complete();
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Another dialog'), findsOneWidget);
        expect(
          find.text(
            const WriteException(WriteFailure.forbidden).message,
            skipOffstage: false,
          ),
          findsNothing,
        );
        expect(fixture.api.writes, hasLength(1));
        if (!failure) {
          expect(fixture.api.updatedBookmarks.single.reminderAt, isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final failure in [WriteFailure.forbidden, WriteFailure.unreachable]) {
    testWidgets(
      'current ${failure.name} write keeps its refusal or reconciliation message',
      (tester) async {
        final fixture = await _Fixture.load(_Target.post);
        addTearDown(fixture.shell.dispose);
        final response = Completer<void>();
        fixture.api.updateResponse = response;
        await fixture.mount(tester);
        await fixture.open(tester);
        await tester.tap(find.text('Clear reminder'));
        await tester.pump();
        response.completeError(WriteException(failure));
        await tester.pumpAndSettle();
        expect(
          find.text(
            failure == WriteFailure.unreachable
                ? "Couldn't confirm the bookmark changes. The topic is being refreshed."
                : WriteException(failure).message,
          ),
          findsOneWidget,
        );
        expect(find.text('Clear reminder'), findsOneWidget);
      },
    );
  }
}

enum _Target { post, topic, chat }

class _Fixture {
  _Fixture(this.target, this.multiple, this.shell, this.api, this.auth);

  final _Target target;
  final bool multiple;
  final ShellController shell;
  final _BookmarkApi api;
  final _Credentials auth;

  static Future<_Fixture> load(
    _Target target, {
    bool multiple = false,
    bool bookmarked = true,
  }) async {
    final api = _BookmarkApi();
    final auth = _Credentials()..keys[_site] = 'opening-key';
    final shell = ShellController(
      instanceStore: FakeInstanceStore([
        instance('meta.example').copyWith(user: _reader),
        instance('other.example').copyWith(user: _reader),
      ]),
      api: api,
      authenticator: auth,
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      plugins: installedPlugins,
    );
    await shell.load();
    shell.pushContent(
      ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
    );
    final fixture = _Fixture(target, multiple, shell, api, auth);
    fixture.seed(bookmarked ? 81 : null);
    return fixture;
  }

  Bookmark? get currentBookmark => switch (target) {
    _Target.post => shell.store.read<Post>(_site, 12)?.bookmark,
    _Target.topic => shell.store.read<TopicDetail>(_site, 7)?.topicBookmark,
    _Target.chat =>
      shell.pluginSession
          .require(chatControllerService)
          .messageRef(_site, 42)
          .value
          ?.bookmark,
  };

  void seed(int? id) {
    final bookmark = id == null
        ? null
        : Bookmark(
            id: id,
            bookmarkableId: switch (target) {
              _Target.post => 12,
              _Target.topic => 7,
              _Target.chat => 42,
            },
            bookmarkableType: switch (target) {
              _Target.post => 'Post',
              _Target.topic => 'Topic',
              _Target.chat => chatMessageBookmarkTarget.wireName,
            },
            postNumber: target == _Target.post ? 2 : null,
            name: 'Bookmark $id',
            reminderAt: DateTime.utc(2030, 1, 1),
          );
    final post = Post(
      id: 12,
      postNumber: 2,
      username: 'sam',
      cooked: '<p>Post body</p>',
      bookmark: target == _Target.post ? bookmark : null,
    );
    final detail = TopicDetail(
      id: 7,
      title: 'Topic',
      stream: const [12],
      postsCount: 1,
      canCreatePost: true,
      bookmarks: [
        if (target != _Target.chat && bookmark != null) bookmark,
        if (multiple && id != null)
          Bookmark(
            id: id + 1,
            bookmarkableId: 12,
            bookmarkableType: 'Post',
            postNumber: 2,
            reminderAt: DateTime.utc(2030, 1, 1),
          ),
      ],
    );
    api.topics[7] = (detail: detail, posts: [post]);
    shell.store.put(_site, detail);
    shell.store.put(_site, post);
    final chat = shell.pluginSession.require(chatControllerService);
    chat.putRecordForTesting(
      _site,
      const ChatChannel(
        id: 9,
        title: 'Support',
        kind: ChatChannelKind.category,
        membership: ChatMembership(following: true),
      ),
    );
    chat.putRecordForTesting(
      _site,
      ChatMessage(
        id: 42,
        channelId: 9,
        cooked: '<p>Chat body</p>',
        author: const ChatMessageAuthor(id: 2, username: 'sam'),
        bookmark: target == _Target.chat ? bookmark : null,
      ),
    );
  }

  Future<void> replaceAccount(WidgetTester tester, {bool settle = true}) async {
    final opening = shell.lifecycle.capture(_site);
    // Same username and URL are insufficient to identify an account lifetime.
    api.reader = const DiscourseUser(
      username: 'reader',
      timezone: 'America/New_York',
    );
    await shell.connectCurrentInstance();
    seed(181); // Restore eligible records so empty state cannot mask a write.
    shell.pushContent(
      ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
    expect(opening.isCurrent, isFalse);
    expect(auth.keys[_site], 'replacement-key');
    expect(shell.currentUserFor(_site)?.timezone, 'America/New_York');
  }

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: Builder(
              builder: (context) => ListenableBuilder(
                listenable: shell,
                builder: (context, _) => switch (target) {
                  _Target.post => PostActions(
                    siteUrl: _site,
                    post: shell.store.read<Post>(_site, 12)!,
                    persistent: true,
                    child: const PostActionsFooter(child: SizedBox.shrink()),
                  ),
                  _Target.topic => TopicBookmarkButton(
                    siteUrl: _site,
                    topic: shell.store.read<TopicDetail>(_site, 7)!,
                    busy: false,
                  ),
                  _Target.chat => FilledButton(
                    onPressed: () => unawaited(
                      showChatMessageBookmarkMenu(
                        context: context,
                        host: shell.pluginSession.require(
                          chatBookmarkHostService,
                        ),
                        siteUrl: _site,
                        messageId: 42,
                        bookmark: currentBookmark,
                        cooked: '<p>Chat body</p>',
                      ),
                    ),
                    child: const Text('Chat bookmark'),
                  ),
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tapOpen(tester);
    await tester.pumpAndSettle();
  }

  Future<void> tapOpen(WidgetTester tester) async {
    await tester.tap(switch (target) {
      _Target.post => find.byTooltip(
        currentBookmark == null
            ? 'Bookmark this post'
            : 'Edit this post bookmark',
      ),
      _Target.topic => find.byKey(const ValueKey('topic-bookmark-button')),
      _Target.chat => find.text('Chat bookmark'),
    });
  }
}

Future<void> _save(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await tester.ensureVisible(find.text('Save'));
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

class _Credentials extends FakeAuthenticator {
  _Credentials()
    : super(
        credentials: const UserApiCredentials(
          key: 'replacement-key',
          apiVersion: 4,
          push: false,
        ),
      );
  int reads = 0;

  @override
  Future<String?> apiKeyFor(String siteUrl) {
    reads++;
    return super.apiKeyFor(siteUrl);
  }
}

class _BookmarkApi extends FakeDiscourseApi {
  _BookmarkApi()
    : super(
        feeds: const {
          '/latest.json': [Topic(id: 7, title: 'Topic', slug: 'topic')],
        },
        topics: {},
        siteConfigs: const {
          _site: SiteConfig.unknown(),
          _otherSite: SiteConfig.unknown(),
        },
        bookmarkList: const [],
      );

  DiscourseUser reader = _reader;
  final writes = <({String action, String key, String site})>[];
  Completer<int>? createResponse;
  Completer<void>? updateResponse;

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => reader;

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
  }) async {
    writes.add((action: 'create', key: apiKey, site: siteUrl));
    if (createResponse case final response?) return response.future;
    return super.createBookmark(
      siteUrl: siteUrl,
      apiKey: apiKey,
      targetType: targetType,
      targetId: targetId,
      name: name,
      reminderAt: reminderAt,
      autoDeletePreference: autoDeletePreference,
    );
  }

  @override
  Future<void> updateBookmark({
    required String siteUrl,
    required String apiKey,
    required int bookmarkId,
    String? name,
    DateTime? reminderAt,
    required BookmarkAutoDeletePreference autoDeletePreference,
    String? clientId,
  }) async {
    writes.add((action: 'update', key: apiKey, site: siteUrl));
    await updateResponse?.future;
    await super.updateBookmark(
      siteUrl: siteUrl,
      apiKey: apiKey,
      bookmarkId: bookmarkId,
      name: name,
      reminderAt: reminderAt,
      autoDeletePreference: autoDeletePreference,
    );
  }

  @override
  Future<bool?> deleteBookmark({
    required String siteUrl,
    required String apiKey,
    required int bookmarkId,
    required BookmarkTargetType targetType,
    String? clientId,
  }) async {
    writes.add((action: 'delete', key: apiKey, site: siteUrl));
    return super.deleteBookmark(
      siteUrl: siteUrl,
      apiKey: apiKey,
      bookmarkId: bookmarkId,
      targetType: targetType,
    );
  }

  @override
  Future<void> deleteTopicBookmarks({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    String? clientId,
  }) async {
    writes.add((action: 'clear-all', key: apiKey, site: siteUrl));
  }
}
