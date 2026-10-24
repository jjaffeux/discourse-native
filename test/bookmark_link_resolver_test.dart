import 'dart:async';

import 'package:discourse_native/src/data/account_request_session.dart';
import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/bookmark_host.dart';
import 'package:discourse_native/src/plugin_api/shell_extensions.dart';
import 'package:discourse_native/src/shell/bookmark_link_resolver.dart';
import 'package:discourse_native/src/shell/bookmark_transactions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.example';
const _url = '$_site/t/topic/7';

final class _Credentials implements ApiCredentialReader {
  Completer<String?>? pending;
  int clientReads = 0;
  @override
  Future<String?> apiKeyFor(String siteUrl) =>
      pending?.future ?? Future.value('key');
  @override
  Future<String> clientId() async {
    clientReads++;
    throw StateError('Bookmark links require only the API key.');
  }
}

final class _Api extends FakeDiscourseApi {
  _Api({super.topicGate}) : super(topics: {7: topicPayload(id: 7)});
  Completer<int>? write;
  final requests = <({String? apiKey, String? clientId, Object? session})>[];
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
  }) {
    requests.add((
      apiKey: apiKey,
      clientId: clientId,
      session: AccountRequestScope.current?.session,
    ));
    return super.topic(
      siteUrl: siteUrl,
      slug: slug,
      id: id,
      postNumber: postNumber,
      apiKey: apiKey,
      clientId: clientId,
      summary: summary,
      abortTrigger: abortTrigger,
    );
  }

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
  }) =>
      write?.future ??
      super.createBookmark(
        siteUrl: siteUrl,
        apiKey: apiKey,
        targetType: targetType,
        targetId: targetId,
        name: name,
        reminderAt: reminderAt,
        autoDeletePreference: autoDeletePreference,
        clientId: clientId,
      );
}

final class _PluginResolver implements PluginBookmarkLinkResolver {
  final response = Completer<BookmarkLinkAction?>();
  final calls = <(String, String)>[];
  @override
  Future<BookmarkLinkAction?> resolveBookmarkLink(String siteUrl, String url) {
    calls.add((siteUrl, url));
    return response.future;
  }
}

final class _Fixture {
  _Fixture({_Api? api}) : api = api ?? _Api() {
    bookmarks = BookmarkTransactions(
      api: this.api,
      store: store,
      credentials: credentials,
      lifecycle: lifecycle,
      instanceAt: (_) => forum,
      siteContextFor: (_) =>
          const BookmarkSiteContext(suggestWeekendsInDatePickers: true),
      pluginStrategies: () => const [],
      topicData: (_, _) => null,
      checklistWriting: (_, _) => false,
      topicSlug: (_, _) => 'topic',
      changes: changes,
      changed: () => changes.notifyListeners(),
      refreshMenu: (_) async {},
      refreshList: (_) async {},
    );
    resolver = BookmarkLinkResolver(
      bookmarks: bookmarks,
      store: store,
      api: this.api,
      credentials: credentials,
      servingForum: (_) => forum,
      pluginResolvers: () => plugins,
    );
    store.put(_site, const Topic(id: 7, title: 'Topic', slug: 'topic'));
    addTearDown(() {
      bookmarks.dispose();
      changes.dispose();
    });
  }
  final _Api api;
  final credentials = _Credentials();
  final store = Store();
  final lifecycle = SiteLifecycle();
  final changes = ChangeNotifier();
  final forum = instance(
    'meta.example',
  ).copyWith(user: const DiscourseUser(username: 'reader'));
  List<PluginBookmarkLinkResolver> plugins = [];
  late final BookmarkTransactions bookmarks;
  late final BookmarkLinkResolver resolver;
}

void main() {
  test(
    'standalone resolution uses key-only credentials and the account lease',
    () async {
      final f = _Fixture();
      final account = f.bookmarks.forSite(_site);
      final action = await f.resolver.resolveBookmarkLink(_url);
      expect(action, isNotNull);
      expect(f.api.requests, [
        (apiKey: 'key', clientId: null, session: account.lease.session),
      ]);
      expect(f.credentials.clientReads, 0);
      expect(f.store.read<TopicDetail>(_site, 7), isNull);
      expect(f.api.createdBookmarks, isEmpty);
    },
  );

  test(
    'replacement during credential lookup cannot dispatch with a successor key',
    () async {
      final f = _Fixture();
      final key = Completer<String?>();
      f.credentials.pending = key;
      final pending = f.resolver.resolveBookmarkLink(_url);
      f.lifecycle.invalidate(_site);
      key.complete('old-key');
      expect(await pending, isNull);
      expect(f.api.requests, isEmpty);
      f.credentials.pending = null;
      expect(await f.resolver.resolveBookmarkLink(_url), isNotNull);
      expect(f.api.requests.single.apiKey, 'key');
    },
  );

  test(
    'a retired topic read cannot produce an action for its successor',
    () async {
      final gate = Completer<void>();
      final f = _Fixture(api: _Api(topicGate: gate));
      final pending = f.resolver.resolveBookmarkLink(_url);
      await pumpEventQueue();
      expect(f.api.requests, hasLength(1));
      f.lifecycle.invalidate(_site);
      gate.complete();
      expect(await pending, isNull);
      expect(await f.resolver.resolveBookmarkLink(_url), isNotNull);
      expect(f.api.requests.first.session, isNot(f.api.requests.last.session));
    },
  );

  for (final dispose in [false, true]) {
    test(
      'captured actions refuse after bookmark authority ${dispose ? 'disposal' : 'forgetting'}',
      () async {
        final f = _Fixture();
        final action = f.resolver.cachedTopicBookmarkLink(_url)!;
        if (dispose) {
          f.bookmarks.dispose();
        } else {
          f.bookmarks.forget(_site);
        }
        expect((await action.invoke()).saved, isFalse);
        expect(f.api.createdBookmarks, isEmpty);
        if (!dispose) {
          final next = f.resolver.cachedTopicBookmarkLink(_url)!;
          expect((await next.invoke()).saved, isTrue);
        }
      },
    );
  }

  test(
    'active writes refuse cached, fetched and previously resolved actions',
    () async {
      final f = _Fixture();
      final action = f.resolver.cachedTopicBookmarkLink(_url)!;
      final write = Completer<int>();
      f.api.write = write;
      final pending = f.bookmarks
          .forSite(_site)
          .createBookmark(
            topicId: 7,
            targetType: BookmarkTargetType.topic,
            targetId: 7,
          );
      expect(f.resolver.cachedTopicBookmarkLink(_url), isNull);
      expect(await f.resolver.resolveBookmarkLink(_url), isNull);
      expect((await action.invoke()).saved, isFalse);
      write.complete(91);
      expect((await pending).saved, isTrue);
    },
  );

  test(
    'plugin capabilities stay current and pending answers expire with the account',
    () async {
      final f = _Fixture();
      final first = _PluginResolver();
      f.plugins = [first];
      final pending = f.resolver.resolveBookmarkLink('$_site/plugin/42');
      expect(first.calls, [(_site, '$_site/plugin/42')]);
      f.lifecycle.invalidate(_site);
      final action = BookmarkLinkAction(
        bookmark: null,
        invoke: () async => const BookmarkWriteResult.saved(),
      );
      first.response.complete(action);
      expect(await pending, isNull);
      final next = _PluginResolver()..response.complete(action);
      f.plugins = [next];
      expect(
        await f.resolver.resolveBookmarkLink('$_site/plugin/42'),
        same(action),
      );
      expect(next.calls, hasLength(1));
      expect(f.api.requests, isEmpty);
    },
  );
}
