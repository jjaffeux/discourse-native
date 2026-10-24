import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/custom_sidebar_sections.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

const _site = 'https://forum.example/discuss';
const _otherSite = 'https://other.example';

SidebarSection _section(int id, List<int> links, {bool public = false}) =>
    SidebarSection.customFromJson({
      'id': id,
      'title': 'Section $id',
      'public': public,
      'links': [
        for (final link in links)
          {
            'id': link,
            'name': 'Link $link',
            'value': '/link-$link',
            'icon': 'link',
          },
      ],
    }, index: id)!;

List<int?> _order(SidebarSection section) => [
  for (final link in section.destinations) link.linkId,
];

Future<void> _flush() => Future<void>.delayed(Duration.zero);

final class _Credentials implements ApiCredentialReader {
  String? key = 'key';
  Future<String?> Function()? readKey;
  int keyReads = 0;
  int clientReads = 0;

  @override
  Future<String?> apiKeyFor(String siteUrl) {
    keyReads++;
    return readKey?.call() ?? Future.value(key);
  }

  @override
  Future<String> clientId() async {
    clientReads++;
    return 'client';
  }
}

final class _Read {
  _Read(this.siteUrl, this.apiKey, this.clientId);

  final String siteUrl;
  final String? apiKey;
  final String? clientId;
  final result = Completer<List<SidebarSection>>();
}

final class _Reorder {
  _Reorder(this.sectionId, this.order, this.apiKey);

  final int sectionId;
  final List<int> order;
  final String apiKey;
  final result = Completer<SidebarSection>();
}

final class _Move {
  _Move(this.sourceId, this.targetId, this.linkId, this.position);

  final int sourceId;
  final int targetId;
  final int linkId;
  final int position;
  final result = Completer<List<SidebarSection>>();
}

final class _Api extends FakeDiscourseApi {
  final reads = <_Read>[];
  final reorders = <_Reorder>[];
  final moves = <_Move>[];

  @override
  Future<List<SidebarSection>> customSidebarSections({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) {
    final request = _Read(siteUrl, apiKey, clientId);
    reads.add(request);
    return request.result.future;
  }

  @override
  Future<SidebarSection> reorderSidebarLinks({
    required String siteUrl,
    required String apiKey,
    required int sectionId,
    required List<int> linksOrder,
    String? clientId,
  }) {
    final request = _Reorder(sectionId, List.of(linksOrder), apiKey);
    reorders.add(request);
    return request.result.future;
  }

  @override
  Future<List<SidebarSection>> moveSidebarLink({
    required String siteUrl,
    required String apiKey,
    required int sourceSectionId,
    required int targetSectionId,
    required int linkId,
    required int position,
    String? clientId,
  }) {
    final request = _Move(sourceSectionId, targetSectionId, linkId, position);
    moves.add(request);
    return request.result.future;
  }
}

final class _Harness {
  _Harness({
    bool connected = true,
    bool admin = false,
    bool loginRequired = false,
  }) {
    instance = DiscourseInstance(
      url: _site,
      title: 'Forum',
      loginRequired: loginRequired,
      user: connected
          ? DiscourseUser(id: 7, username: 'reader', admin: admin)
          : null,
    );
    owner = CustomSidebarSections(
      api: api,
      credentials: credentials,
      lifecycle: lifecycle,
      instanceFor: (site) => site == _site ? instance : null,
      selectedSite: () => selected,
      onChanged: () => changes++,

      clock: () => now,
    );
    addTearDown(owner.dispose);
  }

  final api = _Api();
  final credentials = _Credentials();
  final lifecycle = SiteLifecycle();
  late DiscourseInstance instance;
  late final CustomSidebarSections owner;
  String? selected = _site;
  DateTime now = DateTime.utc(2026, 10, 19);
  int changes = 0;

  List<SidebarSection> get sections => owner.customFor(_site);
  SiteLease get lease => lifecycle.capture(_site);

  Future<void> load(List<SidebarSection> sections) async {
    final loading = owner.ensure(_site);
    await _flush();
    api.reads.last.result.complete(sections);
    await loading;
  }

