import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_checklist.dart';
import 'package:discourse_native/src/plugin_api/bookmark_host.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/post_actions.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const site = 'https://meta.discourse.org';
const raw = '[ ] First\n[x] Second';
String cooked(String raw) =>
    '<p>${raw.split('\n').indexed.map((entry) {
      final checked = entry.$2.startsWith('[x]');
      return '<span class="chcklst-box ${checked ? 'checked fa-square-check-o' : 'fa-square-o'}" data-chk-src="${entry.$1}:0"></span>${entry.$2.substring(3)}';
    }).join('<br>')}</p>';
Post post({bool canEdit = true, bool withRaw = true}) => Post(
  id: 22,
  postNumber: 2,
  username: 'author',
  cooked: cooked(raw),
  raw: withRaw ? raw : null,
  canEdit: canEdit,
  updatedAt: DateTime.utc(2026, 9, 22),
  liked: true,
  likeCount: 4,
);

class ChecklistApi extends FakeDiscourseApi {
  ChecklistApi() : server = post();
  Post server;
  final calls = <Map<String, Object?>>[];
  Completer<void>? readGate;
  final writeGates = <Completer<void>>[];
  WriteException? refusal;
  bool readFails = false;
  int reads = 0;
  Post Function(Post)? transformSaved;

  @override
  Future<List<Post>> posts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    bool includeRaw = false,
    String? apiKey,
    String? clientId,
  }) async {
    reads++;
    await readGate?.future;
    if (readFails) throw Exception('Offline');
    return [server];
  }

  @override
  Future<PostChecklistUpdate> togglePostChecklist({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required List<Map<String, Object?>> toggles,
    required String expectedRaw,
    required DateTime expectedUpdatedAt,
    required String mutationId,
    String? clientId,
  }) async {
    final index = calls.length;
    calls.add({
      'site': siteUrl,
      'post': postId,
      'toggles': toggles,
      'raw': expectedRaw,
      'updatedAt': expectedUpdatedAt,
      'mutationId': mutationId,
    });
    if (index < writeGates.length) await writeGates[index].future;
    if (refusal != null) throw refusal!;
    final lines = server.raw!.split('\n');
    for (final toggle in toggles) {
      final i = toggle['checkbox_index'] as int;
      lines[i] =
          '${toggle['checked'] == true ? '[x]' : '[ ]'}${lines[i].substring(3)}';
    }
    final nextRaw = lines.join('\n');
    server = server.copyWith(
      raw: nextRaw,
      cooked: cooked(nextRaw),
      updatedAt: server.updatedAt!.add(const Duration(seconds: 1)),
      version: server.version + 1,
    );
    server = transformSaved?.call(server) ?? server;
    return PostChecklistUpdate(
      raw: server.raw!,
      cooked: server.cooked,
      updatedAt: server.updatedAt!,
      version: server.version,
    );
  }
}

class ChecklistBookmarkApi extends ChecklistApi {
  final bookmarkGate = Completer<void>();
  Completer<void>? bookmarkReadGate;

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
    final id = await super.createBookmark(
      siteUrl: siteUrl,
      apiKey: apiKey,
      targetType: targetType,
      targetId: targetId,
      name: name,
      reminderAt: reminderAt,
      autoDeletePreference: autoDeletePreference,
      clientId: clientId,
    );
    await bookmarkGate.future;
    server = server.withBookmark(
      Bookmark(id: id, bookmarkableType: 'Post', bookmarkableId: targetId),
    );
    return id;
  }

  @override
  Future<void> deleteTopicBookmarks({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    String? clientId,
  }) async {
    await bookmarkGate.future;
    server = server.withBookmark(null);
  }

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
    Future<void>? abortTrigger,
  }) async {
    topicsOpened.add(id);
    // Capture the body before waiting to exercise a stale bookmark response.
    final snapshot = server;
    await bookmarkReadGate?.future;
    return (
      detail: TopicDetail(
        id: 7,
        title: 'Topic',
        stream: const [22],
        postsCount: 1,
        bookmarks: [?snapshot.bookmark],
      ),
      posts: [snapshot],
    );
  }
}

/// Every whole-post checklist parse starts by reading the saved cooked HTML.
class _CookedReadCountingPost extends Post {
  const _CookedReadCountingPost({
    required super.cooked,
    required this.onCookedRead,
  }) : super(id: 22, postNumber: 2, username: 'author');

  final VoidCallback onCookedRead;

  @override
  String get cooked {
    onCookedRead();
    return super.cooked;
  }
}

bool bookmarkBusy(ShellController shell) => shell.bookmarkWriteInFlight(
  siteUrl: site,
  topicId: 7,
  targetType: BookmarkTargetType.post,
  targetId: 22,
);

