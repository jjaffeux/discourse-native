import 'dart:async';
import 'dart:collection';

import 'package:discourse_native/src/data/account_session_coordinator.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _personal = SidebarTag(id: 1, name: 'Personal', slug: 'personal-label');
const _top = SidebarTag(id: 2, name: 'Top', slug: 'top-label');
const _anonymous = SidebarTag(id: 3, name: 'Default', slug: 'default-label');
const _directory = SidebarTag(
  id: 4,
  name: 'Directory',
  slug: 'directory-label',
);
const _private = SidebarTag(
  id: 5,
  name: 'Private',
  slug: 'private',
  pmOnly: true,
);
const _user = DiscourseUser(id: 7, username: 'sam', sidebarTags: [_personal]);

void main() {
  test(
    'returns immutable tags in source order with case-insensitive precedence',
    () async {
      final api = _TagApi(
        categorySiteTopTags: const [
          SidebarTag(id: 11, name: 'PERSONAL', slug: 'lower-precedence'),
          _top,
          _private,
        ],
        categoryAnonymousDefaultTags: const [
          SidebarTag(id: 12, name: 'TOP', slug: 'lower-precedence'),
          _anonymous,
        ],
        tagList: const [
          SidebarTag(id: 13, name: 'DEFAULT', slug: 'lower-precedence'),
          _directory,
          _private,
          SidebarTag(id: 14, name: 'Private', slug: 'public-tag'),
        ],
      );
      final controller = await _loadController(api);
      await controller.loadTags(_siteUrl);

      final tags = controller.topicListFilterTagsFor(_siteUrl);
      expect(tags, const [
        _personal,
        _top,
        _anonymous,
        _directory,
        SidebarTag(id: 14, name: 'Private', slug: 'public-tag'),
      ]);
      expect(() => tags.add(_top), throwsUnsupportedError);
    },
  );

  test(
    'unchanged reads and counter updates reuse tags without scanning sources',
    () async {
      final personal = _CountingTags([_personal]);
      final user = DiscourseUser(id: 7, username: 'sam', sidebarTags: personal);
      final controller = await _loadController(
        _TagApi(reader: user),
        user: user,
      );
      final tags = controller.topicListFilterTagsFor(_siteUrl);
      expect(personal.iterations, greaterThan(0));
      personal.iterations = 0;

      for (var count = 1; count <= 20; count++) {
        _publishUser(controller, user.withDraftCount(count));
        expect(controller.topicListFilterTagsFor(_siteUrl), same(tags));
      }
      expect(personal.iterations, 0);
    },
  );

  test(
    'equal refresh responses preserve the merged snapshot identity',
    () async {
      final api = _TagApi(
        categorySiteTopTags: const [_top],
        categoryAnonymousDefaultTags: const [_anonymous],
        tagList: const [_directory],
      );
      final controller = await _loadController(api);
      await controller.loadTags(_siteUrl);
      final tags = controller.topicListFilterTagsFor(_siteUrl);

      await controller.loadCategories(_siteUrl, force: true);
      await controller.loadTags(_siteUrl, force: true);
      _publishUser(
        controller,
        DiscourseUser(
          id: 7,
          username: 'sam',
          sidebarTags: List.of(_user.sidebarTags),
        ),
      );
      expect(controller.topicListFilterTagsFor(_siteUrl), same(tags));
      expect(api.tagRequests, [_siteUrl, _siteUrl]);
    },
  );

  test(
    'refreshes each source and reveals the next source when precedence changes',
    () async {
      final top = [_top];
      final anonymous = [_anonymous];
      final directory = [_directory];
      final controller = await _loadController(
        _TagApi(
          categorySiteTopTags: top,
          categoryAnonymousDefaultTags: anonymous,
          tagList: directory,
        ),
      );
      await controller.loadTags(_siteUrl);
      final original = controller.topicListFilterTagsFor(_siteUrl);

      const renamed = SidebarTag(
        id: 1,
        name: 'PERSONAL',
        slug: 'renamed-label',
      );
      _publishUser(
        controller,
        const DiscourseUser(id: 7, username: 'sam', sidebarTags: [renamed]),
      );
      expect(controller.topicListFilterTagsFor(_siteUrl), [
        renamed,
        _top,
        _anonymous,
        _directory,
      ]);

      top[0] = const SidebarTag(id: 2, name: 'personal', slug: 'top-fallback');
      await controller.loadCategories(_siteUrl, force: true);
      expect(controller.topicListFilterTagsFor(_siteUrl), [
        renamed,
        _anonymous,
        _directory,
      ]);

      _publishUser(controller, const DiscourseUser(id: 7, username: 'sam'));
      expect(controller.topicListFilterTagsFor(_siteUrl), [
        top.single,
        _anonymous,
        _directory,
      ]);

      anonymous[0] = const SidebarTag(
        id: 3,
        name: 'Changed default',
        slug: 'changed-default',
      );
      await controller.loadCategories(_siteUrl, force: true);
      expect(controller.topicListFilterTagsFor(_siteUrl), [
        top.single,
        anonymous.single,
        _directory,
      ]);

      directory[0] = const SidebarTag(
        id: 4,
        name: 'Changed directory',
        slug: 'changed-directory',
      );
      await controller.loadTags(_siteUrl, force: true);
      expect(controller.topicListFilterTagsFor(_siteUrl), [
        top.single,
        anonymous.single,
        directory.single,
      ]);
      directory.clear();
      await controller.loadTags(_siteUrl, force: true);
      expect(controller.topicListFilterTagsFor(_siteUrl), [
        top.single,
        anonymous.single,
      ]);
      expect(original, [_personal, _top, _anonymous, _directory]);
    },
  );

  test(
    'directory loading and refresh failures retain the current snapshot',
    () async {
      final api = _TagApi(tagList: const [_directory]);
      final controller = await _loadController(api);
      await controller.loadTags(_siteUrl);
      final tags = controller.topicListFilterTagsFor(_siteUrl);
      final response = Completer<List<SidebarTag>>();
      api.directoryResponse = response.future;
      final refresh = controller.loadTags(_siteUrl, force: true);
      expect(controller.tagDirectoryFeedFor(_siteUrl).loading, isTrue);
      expect(controller.topicListFilterTagsFor(_siteUrl), same(tags));
      await api.directoryRequested.future;
      response.completeError(StateError('Refresh failed'));
      await refresh;
      expect(controller.tagDirectoryFeedFor(_siteUrl).error, isNotNull);
      expect(controller.topicListFilterTagsFor(_siteUrl), same(tags));
    },
  );

  test(
    'account replacement cannot reuse the previous account snapshot',
    () async {
      final controller = await _loadController(_TagApi());
      final tags = controller.topicListFilterTagsFor(_siteUrl);
      // Even identical tag objects and usernames must not hide an account ID change.
      _publishUser(
        controller,
        const DiscourseUser(id: 8, username: 'sam', sidebarTags: [_personal]),
      );
      final replacement = controller.topicListFilterTagsFor(_siteUrl);
      expect(replacement, tags);
      expect(replacement, isNot(same(tags)));
      expect(controller.topicListFilterTagsFor(_siteUrl), same(replacement));
    },
  );

  test(
    'site switching keeps separate snapshots and removal clears old taxonomy',
    () async {
      const secondUser = DiscourseUser(
        id: 9,
        username: 'lee',
        sidebarTags: [_directory],
      );
      final secondSite = instance(
        'team.discourse.org',
      ).copyWith(user: secondUser);
      final api = _TagApi()..readers[secondSite.url] = secondUser;
      final controller = await _loadController(
        api,
        additionalSites: [secondSite],
      );
      final firstTags = controller.topicListFilterTagsFor(_siteUrl);
      final secondTags = controller.topicListFilterTagsFor(secondSite.url);
      expect(firstTags, [_personal]);
      expect(secondTags, [_directory]);

      controller.selectInstance(1);
      expect(
        controller.topicListFilterTagsFor(controller.currentInstance!.url),
        same(secondTags),
      );
      controller.selectInstance(0);
      expect(
        controller.topicListFilterTagsFor(controller.currentInstance!.url),
        same(firstTags),
      );

      expect(
        await controller.removeInstance(controller.instanceFor(_siteUrl)!),
        isTrue,
      );
      expect(controller.topicListFilterTagsFor(_siteUrl), isEmpty);
      await controller.addInstance(instance('meta.discourse.org'));
      expect(controller.topicListFilterTagsFor(_siteUrl), isEmpty);
      expect(
        controller.topicListFilterTagsFor(secondSite.url),
        same(secondTags),
      );
    },
  );

  test(
    'disconnect drops personal and directory tags before another account connects',
    () async {
      final api = _TagApi(
        tagList: [_directory],
        categoryAnonymousDefaultTags: [_anonymous],
      );
      final controller = await _loadController(api);
      await controller.loadTags(_siteUrl);
      final tags = controller.topicListFilterTagsFor(_siteUrl);
      expect(tags, [_personal, _anonymous, _directory]);

      await controller.disconnectCurrentInstance();
      await controller.loadCategories(_siteUrl);
      expect(controller.topicListFilterTagsFor(_siteUrl), [_anonymous]);

      api.reader = const DiscourseUser(
        id: 8,
        username: 'lee',
        sidebarTags: [_top],
      );
      await controller.connectCurrentInstance();
      await controller.loadCategories(_siteUrl);
      expect(controller.topicListFilterTagsFor(_siteUrl), [_top, _anonymous]);
    },
  );
}