  Future<void> reorder(int index, {int oldIndex = 0, int newIndex = 2}) =>
      owner.reorder(
        siteUrl: _site,
        section: sections[index],
        oldIndex: oldIndex,
        newIndex: newIndex,
      );

  Future<void> move({int oldIndex = 0, int newIndex = 1}) => owner.move(
    siteUrl: _site,
    source: sections[0],
    target: sections[1],
    oldIndex: oldIndex,
    newIndex: newIndex,
  );
}

void main() {
  group('custom sidebar loads', () {
    test(
      'signed-in production owner publishes anonymous custom artwork',
      () async {
        final requests = <http.Request>[];
        final api = DiscourseApi(
          client: MockClient((request) async {
            requests.add(request);
            if (request.url.path.endsWith('/sidebar_sections.json')) {
              return http.Response(
                jsonEncode({
                  'sidebar_sections': [
                    {
                      'id': 9,
                      'title': 'Projects',
                      'links': [
                        {
                          'id': 11,
                          'name': 'Project',
                          'value': '/project',
                          'icon': 'theme-logo',
                        },
                      ],
                    },
                  ],
                }),
                200,
              );
            }
            return http.Response(
              '<svg viewBox="0 0 16 16"><path d="M0 16L8 0L16 16Z"/></svg>',
              200,
            );
          }),
        );
        addTearDown(api.close);
        const instance = DiscourseInstance(
          url: _site,
          title: 'Forum',
          user: DiscourseUser(id: 7, username: 'reader'),
        );
        var changes = 0;
        final owner = CustomSidebarSections(
          api: api,
          credentials: _Credentials(),
          lifecycle: SiteLifecycle(),
          instanceFor: (_) => instance,
          selectedSite: () => _site,
          onChanged: () => changes++,
        );
        addTearDown(owner.dispose);
        await owner.ensure(_site);
        final link = owner.customFor(_site).single.destinations.single;
        expect(link.url, '/project');
        expect(link.icon.name, 'theme-logo');
        expect(link.icon.svg, contains('M0 16L8 0L16 16Z'));
        expect(changes, 1);
        expect(requests, hasLength(2));
        expect(requests.first.headers['User-Api-Key'], 'key');
        expect(requests.first.headers['User-Api-Client-Id'], 'client');
        expect(
          requests.last.url.path,
          '/discuss/svg-sprite/forum.example/icon/theme-logo.svg',
        );
        expect(requests.last.headers['User-Api-Key'], isNull);
        expect(requests.last.headers['User-Api-Client-Id'], isNull);
      },
    );
    test(
      'retirement observers cannot read the retired account snapshot',
      () async {
        final h = _Harness();
        List<SidebarSection>? observed;
        h.lease.onRetire(() => observed = h.sections);
        await h.load([
          _section(9, [11, 12]),
        ]);
        h.lifecycle.invalidate(_site);
        expect(observed, isEmpty);
        expect(h.sections, isEmpty);
      },
    );

    test(
      'joins pending credentials and HTTP and caches an empty response',
      () async {
        final h = _Harness();
        final key = Completer<String?>();
        h.credentials.readKey = () => key.future;
        final first = h.owner.ensure(_site);
        expect(h.owner.ensure(_site), same(first));
        expect(h.credentials.keyReads, 1);
        expect(h.api.reads, isEmpty);

        key.complete('key');
        await _flush();
        expect(h.api.reads, hasLength(1));
        expect(h.owner.ensure(_site), same(first));
        h.api.reads.single.result.complete([]);
        await first;
        await h.owner.ensure(_site);

        expect(h.api.reads, hasLength(1));
        expect(h.sections, isEmpty);
        expect(h.changes, 1);
      },
    );

    test(
      'loads only selected readable sites and keeps public reads anonymous',
      () async {
        final h = _Harness(connected: false, loginRequired: true);
        await h.owner.ensure(_site);
        h.instance = h.instance.copyWith(loginRequired: false);
        h.selected = _otherSite;
        await h.owner.ensure(_site);
        await h.owner.ensure(_otherSite);
        expect(h.api.reads, isEmpty);
        expect(h.credentials.keyReads, 0);

        h.selected = _site;
        final loading = h.owner.ensure(_site);
        await _flush();
        expect(h.api.reads.single.siteUrl, _site);
        expect(h.api.reads.single.apiKey, isNull);
        expect(h.api.reads.single.clientId, isNull);
        expect(h.credentials.keyReads, 0);
        expect(h.credentials.clientReads, 0);
        h.api.reads.single.result.complete([]);
        await loading;
        expect(h.changes, 1);
      },
    );

    test(
      'publishes immutable snapshots and caches composition by identity',
      () async {
        final h = _Harness();
        final links = List.of(_section(9, [11, 12]).destinations);
        final more = List.of(_section(10, [21]).destinations);
        final source = <SidebarSection>[
          SidebarSection(
            id: 'custom-9',
            title: 'Projects',
            destinations: links,
            moreDestinations: more,
            remoteId: 9,
            public: true,
            unreadCount: 5,
          ),
        ];
        await h.load(source);
        final custom = h.sections;
        final composed = h.owner.sectionsFor(h.instance);
        expect(h.sections, same(custom));
        expect(h.owner.sectionsFor(h.instance), same(composed));
        expect(custom.single.title, 'Projects');
        expect(custom.single.public, isTrue);
        expect(custom.single.unreadCount, 5);
        expect(custom.single.moreDestinations.single.linkId, 21);
        expect(() => custom.clear(), throwsUnsupportedError);
        expect(
          () => custom.single.destinations.clear(),
          throwsUnsupportedError,
        );
        expect(
          () => custom.single.moreDestinations.clear(),
          throwsUnsupportedError,
        );
        expect(() => composed.clear(), throwsUnsupportedError);

        source.clear();
        links.clear();
        more.clear();
        expect(_order(custom.single), [11, 12]);
        expect(custom.single.moreDestinations, hasLength(1));
        h.instance = h.instance.copyWith(title: 'Renamed forum');
        expect(h.owner.sectionsFor(h.instance), isNot(same(composed)));
        final renamed = h.owner.sectionsFor(h.instance);
        h.owner.invalidate(_site, account: h.lease);
        expect(h.sections, same(custom));
        expect(h.owner.sectionsFor(h.instance), same(renamed));
        await _flush();
        h.api.reads.last.result.complete([
          _section(9, [12, 11]),
        ]);
        await h.owner.ensure(_site);
        expect(h.sections, isNot(same(custom)));
        expect(h.owner.sectionsFor(h.instance), isNot(same(renamed)));
      },
    );

    test(
      'HTTP failure retries at five minutes and invalidation bypasses cooldown',
      () async {
        final h = _Harness();
        final failure = StateError('offline');
        final first = h.owner.ensure(_site);
        await _flush();
        h.api.reads.single.result.completeError(failure);
        await first;
        await h.owner.ensure(_site);
        h.now = h.now.add(const Duration(minutes: 4, seconds: 59));
        await h.owner.ensure(_site);
        expect(h.api.reads, hasLength(1));

        h.now = h.now.add(const Duration(seconds: 1));
        final retry = h.owner.ensure(_site);
        await _flush();
        expect(h.api.reads, hasLength(2));
        h.api.reads.last.result.completeError(failure);
        await retry;
        h.owner.invalidate(_site, account: h.lease);
        await _flush();
        expect(h.api.reads, hasLength(3));
        h.api.reads.last.result.complete([]);
        await h.owner.ensure(_site);
        expect(h.changes, 1);
      },
    );

    test('credential failures do not start the HTTP retry cooldown', () async {
      final h = _Harness();
      final failure = StateError('storage unavailable');
      h.credentials.readKey = () => Future.error(failure);
      await h.owner.ensure(_site);
      expect(h.api.reads, isEmpty);
      h.credentials.readKey = null;
      await h.load([
        _section(9, [11, 12]),
      ]);
      expect(h.api.reads, hasLength(1));
      expect(_order(h.sections.single), [11, 12]);
    });

    test(
      'selection changes before credentials settle prevent dispatch',
      () async {
        final h = _Harness();
        final key = Completer<String?>();
        h.credentials.readKey = () => key.future;
        final loading = h.owner.ensure(_site);
        h.selected = _otherSite;
        key.complete('key');
        await loading;
        expect(h.api.reads, isEmpty);
        expect(h.changes, 0);

        h.selected = _site;
        h.credentials.readKey = null;
        await h.load([
          _section(9, [11, 12]),
        ]);
        expect(h.api.reads, hasLength(1));
        expect(h.changes, 1);
      },
    );

    test(
      'an already dispatched current-account read may publish while inactive',
      () async {
        final h = _Harness();
        final loading = h.owner.ensure(_site);
        await _flush();
        h.selected = _otherSite;
        h.api.reads.single.result.complete([
          _section(9, [11, 12]),
        ]);
        await loading;
        expect(_order(h.sections.single), [11, 12]);
        expect(h.changes, 1);
      },
    );

    test(
      'retirement during credentials cannot dispatch or invalidate a successor',
      () async {
        final h = _Harness();
        final oldLease = h.lease;
        final oldKey = Completer<String?>();
        h.credentials.readKey = () => oldKey.future;
        final retired = h.owner.ensure(_site, account: oldLease);
        h.lifecycle.invalidate(_site);
        h.credentials.readKey = null;
        h.credentials.key = 'successor-key';
        await h.load([
          _section(9, [21, 22]),
        ]);
        expect(h.api.reads.single.apiKey, 'successor-key');

        oldKey.complete('retired-key');
        await retired;
        h.owner.invalidate(_site, account: oldLease);
        await h.owner.ensure(_site, account: oldLease);
        expect(h.api.reads, hasLength(1));
        expect(_order(h.sections.single), [21, 22]);
        expect(h.changes, 1);
      },
    );

    test(
      'forget detaches a sent load and its cleanup cannot release a successor load',
      () async {
        final h = _Harness();
        final forgotten = h.owner.ensure(_site);
        await _flush();
        h.owner.forget(_site);
        final successor = h.owner.ensure(_site);
        await _flush();
        expect(h.api.reads, hasLength(2));
        h.api.reads.first.result.complete([
          _section(9, [11, 12]),
        ]);
        await forgotten;
        expect(h.sections, isEmpty);
        expect(h.changes, 0);
        expect(h.owner.ensure(_site), same(successor));
        h.api.reads.last.result.complete([
          _section(9, [21, 22]),
        ]);
        await successor;
        expect(_order(h.sections.single), [21, 22]);
        expect(h.changes, 1);
      },
    );

    for (final duringCredentials in [true, false]) {
      test(
        'dispose suppresses late ${duringCredentials ? 'credentials' : 'HTTP'} work',
        () async {
          final h = _Harness();
          final key = Completer<String?>();
          if (duringCredentials) h.credentials.readKey = () => key.future;
          final loading = h.owner.ensure(_site);
          await _flush();
          h.owner.dispose();
          if (duringCredentials) {
            key.complete('key');
          } else {
            h.api.reads.single.result.completeError(StateError('late failure'));
          }
          await loading;
          await h.owner.ensure(_site);
          expect(h.api.reads, hasLength(duringCredentials ? 0 : 1));
          expect(h.sections, isEmpty);
          expect(h.changes, 0);
        },
      );
    }
  });

  group('custom sidebar writes', () {
    test(
      'reorder sends insertion-gap order and publishes the server response',
      () async {
        final h = _Harness();
        await h.load([
          _section(9, [11, 12, 13]),
          _section(10, [21, 22]),
        ]);
        final untouched = h.sections[1];
        final writing = h.reorder(0, newIndex: 3);
        await _flush();
        expect(h.api.reorders.single.sectionId, 9);
        expect(h.api.reorders.single.order, [12, 13, 11]);
        expect(_order(h.sections[0]), [11, 12, 13]);
        h.api.reorders.single.result.complete(_section(9, [13, 11, 12]));
        await writing;
        expect(_order(h.sections[0]), [13, 11, 12]);
        expect(h.sections[1], same(untouched));
        expect(h.changes, 2);
        expect(h.api.reads, hasLength(1));
        expect(
          () => h.sections[0].destinations.clear(),
          throwsUnsupportedError,
        );
      },
    );

    test(
      'move publishes both returned sections together with one notification',
      () async {
        final h = _Harness();
        await h.load([
          _section(9, [11, 12]),
          _section(10, [21, 22]),
          _section(11, [31, 32]),
        ]);
        final untouched = h.sections[2];
        final writing = h.move();
        await _flush();
        final request = h.api.moves.single;
        expect(request.sourceId, 9);
        expect(request.targetId, 10);
        expect(request.linkId, 11);
        expect(request.position, 1);
        expect(_order(h.sections[0]), [11, 12]);
        expect(_order(h.sections[1]), [21, 22]);
        request.result.complete([
          _section(9, [12]),
          _section(10, [21, 11, 22]),
        ]);
        await writing;
        expect(_order(h.sections[0]), [12]);
        expect(_order(h.sections[1]), [21, 11, 22]);
        expect(h.sections[2], same(untouched));
        expect(h.changes, 2);
        expect(h.api.reads, hasLength(1));
      },
    );

    for (final moving in [false, true]) {
      test(
        'a superseded load cannot overwrite a confirmed ${moving ? 'move' : 'reorder'}',
        () async {
          final h = _Harness();
          await h.load([
            _section(9, [11, 12]),
            _section(10, [21, 22]),
          ]);
          h.owner.invalidate(_site, account: h.lease);
          final superseded = h.owner.ensure(_site);
          await _flush();
          final writing = moving ? h.move() : h.reorder(0);
          await _flush();
          final updated = [
            _section(9, moving ? [12] : [12, 11]),
            _section(10, moving ? [21, 11, 22] : [21, 22]),
          ];
          if (moving) {
            h.api.moves.single.result.complete(updated);
          } else {
            h.api.reorders.single.result.complete(updated[0]);
          }
          await writing;
          await _flush();
          expect(h.api.reads, hasLength(3));
          expect(_order(h.sections[0]), moving ? [12] : [12, 11]);
          h.api.reads[1].result.complete([
            _section(9, [11, 12]),
          ]);
          await superseded;
          expect(_order(h.sections[0]), moving ? [12] : [12, 11]);
          h.api.reads.last.result.complete(updated);
          await h.owner.ensure(_site);
          expect(_order(h.sections[1]), moving ? [21, 11, 22] : [21, 22]);
        },
      );
    }

    test(
      'live events during writes reject stale responses and coalesce one reload',
      () async {
        final h = _Harness();
        await h.load([
          _section(9, [11, 12]),
          _section(10, [21, 22]),
        ]);
        final original = h.sections;
        final first = h.reorder(0);
        final second = h.reorder(1);
        await _flush();
        h.owner.invalidate(_site, account: h.lease);
        h.owner.invalidate(_site, account: h.lease);
        await h.owner.ensure(_site);
        expect(h.api.reads, hasLength(1));
        h.api.reorders[0].result.complete(_section(9, [12, 11]));
        await first;
        expect(h.sections, same(original));
        expect(h.api.reads, hasLength(1));
        h.api.reorders[1].result.complete(_section(10, [22, 21]));
        await second;
        await _flush();
        expect(h.sections, same(original));
        expect(h.changes, 1);
        expect(h.api.reads, hasLength(2));
        h.api.reads.last.result.complete([
          _section(9, [13, 11]),
          _section(10, [23, 21]),
        ]);
        await h.owner.ensure(_site);
        expect(_order(h.sections[0]), [13, 11]);
        expect(_order(h.sections[1]), [23, 21]);
        expect(h.changes, 2);
        expect(h.api.reads, hasLength(2));
      },
    );

    for (final moving in [false, true]) {
      test(
        'live invalidation during ${moving ? 'move' : 'reorder'} credentials cancels dispatch and drains one reload',
        () async {
          final h = _Harness();
          await h.load([
            _section(9, [11, 12]),
            _section(10, [21, 22]),
          ]);
          final key = Completer<String?>();
          h.credentials.readKey = () => key.future;
          final writing = moving ? h.move() : h.reorder(0);
          h.owner.invalidate(_site, account: h.lease);
          h.owner.invalidate(_site, account: h.lease);
          await h.owner.ensure(_site);
          h.credentials.readKey = null;
          key.complete('key');
          await writing;
          await _flush();
          expect(h.api.reorders, isEmpty);
          expect(h.api.moves, isEmpty);
          expect(h.api.reads, hasLength(2));
          h.api.reads.last.result.complete([
            _section(9, [13, 14]),
            _section(10, [23, 24]),
          ]);
          await h.owner.ensure(_site);
          expect(_order(h.sections[0]), [13, 14]);
          expect(_order(h.sections[1]), [23, 24]);
          expect(h.changes, 2);
        },
      );
    }

    test(
      'a deferred reload waits for reselection without inheriting a cooldown',
      () async {
        final h = _Harness();
        await h.load([
          _section(9, [11, 12]),
        ]);
        final writing = h.reorder(0);
        await _flush();
        h.owner.invalidate(_site, account: h.lease);
        h.selected = _otherSite;
        h.api.reorders.single.result.complete(_section(9, [12, 11]));
        await writing;
        await _flush();
        expect(h.api.reads, hasLength(1));
        expect(_order(h.sections.single), [11, 12]);
        h.selected = _site;
        final loading = h.owner.ensure(_site);
        await _flush();
        expect(h.api.reads, hasLength(2));
        h.api.reads.last.result.complete([
          _section(9, [13, 14]),
        ]);
        await loading;
        expect(_order(h.sections.single), [13, 14]);
      },
    );

    test(
      'a failed write still drains an independently pending live reload',
      () async {
        final h = _Harness();
        await h.load([
          _section(9, [11, 12]),
        ]);
        final writing = h.reorder(0);
        final failure = StateError('write failed');
        final failed = expectLater(writing, throwsA(same(failure)));
        await _flush();
        h.owner.invalidate(_site, account: h.lease);
        h.api.reorders.single.result.completeError(failure);
        await failed;
        await _flush();
        expect(h.api.reorders, hasLength(1));
        expect(h.api.reads, hasLength(2));
        h.api.reads.last.result.complete([
          _section(9, [13, 14]),
        ]);
        await h.owner.ensure(_site);
        expect(_order(h.sections.single), [13, 14]);
        expect(h.changes, 2);
      },
    );

    test(
      'disjoint writes merge and overlapping reorder and move are suppressed',
      () async {
        final h = _Harness();
        await h.load([
          _section(9, [11, 12]),
          _section(10, [21, 22]),
          _section(11, [31, 32]),
        ]);
        final untouched = h.sections[2];
        final first = h.reorder(0);
        final second = h.reorder(1);
        await h.reorder(0);
        await h.owner.move(
          siteUrl: _site,
          source: h.sections[2],
          target: h.sections[0],
          oldIndex: 0,
          newIndex: 0,
        );
        await _flush();
        expect(h.api.reorders, hasLength(2));
        expect(h.api.moves, isEmpty);
        h.api.reorders[1].result.complete(_section(10, [22, 21]));
        await second;
        expect(_order(h.sections[0]), [11, 12]);
        expect(_order(h.sections[1]), [22, 21]);
        final confirmedSecond = h.sections[1];
        h.api.reorders[0].result.complete(_section(9, [12, 11]));
        await first;
        expect(_order(h.sections[0]), [12, 11]);
        expect(h.sections[1], same(confirmedSecond));
        expect(h.sections[2], same(untouched));
        expect(h.changes, 3);
        expect(h.api.reads, hasLength(1));
      },
    );

    test(
      'move reserves source and target atomically and allows a disjoint reorder',
      () async {
        final h = _Harness();
        await h.load([
          _section(9, [11, 12]),
          _section(10, [21, 22]),
          _section(11, [31, 32]),
        ]);
        final moving = h.move();
        await h.reorder(0);
        await h.reorder(1);
        final disjoint = h.reorder(2);
        await _flush();
        expect(h.api.moves, hasLength(1));
        expect(h.api.reorders.single.sectionId, 11);
        h.api.reorders.single.result.complete(_section(11, [32, 31]));
        await disjoint;
        h.api.moves.single.result.complete([
          _section(9, [12]),
          _section(10, [21, 11, 22]),
        ]);
        await moving;
        expect(_order(h.sections[0]), [12]);
        expect(_order(h.sections[1]), [21, 11, 22]);
        expect(_order(h.sections[2]), [32, 31]);
        expect(h.changes, 3);
      },
    );

    test(
      'old write cleanup cannot release a successor lock or reload its account',
      () async {
        final h = _Harness();
        await h.load([
          _section(9, [11, 12]),
        ]);
        final retired = h.reorder(0);
        await _flush();
        h.owner.invalidate(_site, account: h.lease);
        h.lifecycle.invalidate(_site);
        h.credentials.key = 'successor-key';
        await h.load([
          _section(9, [21, 22]),
        ]);
        final successor = h.reorder(0);
        await _flush();
        expect(h.api.reorders.last.apiKey, 'successor-key');
        h.api.reorders.first.result.complete(_section(9, [12, 11]));
        await retired;
        await h.reorder(0);
        expect(h.api.reorders, hasLength(2));
        expect(h.api.reads, hasLength(2));
        expect(_order(h.sections.single), [21, 22]);
        h.api.reorders.last.result.complete(_section(9, [22, 21]));
        await successor;
        expect(_order(h.sections.single), [22, 21]);
        expect(h.changes, 3);
      },
    );

    test(
      'retirement while write credentials wait sends no request for either account',
      () async {
        final h = _Harness();
        await h.load([
          _section(9, [11, 12]),
        ]);
        final key = Completer<String?>();
        h.credentials.readKey = () => key.future;
        final retired = h.reorder(0);
        h.lifecycle.invalidate(_site);
        h.credentials.readKey = null;
        h.credentials.key = 'successor-key';
        await h.load([
          _section(9, [21, 22]),
        ]);
        key.complete('old-key');
        await retired;
        expect(h.api.reorders, isEmpty);
        final successor = h.reorder(0);
        await _flush();
        expect(h.api.reorders.single.apiKey, 'successor-key');
        h.api.reorders.single.result.complete(_section(9, [22, 21]));
        await successor;
        expect(_order(h.sections.single), [22, 21]);
      },
    );

    test(
      'write failure propagates, unlocks, and permits an explicit retry',
      () async {
        final h = _Harness();
        await h.load([
          _section(9, [11, 12]),
        ]);
        final writing = h.reorder(0);
        final failure = StateError('write failed');
        final failed = expectLater(writing, throwsA(same(failure)));
        await _flush();
        h.api.reorders.single.result.completeError(failure);
        await failed;
        expect(_order(h.sections.single), [11, 12]);
        expect(h.api.reorders, hasLength(1));
        expect(h.api.reads, hasLength(1));
        expect(h.changes, 1);
        final retry = h.reorder(0);
        await _flush();
        expect(h.api.reorders, hasLength(2));
        h.api.reorders.last.result.complete(_section(9, [12, 11]));
        await retry;
        expect(_order(h.sections.single), [12, 11]);
      },
    );

    for (final moving in [false, true]) {
      test(
        'a missing ${moving ? 'move' : 'reorder'} key is forbidden and releases its reservations',
        () async {
          final h = _Harness();
          await h.load([
            _section(9, [11, 12]),
            _section(10, [21, 22]),
          ]);
          h.credentials.key = null;
          await expectLater(
            moving ? h.move() : h.reorder(0),
            throwsA(
              isA<WriteException>().having(
                (error) => error.failure,
                'failure',
                WriteFailure.forbidden,
              ),
            ),
          );
          expect(h.api.moves, isEmpty);
          expect(h.api.reorders, isEmpty);
          h.credentials.key = 'key';
          final retry = moving ? h.move() : h.reorder(0);
          await _flush();
          if (moving) {
            expect(h.api.moves, hasLength(1));
            h.api.moves.single.result.complete([
              _section(9, [12]),
              _section(10, [21, 11, 22]),
            ]);
          } else {
            expect(h.api.reorders, hasLength(1));
            h.api.reorders.single.result.complete(_section(9, [12, 11]));
          }
          await retry;
          expect(_order(h.sections[0]), moving ? [12] : [12, 11]);
        },
      );
    }

    test(
      'permissions are checked again after write credentials settle',
      () async {
        final h = _Harness(admin: true);
        await h.load([
          _section(9, [11, 12], public: true),
        ]);
        final key = Completer<String?>();
        h.credentials.readKey = () => key.future;
        final writing = h.reorder(0);
        h.instance = h.instance.copyWith(
          user: const DiscourseUser(id: 7, username: 'reader'),
        );
        key.complete('key');
        await writing;
        expect(h.api.reorders, isEmpty);
        expect(_order(h.sections.single), [11, 12]);
      },
    );

    test(
      'invalid indices, no-ops, stale membership, and full targets send no writes',
      () async {
        final h = _Harness();
        await h.load([
          _section(9, [11, 12]),
          _section(
            10,
            List.generate(SidebarSection.maximumCustomLinks, (i) => 100 + i),
          ),
        ]);
        final stale = _section(9, [11, 12]);
        for (final indices in [
          (-1, 1),
          (2, 0),
          (0, -1),
          (0, 3),
          (0, 0),
          (0, 1),
        ]) {
          await h.reorder(0, oldIndex: indices.$1, newIndex: indices.$2);
        }
        await h.owner.reorder(
          siteUrl: _site,
          section: stale,
          oldIndex: 0,
          newIndex: 2,
        );
        await h.move();
        await h.owner.move(
          siteUrl: _site,
          source: h.sections[0],
          target: h.sections[0],
          oldIndex: 0,
          newIndex: 0,
        );
        expect(h.api.reorders, isEmpty);
        expect(h.api.moves, isEmpty);
        expect(h.credentials.keyReads, 1);
      },
    );

    test(
      'connected users edit private sections and only admins edit public sections',
      () async {
        final h = _Harness();
        await h.load([
          _section(9, [11, 12]),
          _section(10, [21, 22], public: true),
        ]);
        expect(h.owner.canEdit(_site, h.sections[0]), isTrue);
        expect(h.owner.canReorder(_site, h.sections[0]), isTrue);
        expect(h.owner.canEdit(_site, h.sections[1]), isFalse);
        await h.reorder(1);
        await h.move();
        expect(h.api.reorders, isEmpty);
        expect(h.api.moves, isEmpty);

        h.instance = h.instance.copyWith(
          user: const DiscourseUser(id: 7, username: 'admin', admin: true),
        );
        expect(h.owner.canEdit(_site, h.sections[1]), isTrue);
        final writing = h.reorder(1);
        await _flush();
        h.api.reorders.single.result.complete(
          _section(10, [22, 21], public: true),
        );
        await writing;
        expect(
          h.owner.canEdit(
            _site,
            const SidebarSection(
              id: 'builtin',
              title: 'Built in',
              destinations: [],
            ),
          ),
          isFalse,
        );
        expect(h.owner.canReorder(_site, _section(11, [31])), isFalse);
        h.instance = h.instance.copyWith(clearUser: true);
        expect(h.owner.canEdit(_site, h.sections[0]), isFalse);
        await h.reorder(0);
        await h.move();
        expect(h.api.reorders, hasLength(1));
        expect(h.api.moves, isEmpty);
      },
    );
  });
}