Future<BookmarkWriteResult> bookmark(ShellController shell) =>
    shell.createBookmark(
      siteUrl: site,
      topicId: 7,
      targetType: BookmarkTargetType.post,
      targetId: 22,
    );

Future<ShellController> shellFor(
  ChecklistApi api, {
  Post? initial,
  bool liveRefresh = false,
}) async {
  final shell = ShellController(
    plugins: liveRefresh ? installedPlugins : null,
    instanceStore: FakeInstanceStore([
      instance(
        'meta.discourse.org',
      ).copyWith(user: const DiscourseUser(id: 7, username: 'author')),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[site] = 'api-key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  await shell.load();
  shell.store.put(
    site,
    const TopicDetail(id: 7, title: 'Topic', stream: [22], postsCount: 1),
  );
  shell.store.put(site, initial ?? post());
  shell.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
  );
  return shell;
}

List<bool> states(ShellController shell) => PostChecklistDocument(
  shell.store.read<Post>(site, 22)!.cooked,
).targets.map((t) => t.checked).toList();
Future<String?> toggle(ShellController shell, int index, bool checked) {
  final held = shell.store.read<Post>(site, 22)!;
  return shell.togglePostChecklist(
    siteUrl: site,
    topicId: 7,
    post: held,
    target: PostChecklistDocument(held.cooked).targets[index],
    checked: checked,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'endpoint sends the guarded checklist contract and decodes canonical content',
    () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'raw': '[x] First',
              'cooked': '<p>saved</p>',
              'version': 3,
              'updated_at': '2026-09-22T14:00:00.123Z',
            }),
            200,
          );
        }),
      );
      final target = PostChecklistDocument(post().cooked).targets.first;
      final result = await api.togglePostChecklist(
        siteUrl: site,
        apiKey: 'secret',
        postId: 22,
        toggles: [target.toggle(true)],
        expectedRaw: raw,
        expectedUpdatedAt: post().updatedAt!,
        mutationId: 'test-1',
      );
      expect(sent.method, 'PUT');
      expect(sent.url.path, '/checklist/toggle.json');
      expect(sent.headers['User-Api-Key'], 'secret');
      expect(jsonDecode(sent.body), {
        'post_id': 22,
        'toggles': [
          {'checkbox_index': 0, 'checkbox_source': '0:0', 'checked': true},
        ],
        'expected_raw': raw,
        'expected_updated_at': '2026-09-22T00:00:00.000Z',
        'mutation_id': 'test-1',
      });
      expect(result.raw, '[x] First');
      expect(result.version, 3);
      expect(result.updatedAt.millisecond, 123);
    },
  );

  test('legacy targets use rendered count and quoted controls are excluded', () {
    final doc = PostChecklistDocument(
      '<p><span class="chcklst-box"></span>One</p>'
      '<aside class="quote" data-post="1"><span class="chcklst-box" data-native-checklist-index="0"></span>Quoted</aside>'
      '<details><summary>Tasks</summary><span class="chcklst-box checked permanent"></span>Locked'
      '<span class="chcklst-box"></span>Three</details>',
    );
    expect(doc.targets.length, 3);
    expect(doc.targets.last.toggle(true), {
      'checkbox_index': 2,
      'checkbox_count': 3,
      'checked': true,
    });
    expect(doc.targets[1].permanent, isTrue);
    expect(
      RegExp(
        PostChecklistDocument.indexAttribute,
      ).allMatches(doc.annotatedHtml).length,
      3,
    );
    expect(
      PostChecklistDocument(doc.withStates({0: true, 2: true})).fingerprint,
      doc.fingerprint,
    );
  });

  test('annotation numbers owned boxes in order without altering markup', () {
    // The annotated markup is what HtmlWidget renders and where each checkbox
    // finds its target, so it is pinned byte for byte.
    final shapes = [
      (
        cooked(raw),
        '<p><span class="chcklst-box fa-square-o" data-chk-src="0:0" '
            'data-native-checklist-index="0"></span> First<br>'
            '<span class="chcklst-box checked fa-square-check-o" '
            'data-chk-src="1:0" data-native-checklist-index="1"></span> '
            'Second</p>',
      ),
      (
        '<p><span class="chcklst-box"></span>One</p>'
            '<aside class="quote" data-post="1"><span class="chcklst-box" '
            'data-native-checklist-index="0"></span>Quoted</aside>'
            '<details><summary>Tasks</summary><span class="chcklst-box '
            'checked permanent"></span>Locked<span class="chcklst-box"></span>'
            'Three</details>',
        '<p><span class="chcklst-box" data-native-checklist-index="0"></span>'
            'One</p><aside class="quote" data-post="1">'
            '<span class="chcklst-box"></span>Quoted</aside><details>'
            '<summary>Tasks</summary><span class="chcklst-box checked '
            'permanent" data-native-checklist-index="1"></span>Locked'
            '<span class="chcklst-box" data-native-checklist-index="2"></span>'
            'Three</details>',
      ),
      (
        '<ul><li><span class="chcklst-box fa-square-o" data-chk-src="0:0">'
            '</span> Parent<ul><li><span class="chcklst-box checked '
            'fa-square-check-o" data-chk-src="1:2"></span> Child</li></ul>'
            '</li></ul><div class="md-table"><table><thead><tr><th>Task</th>'
            '</tr></thead><tbody><tr><td><span class="chcklst-box fa-square-o" '
            'data-chk-src="4:2"></span> Cell &amp; &lt;b&gt;</td></tr></tbody>'
            '</table></div>',
        '<ul><li><span class="chcklst-box fa-square-o" data-chk-src="0:0" '
            'data-native-checklist-index="0"></span> Parent<ul><li>'
            '<span class="chcklst-box checked fa-square-check-o" '
            'data-chk-src="1:2" data-native-checklist-index="1"></span> Child'
            '</li></ul></li></ul><div class="md-table"><table><thead><tr>'
            '<th>Task</th></tr></thead><tbody><tr><td>'
            '<span class="chcklst-box fa-square-o" data-chk-src="4:2" '
            'data-native-checklist-index="2"></span> Cell &amp; &lt;b&gt;</td>'
            '</tr></tbody></table></div>',
      ),
      (
        '<div class="post-body" data-native-checklist-index="9"><p>'
            '<span class="chcklst-box" data-chk-src="x"></span>Legacy</p></div>',
        '<div class="post-body"><p><span class="chcklst-box" data-chk-src="x" '
            'data-native-checklist-index="0"></span>Legacy</p></div>',
      ),
    ];
    for (final (source, annotated) in shapes) {
      final doc = PostChecklistDocument(source);
      expect(doc.annotatedHtml, annotated);
      expect(doc.annotatedHtml, same(doc.annotatedHtml));
      expect(
        PostChecklistDocument(doc.annotatedHtml).targets.map((t) => t.source),
        doc.targets.map((t) => t.source),
      );
    }
  });

  test('raw fingerprints ignore only owned mutable source markers', () {
    final document = PostChecklistDocument(
      '<p><code>[ ]</code> '
      '<span class="chcklst-box" data-chk-src="0:1"></span> First<br>'
      '<span class="chcklst-box checked" data-chk-src="1:0"></span> Second<br>'
      '<span class="chcklst-box checked permanent"></span> Locked</p>'
      '<aside class="quote" data-post="1">'
      '<span class="chcklst-box" data-chk-src="4:0"></span> Quoted</aside>',
    );
    const before = '`[ ]` [] First\n[x] Second\n[X] Locked\n\n[ ] Quoted';
    final fingerprint = document.rawFingerprint(before);
    expect(fingerprint, isNotNull);
    expect(
      document.rawFingerprint(
        '`[ ]` [x] First\r\n[ ] Second\r\n[X] Locked\r\n\r\n[ ] Quoted',
      ),
      fingerprint,
    );
    for (final changed in [
      before.replaceFirst('`[ ]`', '`[x]`'),
      before.replaceFirst('First', 'Edited'),
      before.replaceFirst('[X]', '[x]'),
      before.replaceFirst('[ ] Quoted', '[x] Quoted'),
    ]) {
      expect(document.rawFingerprint(changed), isNot(fingerprint));
    }
    expect(document.rawFingerprint('Missing targets'), isNull);
    expect(document.rawFingerprint(before.replaceFirst('[]', '[X]')), isNull);
  });

  test(
    'legacy raw fingerprints follow core without changing permanent markers',
    () {
      final document = PostChecklistDocument(
        '<p><span class="chcklst-box"></span> First<br>'
        '<span class="chcklst-box checked permanent"></span> Locked</p>',
      );
      expect(
        document.rawFingerprint('[] First\n[X] Locked'),
        '[ ] First\n[X] Locked',
      );
      expect(
        document.rawFingerprint('[x] First\n[X] Locked'),
        '[ ] First\n[X] Locked',
      );
    },
  );

  test(
    'projects before raw loads, then persists while preserving reader fields',
    () async {
      final api = ChecklistApi()..readGate = Completer<void>();
      final shell = await shellFor(api, initial: post(withRaw: false));
      addTearDown(shell.dispose);
      final pending = toggle(shell, 0, true);
      expect(states(shell), [true, true]);
      expect(api.calls, isEmpty);
      api.readGate!.complete();
      expect(await pending, isNull);
      expect(api.server.raw, '[x] First\n[x] Second');
      expect(shell.store.read<Post>(site, 22)!.raw, api.server.raw);
      expect(shell.store.read<Post>(site, 22)!.likeCount, 4);
      expect(shell.store.read<Post>(site, 22)!.canEdit, isTrue);
      expect(shell.postWriteInFlight(22), isFalse);
    },
  );

  for (final bookmarkStartsFirst in [false, true]) {
    for (final bookmarkFinishesFirst in [false, true]) {
      for (final rejected in [false, true]) {
        test(
          'independent saves: bookmark starts first=$bookmarkStartsFirst, '
          'finishes first=$bookmarkFinishesFirst, checklist refused=$rejected',
          () async {
            final api = ChecklistBookmarkApi()
              ..writeGates.add(Completer<void>())
              ..refusal = rejected
                  ? const WriteException(WriteFailure.validation)
                  : null;
            final shell = await shellFor(api, liveRefresh: true);
            addTearDown(shell.dispose);
            late Future<BookmarkWriteResult> savingBookmark;
            late Future<String?> savingChecklist;
            if (bookmarkStartsFirst) {
              savingBookmark = bookmark(shell);
              savingChecklist = toggle(shell, 0, true);
            } else {
              savingChecklist = toggle(shell, 0, true);
              expect(bookmarkBusy(shell), isFalse);
              savingBookmark = bookmark(shell);
            }
            await pumpEventQueue();
            expect(states(shell), [true, true]);
            expect(api.calls, hasLength(1));
            expect(api.createdBookmarks, hasLength(1));
            expect(bookmarkBusy(shell), isTrue);
            expect((await bookmark(shell)).saved, isFalse);
            expect(api.createdBookmarks, hasLength(1));
            expect(shell.beginPluginPostWrite(site, 22), isFalse);
            FakeSiteTracker.built.last.deliverTopicMessage(
              '/topic/7/reactions',
              {
                'post_id': 22,
                'reactions': ['heart', null],
              },
            );
            await pumpEventQueue();
            expect(api.reads, 1);

            if (bookmarkFinishesFirst) {
              api.bookmarkGate.complete();
              expect((await savingBookmark).saved, isTrue);
              await pumpEventQueue();
              expect(api.topicsOpened, [7]);
              expect(bookmarkBusy(shell), isFalse);
              expect(states(shell), [true, true]);
              expect(shell.postWriteInFlight(22), isTrue);
              expect(api.reads, 1);
              api.writeGates.single.complete();
            } else {
              api.writeGates.single.complete();
              await savingChecklist;
              await pumpEventQueue();
              expect(api.reads, 1);
              expect(bookmarkBusy(shell), isTrue);
              expect(shell.postWriteInFlight(22), isTrue);
              api.bookmarkGate.complete();
              expect((await savingBookmark).saved, isTrue);
            }
            expect(await savingChecklist, rejected ? isNotNull : isNull);
            await pumpEventQueue();
            expect(api.reads, 2);
            expect(states(shell), [!rejected, true]);
            expect(shell.store.read<Post>(site, 22)!.bookmark, isNotNull);
            expect(shell.postWriteInFlight(22), isFalse);
            expect(bookmarkBusy(shell), isFalse);
          },
        );
      }
    }
  }

  test(
    'late bookmark reconciliation preserves a newer saved checklist',
    () async {
      final api = ChecklistBookmarkApi()
        ..writeGates.add(Completer<void>())
        ..bookmarkReadGate = Completer<void>();
      final shell = await shellFor(api);
      addTearDown(shell.dispose);
      final savingChecklist = toggle(shell, 0, true);
      api.bookmarkGate.complete();
      expect((await bookmark(shell)).saved, isTrue);
      await pumpEventQueue();
      expect(api.topicsOpened, [7]);
      api.writeGates.single.complete();
      expect(await savingChecklist, isNull);
      final saved = shell.store.read<Post>(site, 22)!;
      api.bookmarkReadGate!.complete();
      await pumpEventQueue();
      final after = shell.store.read<Post>(site, 22)!;
      expect(after.cooked, saved.cooked);
      expect(after.raw, saved.raw);
      expect(after.version, saved.version);
      expect(after.updatedAt, saved.updatedAt);
      expect(after.bookmark, isNotNull);
    },
  );

  test('bulk bookmark deletion can overlap a checklist save', () async {
    const initialBookmark = Bookmark(
      id: 91,
      bookmarkableType: 'Post',
      bookmarkableId: 22,
    );
    final api = ChecklistBookmarkApi()
      ..server = post().withBookmark(initialBookmark)
      ..writeGates.add(Completer<void>());
    final shell = await shellFor(api, initial: api.server);
    addTearDown(shell.dispose);
    shell.store.update<TopicDetail>(
      site,
      7,
      (held) => held.withBookmark(initialBookmark),
    );
    final savingChecklist = toggle(shell, 0, true);
    final deletingBookmarks = shell.deleteAllTopicBookmarks(
      siteUrl: site,
      topicId: 7,
    );
    expect(bookmarkBusy(shell), isTrue);
    api.bookmarkGate.complete();
    expect((await deletingBookmarks).saved, isTrue);
    await pumpEventQueue();
    expect(states(shell), [true, true]);
    expect(bookmarkBusy(shell), isFalse);
    expect(shell.postWriteInFlight(22), isTrue);
    api.writeGates.single.complete();
    expect(await savingChecklist, isNull);
    expect(shell.store.read<Post>(site, 22)!.bookmark, isNull);
    expect(shell.postWriteInFlight(22), isFalse);
  });

  testWidgets('bookmark button stays enabled while the checklist saves', (
    tester,
  ) async {
    final api = ChecklistApi()..writeGates.add(Completer<void>());
    final shell = await shellFor(api);
    addTearDown(shell.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ShellScope(
          controller: shell,
          child: Scaffold(
            body: PostActions(
              siteUrl: site,
              post: post(),
              persistent: true,
              child: const PostActionsFooter(child: Text('Post body')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final savingChecklist = toggle(shell, 0, true);
    await tester.pumpAndSettle();
    expect(api.calls, hasLength(1));
    await tester.tap(find.byKey(const ValueKey('post-more-actions-2')));
    await tester.pumpAndSettle();
    final item = tester.widget<DDropdownMenuItem>(
      find.widgetWithText(DDropdownMenuItem, 'Bookmark'),
    );
    expect(item.onPressed, isNotNull);
    api.writeGates.single.complete();
    await tester.pumpAndSettle();
    expect(await savingChecklist, isNull);
  });

  test(
    'rapid clicks remain immediate and save serially against the latest baseline',
    () async {
      final api = ChecklistApi()
        ..writeGates.add(Completer<void>())
        ..writeGates.add(Completer<void>());
      final shell = await shellFor(api);
      addTearDown(shell.dispose);
      final pending = toggle(shell, 0, true);
      await pumpEventQueue();
      expect(api.calls.length, 1);
      await toggle(shell, 0, false);
      await toggle(shell, 1, false);
      expect(states(shell), [false, false]);
      expect(api.calls.length, 1);
      api.writeGates[0].complete();
      await pumpEventQueue();
      expect(states(shell), [false, false]);
      expect(api.calls.length, 2);
      expect(api.calls[1]['raw'], '[x] First\n[x] Second');
      expect(api.calls[0]['mutationId'], isNot(api.calls[1]['mutationId']));
      api.writeGates[1].complete();
      expect(await pending, isNull);
      expect(api.server.raw, '[ ] First\n[ ] Second');
      expect(states(shell), [false, false]);
    },
  );

  testWidgets('recooking an older checklist saves without a conflict toast', (
    tester,
  ) async {
    // Core used fa-check-square-o before its Font Awesome rename. Saving an
    // older post recooks every checkbox, including the ones we did not toggle.
    final initial = post().copyWith(
      cooked: cooked(raw)
          .replaceAll('fa-square-check-o', 'fa-check-square-o')
          .replaceAll('chcklst-box ', 'chcklst-box fa-fw fa ')
          .replaceAll(RegExp(r' data-chk-src="\d+:\d+"'), ''),
    );
    final api = ChecklistApi()
      ..server = initial
      ..writeGates.add(Completer<void>())
      ..writeGates.add(Completer<void>());
    final shell = await shellFor(api, initial: initial);
    addTearDown(shell.dispose);
    final toasts = DToastController();
    addTearDown(toasts.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) =>
            DToaster(controller: toasts, child: child!),
        home: ShellScope(
          controller: shell,
          child: ValueListenableBuilder<Post?>(
            valueListenable: shell.store.ref<Post>(site, 22),
            builder: (context, post, _) => CookedHtml(
              html: post!.cooked,
              post: post,
              siteUrl: site,
              containingTopic: const PluginContainingTopic(
                id: 7,
                slug: 'topic',
                archived: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DCheckbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DCheckbox).last);
    await tester.pumpAndSettle();
    expect(states(shell), [true, false]);
    expect((api.calls.single['toggles'] as List).single, {
      'checkbox_index': 0,
      'checkbox_count': 2,
      'checked': true,
    });
    api.writeGates.first.complete();
    await tester.pumpAndSettle();
    expect(toasts.toasts.map((toast) => toast.options.description), isEmpty);
    expect(api.calls.length, 2);
    expect(api.calls.last['raw'], '[x] First\n[x] Second');
    expect((api.calls.last['toggles'] as List).single, {
      'checkbox_index': 1,
      'checkbox_source': '1:0',
      'checked': false,
    });
    api.writeGates.last.complete();
    await tester.pumpAndSettle();
    expect(api.server.raw, '[x] First\n[ ] Second');
    expect(states(shell), [true, false]);
    expect(toasts.toasts, isEmpty);
    // The refreshed rendering remains interactive after the queue drains.
    await tester.tap(find.byType(DCheckbox).first);
    await tester.pumpAndSettle();
    expect(api.server.raw, '[ ] First\n[ ] Second');
    expect(toasts.toasts, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final change in ['text', 'source', 'count', 'permanent']) {
    test('a save with changed $change stops queued clicks', () async {
      final api = ChecklistApi()
        ..writeGates.add(Completer<void>())
        ..transformSaved = (saved) => switch (change) {
          // Even a response whose cooked HTML has not caught up with its raw
          // Markdown must not be used to write over a changed task.
          'text' => saved.copyWith(
            raw: saved.raw!.replaceFirst('Second', 'Edited'),
          ),
          'source' => saved.copyWith(
            cooked: saved.cooked.replaceFirst(
              'data-chk-src="1:0"',
              'data-chk-src="0:0"',
            ),
          ),
          'count' => saved.copyWith(cooked: cooked('[x] First')),
          _ => saved.copyWith(
            cooked: saved.cooked.replaceFirst(
              'class="chcklst-box checked fa-square-check-o" data-chk-src="1:0"',
              'class="chcklst-box checked permanent fa-square-check"',
            ),
          ),
        };
      final shell = await shellFor(api);
      addTearDown(shell.dispose);
      final pending = toggle(shell, 0, true);
      await pumpEventQueue();
      await toggle(shell, 1, false);
      api.writeGates.single.complete();
      expect(await pending, isNotNull);
      expect(api.calls.length, 1);
      expect(shell.store.read<Post>(site, 22)!.raw, api.server.raw);
      expect(shell.store.read<Post>(site, 22)!.cooked, api.server.cooked);
      expect(shell.postWriteInFlight(22), isFalse);
    });
  }

  for (final failure in [
    WriteFailure.forbidden,
    WriteFailure.validation,
    WriteFailure.rateLimited,
  ]) {
    test('server $failure rolls back the optimistic checkbox', () async {
      final api = ChecklistApi()..refusal = WriteException(failure);
      final shell = await shellFor(api);
      addTearDown(shell.dispose);
      final pending = toggle(shell, 0, true);
      expect(states(shell), [true, true]);
      expect(await pending, isNotNull);
      expect(states(shell), [false, true]);
      expect(shell.postWriteInFlight(22), isFalse);
    });
  }

  test('read-only posts never project or send a write', () async {
    final api = ChecklistApi();
    final shell = await shellFor(api, initial: post(canEdit: false));
    addTearDown(shell.dispose);
    await toggle(shell, 0, true);
    expect(states(shell), [false, true]);
    expect(api.calls, isEmpty);
  });

  test('a later refusal preserves an earlier confirmed toggle', () async {
    final api = ChecklistApi()
      ..writeGates.add(Completer<void>())
      ..writeGates.add(Completer<void>());
    final shell = await shellFor(api);
    addTearDown(shell.dispose);
    final pending = toggle(shell, 0, true);
    await pumpEventQueue();
    await toggle(shell, 1, false);
    api.writeGates[0].complete();
    await pumpEventQueue();
    expect(states(shell), [true, false]);
    api.refusal = const WriteException(WriteFailure.validation);
    api.writeGates[1].complete();
    expect(await pending, isNotNull);
    expect(states(shell), [true, true]);
    expect(shell.store.read<Post>(site, 22)!.raw, '[x] First\n[x] Second');
  });

  test(
    'fresh permission revocation prevents the write and disables editing',
    () async {
      final api = ChecklistApi()..server = post(canEdit: false);
      final shell = await shellFor(api);
      addTearDown(shell.dispose);
      final pending = toggle(shell, 0, true);
      expect(states(shell), [true, true]);
      expect(await pending, isNotNull);
      expect(api.calls, isEmpty);
      expect(states(shell), [false, true]);
      expect(shell.store.read<Post>(site, 22)!.canEdit, isFalse);
    },
  );

  test(
    'newer post content is not overwritten by a late success or rollback',
    () async {
      for (final failure in [null, WriteFailure.validation]) {
        final api = ChecklistApi()..writeGates.add(Completer<void>());
        final shell = await shellFor(api);
        addTearDown(shell.dispose);
        final pending = toggle(shell, 0, true);
        await pumpEventQueue();
        final newer = post().copyWith(
          raw: 'New body',
          cooked: '<p>New body</p>',
          version: 9,
        );
        shell.store.put(site, newer);
        if (failure != null) api.refusal = WriteException(failure);
        api.writeGates.single.complete();
        await pending;
        expect(shell.store.read<Post>(site, 22), same(newer));
      }
    },
  );

  test(
    'conflicting content refreshes without overwriting the other edit',
    () async {
      final api = ChecklistApi()..writeGates.add(Completer<void>());
      final shell = await shellFor(api);
      addTearDown(shell.dispose);
      final pending = toggle(shell, 0, true);
      await pumpEventQueue();
      api.server = api.server.copyWith(
        raw: '[ ] Replaced\n[x] Second',
        cooked: cooked('[ ] Replaced\n[x] Second'),
        version: 3,
      );
      api.refusal = const WriteException(WriteFailure.conflict);
      api.writeGates.single.complete();
      expect(await pending, isNotNull);
      expect(shell.store.read<Post>(site, 22)!.raw, api.server.raw);
      expect(api.calls.length, 1);
    },
  );

  test(
    'lost response keeps the optimistic state when reconciliation is offline',
    () async {
      final api = ChecklistApi()..writeGates.add(Completer<void>());
      final shell = await shellFor(api);
      addTearDown(shell.dispose);
      final pending = toggle(shell, 0, true);
      await pumpEventQueue();
      api.refusal = const WriteException(WriteFailure.unreachable);
      api.readFails = true;
      api.writeGates.single.complete();
      expect(await pending, isNotNull);
      expect(states(shell), [true, true]);
      expect(shell.postWriteInFlight(22), isFalse);
    },
  );

  test(
    'account change disowns in-flight responses and new-session write guards',
    () async {
      final api = ChecklistApi()..writeGates.add(Completer<void>());
      final shell = await shellFor(api);
      addTearDown(shell.dispose);
      final pending = toggle(shell, 0, true);
      await pumpEventQueue();
      shell.lifecycle.invalidate(site);
      shell.endPluginPostWrite(site, 22);
      shell.beginPluginPostWrite(site, 22);
      final other = post().copyWith(cooked: '<p>Another account</p>');
      shell.store.put(site, other);
      api.writeGates.single.complete();
      await pending;
      expect(shell.store.read<Post>(site, 22), same(other));
      expect(shell.postWriteInFlight(22), isTrue);
    },
  );

  for (final kind in ['details', 'spoiler']) {
    testWidgets(
      'nested $kind keeps its disclosure open and whole-post checkbox index',
      (tester) async {
        const first =
            '<p><span class="chcklst-box fa-square-o" data-chk-src="0:0"></span>First</p>';
        const second =
            '<p><span class="chcklst-box checked fa-square-check-o" data-chk-src="1:0"></span>Second</p>';
        final body =
            first +
            (kind == 'details'
                ? '<details><summary>Tasks</summary>$second</details>'
                : '<div class="spoiler">$second</div>');
        final initial = post().copyWith(cooked: body);
        final api = ChecklistApi()
          ..server = initial
          ..writeGates.add(Completer<void>());
        final shell = await shellFor(api, initial: initial);
        addTearDown(shell.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: ShellScope(
              controller: shell,
              child: Scaffold(
                body: ValueListenableBuilder<Post?>(
                  valueListenable: shell.store.ref<Post>(site, 22),
                  builder: (context, post, _) => CookedHtml(
                    html: post!.cooked,
                    post: post,
                    siteUrl: site,
                    containingTopic: const PluginContainingTopic(
                      id: 7,
                      slug: 'topic',
                      archived: false,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(kind == 'details' ? 'Tasks' : 'Spoiler'));
        await tester.pumpAndSettle();
        expect(find.byType(DCheckbox), findsNWidgets(2));
        await tester.tap(find.byType(DCheckbox).last);
        await tester.pumpAndSettle();
        expect(find.byType(DCheckbox), findsNWidgets(2));
        expect(
          tester.widget<DCheckbox>(find.byType(DCheckbox).last).value,
          isFalse,
        );
        expect((api.calls.single['toggles'] as List).single, {
          'checkbox_index': 1,
          'checkbox_source': '1:0',
          'checked': false,
        });
        api.refusal = const WriteException(WriteFailure.validation);
        api.writeGates.single.complete();
        await tester.pumpAndSettle();
        expect(find.byType(DCheckbox), findsNWidgets(2));
        expect(
          tester.widget<DCheckbox>(find.byType(DCheckbox).last).value,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.iOS,
    TargetPlatform.android,
  ]) {
    for (final canEdit in [true, false]) {
      testWidgets(
        'posted checkbox interaction follows can_edit=$canEdit on $platform',
        (tester) async {
          final api = ChecklistApi()..writeGates.add(Completer<void>());
          final shell = await shellFor(api, initial: post(canEdit: canEdit));
          addTearDown(shell.dispose);
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light.copyWith(platform: platform),
              home: ShellScope(
                controller: shell,
                child: Scaffold(
                  body: ValueListenableBuilder<Post?>(
                    valueListenable: shell.store.ref<Post>(site, 22),
                    builder: (context, post, _) => CookedHtml(
                      html: post!.cooked,
                      post: post,
                      siteUrl: site,
                      containingTopic: const PluginContainingTopic(
                        id: 7,
                        slug: 'topic',
                        archived: false,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.widget<DCheckbox>(find.byType(DCheckbox).first).readOnly,
            !canEdit,
          );
          final artwork = tester.getRect(
            find.descendant(
              of: find.byType(DCheckbox).first,
              matching: find.byType(AnimatedContainer),
            ),
          );
          expect(
            artwork.size,
            Size.square(platform == TargetPlatform.macOS ? 16 : 24),
          );
          await tester.tapAt(artwork.bottomRight - const Offset(1, 1));
          await tester.pumpAndSettle();
          expect(
            tester.widget<DCheckbox>(find.byType(DCheckbox).first).value,
            canEdit,
          );
          expect(api.calls.length, canEdit ? 1 : 0);
          api.writeGates.single.complete();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('post-body wrapper keeps an editable checklist interactive', (
    tester,
  ) async {
    final api = ChecklistApi()..writeGates.add(Completer<void>());
    final shell = await shellFor(api);
    addTearDown(shell.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ShellScope(
          controller: shell,
          child: Scaffold(
            body: ValueListenableBuilder<Post?>(
              valueListenable: shell.store.ref<Post>(site, 22),
              builder: (context, current, _) => CookedHtml(
                html: '<div class="post-body">${current!.cooked}</div>',
                post: current,
                siteUrl: site,
                containingTopic: const PluginContainingTopic(
                  id: 7,
                  slug: 'topic',
                  archived: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<DCheckbox>(find.byType(DCheckbox).first).readOnly,
      false,
    );
    await tester.tap(find.byType(DCheckbox).first);
    await tester.pumpAndSettle();
    expect(tester.widget<DCheckbox>(find.byType(DCheckbox).first).value, true);
    expect(api.calls, hasLength(1));
    api.writeGates.single.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a checklist reads its saved post once, not once per task', (
    tester,
  ) async {
    // Each task, table cell and disclosure body is its own nested renderer, so
    // re-deriving the whole post's checklist in every one of them makes the
    // first frame of a long checklist quadratic in its length.
    Future<int> cookedReads(int tasks) async {
      final source = cooked(
        List.generate(tasks, (index) => '[ ] Task $index').join('\n'),
      );
      var reads = 0;
      final counted = _CookedReadCountingPost(
        cooked: source,
        onCookedRead: () => reads += 1,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: CookedHtml(
                html: source,
                post: counted,
                siteUrl: site,
                buildAsync: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(CookedHtml),
        findsNWidgets(tasks + 1),
        reason: 'every task must reach a nested renderer for this to count',
      );
      expect(find.byType(DCheckbox), findsNWidgets(tasks));
      await tester.pumpWidget(const SizedBox());
      return reads;
    }

    final short = await cookedReads(8);
    final long = await cookedReads(64);
    expect(
      long,
      short,
      reason: 'eight times the tasks read the post $long times against $short',
    );
  });

  testWidgets('a checklist post rendered again reuses its parse of the post', (
    tester,
  ) async {
    // Scrolling a post back into a lazily built list mounts a new renderer for
    // the same post, restyling rebuilds it, and a reaction, a like or a live
    // refresh hands it a new post with the same body; deriving the checklist
    // anew in any of them parses the whole body on the UI thread.
    Future<String> render(
      String html,
      Post post,
      Key key, {
      TextStyle? style,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: CookedHtml(
              key: key,
              html: html,
              post: post,
              siteUrl: site,
              textStyle: style,
              buildAsync: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final rendered = tester
          .widget<HtmlWidget>(find.byType(HtmlWidget).first)
          .html;
      expect(rendered, PostChecklistDocument(html).annotatedHtml);
      expect(
        tester
            .widgetList<DCheckbox>(find.byType(DCheckbox))
            .map((box) => box.value),
        [false, true],
      );
      return rendered;
    }

    // Built afresh each time, as a wrapping presentation does on every build.
    String wrapped(Post shown) =>
        '<div class="post-body">${shown.cooked}</div>';
    // A parse annotates its markup once and keeps the result, so rendering the
    // very same string is rendering the same parse.
    final original = post();
    final parsed = await render(
      wrapped(original),
      original,
      const ValueKey('mounted'),
    );
    // Every read builds its own post and its own copy of the body.
    final liked = post().withLike(true);
    expect(liked.cooked, isNot(same(original.cooked)));
    for (final (shown, style) in [
      (original, null),
      (original, const TextStyle(fontSize: 20)),
      (liked, null),
    ]) {
      expect(
        await render(
          wrapped(shown),
          shown,
          const ValueKey('remounted'),
          style: style,
        ),
        same(parsed),
        reason: 'the same markup was parsed again',
      );
    }
    // Other displayed markup is compared with the post, not handed this parse.
    await render(original.cooked, original, const ValueKey('remounted'));
  });
}