Future<ShellController> _loadController(
  _TagApi api, {
  DiscourseUser user = _user,
  List<DiscourseInstance> additionalSites = const [],
}) async {
  final sites = [
    instance('meta.discourse.org').copyWith(user: user),
    ...additionalSites,
  ];
  final authenticator = FakeAuthenticator();
  for (final site in sites) {
    authenticator.keys[site.url] = 'api-key';
  }
  final controller = ShellController(
    instanceStore: FakeInstanceStore(sites),
    api: api,
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    ownsApi: false,
  );
  addTearDown(controller.dispose);
  await controller.load();
  await controller.loadCategories(_siteUrl);
  return controller;
}

void _publishUser(ShellController controller, DiscourseUser user) {
  controller.applyAccountSessionInstance(
    controller.instanceFor(_siteUrl)!.copyWith(user: user),
    AccountSessionPhase.connecting,
  );
}

final class _CountingTags extends UnmodifiableListView<SidebarTag> {
  _CountingTags(super.source);

  int iterations = 0;

  @override
  Iterator<SidebarTag> get iterator {
    iterations++;
    return super.iterator;
  }
}

final class _TagApi extends FakeDiscourseApi {
  _TagApi({
    this.reader = _user,
    super.categorySiteTopTags,
    super.categoryAnonymousDefaultTags,
    super.tagList,
  }) : super(feeds: const {'/latest.json': []});

  DiscourseUser reader;
  final readers = <String, DiscourseUser>{};
  Future<List<SidebarTag>>? directoryResponse;
  final directoryRequested = Completer<void>();

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    currentUserRequests.add(siteUrl);
    return readers[siteUrl] ?? reader;
  }

  @override
  Future<List<SidebarTag>> tags({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    if (directoryResponse case final response?) {
      tagRequests.add(siteUrl);
      directoryRequested.complete();
      return response;
    }
    return super.tags(siteUrl: siteUrl, apiKey: apiKey, clientId: clientId);
  }
}
