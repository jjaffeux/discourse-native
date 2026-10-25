import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/plugin_transport.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/user_directory_api.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/user_directory.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/shell/user_directory_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const defaultQuery = UserDirectoryQuery();

  group('explicit metadata refresh', () {
    const site = DiscourseInstance(
      url: 'https://example.com',
      title: 'Example',
      user: DiscourseUser(username: 'admin', staff: true),
    );
    const otherQuery = UserDirectoryQuery(search: 'other');
    late _ControllerTransport transport;
    late UserDirectoryController controller;

    setUp(() {
      transport = _ControllerTransport();
      controller = UserDirectoryController(
        api: UserDirectoryApi(transport, const DiscourseModelCodec.core()),
        credentials: const _Credentials(),
        lifecycle: SiteLifecycle(),
      );
      addTearDown(controller.dispose);
    });

    void enableCustomColumn() {
      transport.columnEnabled[1] = false;
      transport.columnEnabled[14] = true;
    }

    List<Uri> rowRequests() => [
      for (final path in transport.requests)
        if (path.startsWith('/directory_items.json')) Uri.parse(path),
    ];

    test(
      'reloads columns and field IDs while ordinary loads share metadata',
      () async {
        await controller.load(site, query: defaultQuery);
        await controller.load(site, query: otherQuery);
        await controller.load(site, query: otherQuery, more: true);
        enableCustomColumn();

        await controller.load(site, query: defaultQuery, refresh: true);

        expect(
          controller.stateFor(site.url, defaultQuery).columns.map((c) => c.id),
          [14],
        );
        expect(rowRequests().last.queryParameters['user_field_ids'], '42');
        final stale = controller.stateFor(site.url, otherQuery);
        expect(stale.loaded, isFalse);
        expect(stale.loading, isFalse);
        expect(stale.columns.map((c) => c.id), [14]);
        await controller.load(site, query: otherQuery);
        expect(rowRequests().last.queryParameters['page'], isNull);
        expect(rowRequests().last.queryParameters['user_field_ids'], '42');
        await controller.load(site, query: otherQuery, more: true);
        expect(rowRequests().last.queryParameters['page'], '1');
        expect(
          transport.requests.where((p) => p == '/edit-directory-columns.json'),
          hasLength(2),
        );
      },
    );

    for (final fails in [false, true]) {
      test(
        'superseded metadata ${fails ? 'failure' : 'success'} joins refreshed metadata',
        () async {
          final started = Completer<void>();
          final oldMetadata = Completer<Map<String, dynamic>>();
          transport.nextColumns = () {
            started.complete();
            return oldMetadata.future;
          };
          final oldLoad = controller.load(site, query: defaultQuery);
          await started.future;
          enableCustomColumn();
          await controller.load(site, query: otherQuery, refresh: true);
          if (fails) {
            oldMetadata.completeError(StateError('old metadata'));
          } else {
            oldMetadata.complete(const {
              'directory_columns': [
                {'id': 1, 'name': 'likes_received', 'type': 'automatic'},
              ],
            });
          }
          await oldLoad;
          for (final query in [defaultQuery, otherQuery]) {
            final state = controller.stateFor(site.url, query);
            expect(state.columns.map((c) => c.id), [14]);
            expect(state.loaded, isTrue);
            expect(state.loading, isFalse);
            expect(state.error, isNull);
          }
          expect(rowRequests(), hasLength(2));
          expect(
            rowRequests().every(
              (uri) => uri.queryParameters['user_field_ids'] == '42',
            ),
            isTrue,
          );
        },
      );

      test(
        'superseded page ${fails ? 'failure' : 'success'} restarts at page zero',
        () async {
          await controller.load(site, query: defaultQuery);
          final started = Completer<void>();
          final oldRows = Completer<void>();
          transport.beforeDirectoryReply = (uri) async {
            if (started.isCompleted || uri.queryParameters['page'] != '1')
              return;
            started.complete();
            await oldRows.future;
            if (fails) throw StateError('old rows');
          };
          final oldLoad = controller.load(
            site,
            query: defaultQuery,
            more: true,
          );
          await started.future;
          enableCustomColumn();
          await controller.load(site, query: otherQuery, refresh: true);
          oldRows.complete();
          await oldLoad;

          final state = controller.stateFor(site.url, defaultQuery);
          expect(state.columns.map((c) => c.id), [14]);
          expect(state.items.map((item) => item.user.username), [
            'sam',
            'hawk',
          ]);
          expect(state.nextPage, 1);
          expect(state.loadingMore, isFalse);
          expect(state.error, isNull);
          expect(rowRequests().last.queryParameters['page'], isNull);
          expect(rowRequests().last.queryParameters['user_field_ids'], '42');
        },
      );
    }

    test('concurrent queries share the pending refreshed metadata', () async {
      await controller.load(site, query: defaultQuery);
      enableCustomColumn();
      final started = Completer<void>();
      final metadata = Completer<Map<String, dynamic>>();
      transport.nextColumns = () {
        started.complete();
        return metadata.future;
      };
      final refresh = controller.load(site, query: defaultQuery, refresh: true);
      await started.future;
      final other = controller.load(site, query: otherQuery);
      await pumpEventQueue();
      expect(
        transport.requests.where((p) => p == '/edit-directory-columns.json'),
        hasLength(2),
      );
      metadata.complete(const {
        'directory_columns': [
          {
            'id': 14,
            'name': 'GitHub Username',
            'type': 'user_field',
            'user_field_id': 42,
          },
        ],
      });
      await Future.wait([refresh, other]);
      for (final query in [defaultQuery, otherQuery]) {
        final state = controller.stateFor(site.url, query);
        expect(state.loaded, isTrue);
        expect(state.columns.single.id, 14);
      }
      expect(
        rowRequests()
            .skip(1)
            .every((uri) => uri.queryParameters['user_field_ids'] == '42'),
        isTrue,
      );
    });

    test(
      'metadata failure retains coherent rows and an explicit retry recovers',
      () async {
        await controller.load(site, query: defaultQuery);
        final held = controller.stateFor(site.url, defaultQuery);
        transport.columnsError = StateError('metadata unavailable');
        enableCustomColumn();
        await controller.load(site, query: defaultQuery, refresh: true);
        final failed = controller.stateFor(site.url, defaultQuery);
        expect(failed.items, held.items);
        expect(failed.columns.map((c) => c.id), [1]);
        expect(failed.error, isNotNull);
        expect(failed.loading, isFalse);
        expect(rowRequests(), hasLength(1));
        transport.columnsError = null;
        await controller.load(site, query: defaultQuery, refresh: true);
        final recovered = controller.stateFor(site.url, defaultQuery);
        expect(recovered.columns.single.id, 14);
        expect(recovered.error, isNull);
        expect(rowRequests().last.queryParameters['user_field_ids'], '42');
      },
    );

    test(
      'row refresh failure retains old columns and later paging restarts',
      () async {
        await controller.load(site, query: defaultQuery);
        await controller.load(site, query: defaultQuery, more: true);
        enableCustomColumn();
        transport.beforeDirectoryReply = (_) async =>
            throw StateError('rows unavailable');
        await controller.load(site, query: defaultQuery, refresh: true);
        final failed = controller.stateFor(site.url, defaultQuery);
        expect(failed.columns.single.id, 1);
        expect(failed.items, hasLength(3));
        expect(failed.error, isNotNull);
        transport.beforeDirectoryReply = null;
        await controller.load(site, query: defaultQuery, more: true);
        final recovered = controller.stateFor(site.url, defaultQuery);
        expect(recovered.columns.single.id, 14);
        expect(recovered.items, hasLength(2));
        expect(recovered.nextPage, 1);
        expect(rowRequests().last.queryParameters['page'], isNull);
        expect(rowRequests().last.queryParameters['user_field_ids'], '42');
      },
    );

    test('acknowledged column writes supersede a pending refresh', () async {
      await controller.load(site, query: defaultQuery);
      final columns = controller
          .stateFor(site.url, defaultQuery)
          .availableColumns;
      final started = Completer<void>();
      final oldMetadata = Completer<Map<String, dynamic>>();
      transport.nextColumns = () {
        started.complete();
        return oldMetadata.future;
      };
      final refresh = controller.load(site, query: defaultQuery, refresh: true);
      await started.future;
      expect(
        await controller.updateColumns(site, [
          for (final column in columns)
            column.copyWith(enabled: column.id == 14),
        ], query: defaultQuery),
        isTrue,
      );
      oldMetadata.complete(const {
        'directory_columns': [
          {'id': 1, 'name': 'likes_received', 'type': 'automatic'},
        ],
      });
      await refresh;
      final state = controller.stateFor(site.url, defaultQuery);
      expect(state.columns.single.id, 14);
      expect(state.error, isNull);
      expect(controller.updatingColumnsFor(site.url), isFalse);
      expect(rowRequests().last.queryParameters['user_field_ids'], '42');
    });

    test(
      'retired refresh cannot restore columns in a replacement account',
      () async {
        await controller.load(site, query: defaultQuery);
        final started = Completer<void>();
        final oldMetadata = Completer<Map<String, dynamic>>();
        transport.nextColumns = () {
          started.complete();
          return oldMetadata.future;
        };
        final refresh = controller.load(
          site,
          query: defaultQuery,
          refresh: true,
        );
        await started.future;
        controller.lifecycle.invalidate(site.url);
        enableCustomColumn();
        await controller.load(site, query: defaultQuery);
        oldMetadata.completeError(StateError('retired metadata'));
        await refresh;
        final state = controller.stateFor(site.url, defaultQuery);
        expect(state.columns.single.id, 14);
        expect(state.loaded, isTrue);
        expect(state.error, isNull);
      },
    );
  });

  for (final dispose in [false, true]) {
    test(
      'a ${dispose ? 'disposed' : 'forgotten'} directory does not start metadata after credential lookup',
      () async {
        final transport = _ControllerTransport();
        final controller = UserDirectoryController(
          api: UserDirectoryApi(transport, const DiscourseModelCodec.core()),
          credentials: const _Credentials(),
          lifecycle: SiteLifecycle(),
        );
        const instance = DiscourseInstance(
          url: 'https://example.com',
          title: 'Example',
        );

        final loading = controller.load(instance, query: defaultQuery);
        if (dispose) {
          controller.dispose();
        } else {
          addTearDown(controller.dispose);
          controller.forget(instance.url);
        }
        await loading;

        expect(transport.requests, isEmpty);
        expect(
          controller.stateFor(instance.url, defaultQuery).columns,
          isEmpty,
        );
      },
    );
  }

  test('an immediate account replacement owns its metadata request', () async {
    final transport = _ControllerTransport();
    final lifecycle = SiteLifecycle();
    final controller = UserDirectoryController(
      api: UserDirectoryApi(transport, const DiscourseModelCodec.core()),
      credentials: const _Credentials(),
      lifecycle: lifecycle,
    );
    addTearDown(controller.dispose);
    const instance = DiscourseInstance(
      url: 'https://example.com',
      title: 'Example',
    );

    final signedOut = controller.load(instance, query: defaultQuery);
    lifecycle.invalidate(instance.url);
    final signedIn = controller.load(
      instance.copyWith(
        user: const DiscourseUser(username: 'admin', staff: true),
      ),
      query: defaultQuery,
    );
    await Future.wait([signedOut, signedIn]);

    final state = controller.stateFor(instance.url, defaultQuery);
    expect(state.loaded, isTrue);
    expect(state.canManageColumns, isTrue);
    expect(transport.requests, isNot(contains('/directory-columns.json')));
    expect(transport.requests.first, '/edit-directory-columns.json');
  });

  test('loads, paginates, and forgets per-site query state', () async {
    final transport = _ControllerTransport();
    final controller = UserDirectoryController(
      api: UserDirectoryApi(transport, const DiscourseModelCodec.core()),
      credentials: const _Credentials(),
      lifecycle: SiteLifecycle(),
    );
    addTearDown(controller.dispose);
    const instance = DiscourseInstance(
      url: 'https://example.com',
      title: 'Example',
      user: DiscourseUser(username: 'reader', groups: ['staff']),
    );

    await controller.load(instance, query: defaultQuery);

    var state = controller.stateFor(instance.url, defaultQuery);
    expect(state.loaded, isTrue);
    expect(state.items.map((item) => item.user.username), ['sam', 'hawk']);
    expect(state.columns.single.name, 'likes_received');
    expect(state.groupNames, ['design']);
    expect(state.totalRows, 75);
    expect(state.hasMore, isTrue);

    await controller.load(instance, query: defaultQuery, more: true);
    state = controller.stateFor(instance.url, defaultQuery);
    expect(state.items.map((item) => item.user.username), [
      'sam',
      'hawk',
      'lindsey',
    ]);
    expect(state.nextPage, 2);

    const query = UserDirectoryQuery(
      period: UserDirectoryPeriod.monthly,
      search: 'sam',
      order: 'username',
      ascending: true,
    );
    await controller.load(instance, query: query);
    final uri = Uri.parse(
      transport.requests.lastWhere(
        (path) => path.startsWith('/directory_items.json'),
      ),
    );
    expect(uri.queryParameters['period'], 'monthly');
    expect(uri.queryParameters['name'], 'sam');
    expect(uri.queryParameters['asc'], 'true');
    expect(
      transport.requests.where((path) => path == '/directory-columns.json'),
      hasLength(1),
    );

    controller.forget(instance.url);
    expect(controller.stateFor(instance.url, defaultQuery).loaded, isFalse);
    expect(controller.stateFor(instance.url, query).loaded, isFalse);
  });

  test(
    'concurrent queries keep separate results and deduplicate identical loads',
    () async {
      final transport = _ControllerTransport()
        ..usernamesBySearch.addAll({
          'sam': ['sam'],
          'hawk': ['hawk'],
        });
      final controller = UserDirectoryController(
        api: UserDirectoryApi(transport, const DiscourseModelCodec.core()),
        credentials: const _Credentials(),
        lifecycle: SiteLifecycle(),
      );
      addTearDown(controller.dispose);
      const instance = DiscourseInstance(
        url: 'https://example.com',
        title: 'Example',
      );
      const firstQuery = UserDirectoryQuery(search: 'sam');
      const secondQuery = UserDirectoryQuery(search: 'hawk');
      final started = {'sam': Completer<void>(), 'hawk': Completer<void>()};
      final replies = {'sam': Completer<void>(), 'hawk': Completer<void>()};
      addTearDown(() {
        for (final reply in replies.values) {
          if (!reply.isCompleted) reply.complete();
        }
      });
      transport.beforeDirectoryReply = (uri) async {
        final search = uri.queryParameters['name'];
        started[search]!.complete();
        await replies[search]!.future;
      };

      final first = controller.load(instance, query: firstQuery);
      final second = controller.load(instance, query: secondQuery);
      await Future.wait(started.values.map((start) => start.future));
      expect(controller.stateFor(instance.url, firstQuery).loading, isTrue);
      expect(controller.stateFor(instance.url, secondQuery).loading, isTrue);

      await controller.load(
        instance,
        query: UserDirectoryQuery(search: firstQuery.search),
      );
      expect(
        transport.requests.where(
          (path) => path.startsWith('/directory_items.json'),
        ),
        hasLength(2),
      );
      expect(
        transport.requests.where((path) => path == '/directory-columns.json'),
        hasLength(1),
      );

      replies['sam']!.complete();
      await first;
      expect(
        controller
            .stateFor(instance.url, firstQuery)
            .items
            .map((item) => item.user.username),
        ['sam'],
      );
      expect(controller.stateFor(instance.url, secondQuery).items, isEmpty);
      expect(controller.stateFor(instance.url, secondQuery).loading, isTrue);

      replies['hawk']!.complete();
      await second;
      expect(
        controller
            .stateFor(instance.url, secondQuery)
            .items
            .map((item) => item.user.username),
        ['hawk'],
      );
      expect(
        controller
            .stateFor(instance.url, firstQuery)
            .items
            .map((item) => item.user.username),
        ['sam'],
      );
    },
  );

  test(
    'bounds directory history per forum and retains recently loaded queries',
    () async {
      final transport = _ControllerTransport();
      final controller = UserDirectoryController(
        api: UserDirectoryApi(transport, const DiscourseModelCodec.core()),
        credentials: const _Credentials(),
        lifecycle: SiteLifecycle(),
      );
      addTearDown(controller.dispose);
      const site = DiscourseInstance(
        url: 'https://example.com',
        title: 'Example',
      );
      const other = DiscourseInstance(
        url: 'https://another.example',
        title: 'Other',
      );
      await controller.load(other, query: defaultQuery);
      for (var index = 0; index < 16; index++) {
        await controller.load(
          site,
          query: UserDirectoryQuery(search: 'query-$index'),
        );
      }
      final requestsBeforeRevisit = transport.requests.length;
      await controller.load(
        site,
        query: const UserDirectoryQuery(search: 'query-0'),
      );
      expect(transport.requests.length, requestsBeforeRevisit);

      await controller.load(
        site,
        query: const UserDirectoryQuery(search: 'query-16'),
      );

      expect(
        controller
            .stateFor(site.url, const UserDirectoryQuery(search: 'query-0'))
            .loaded,
        isTrue,
      );
      expect(
        controller
            .stateFor(site.url, const UserDirectoryQuery(search: 'query-1'))
            .loaded,
        isFalse,
      );
      expect(controller.stateFor(other.url, defaultQuery).loaded, isTrue);
      await controller.load(
        site,
        query: const UserDirectoryQuery(search: 'query-1'),
      );
      expect(transport.requests.length, requestsBeforeRevisit + 2);
      expect(
        Uri.parse(transport.requests.last).queryParameters['name'],
        'query-1',
      );
    },
  );

  for (final replaces in [false, true]) {
    test(
      'evicted directory replies cannot ${replaces ? 'finish a replacement load' : 'repopulate the cache'}',
      () async {
        final transport = _ControllerTransport();
        final controller = UserDirectoryController(
          api: UserDirectoryApi(transport, const DiscourseModelCodec.core()),
          credentials: const _Credentials(),
          lifecycle: SiteLifecycle(),
        );
        addTearDown(controller.dispose);
        const site = DiscourseInstance(
          url: 'https://example.com',
          title: 'Example',
        );
        const originalQuery = UserDirectoryQuery(search: 'original');
        final oldStarted = Completer<void>();
        final oldReply = Completer<void>();
        final replacementStarted = Completer<void>();
        final replacementReply = Completer<void>();
        addTearDown(() {
          if (!oldReply.isCompleted) oldReply.complete();
          if (!replacementReply.isCompleted) replacementReply.complete();
        });
        transport.beforeDirectoryReply = (uri) async {
          if (uri.queryParameters['name'] != 'original') return;
          if (!oldStarted.isCompleted) {
            oldStarted.complete();
            await oldReply.future;
          } else {
            replacementStarted.complete();
            await replacementReply.future;
          }
        };
        final old = controller.load(site, query: originalQuery);
        await oldStarted.future;
        for (var index = 0; index < 16; index++) {
          await controller.load(
            site,
            query: UserDirectoryQuery(search: 'query-$index'),
          );
        }
        expect(controller.stateFor(site.url, originalQuery).loading, isFalse);

        Future<void>? replacement;
        if (replaces) {
          replacement = controller.load(site, query: originalQuery);
          await replacementStarted.future;
        }
        oldReply.complete();
        await old;
        expect(controller.stateFor(site.url, originalQuery).loaded, isFalse);
        expect(controller.stateFor(site.url, originalQuery).loading, replaces);
        if (replacement != null) {
          final requestsBeforeDuplicate = transport.requests.length;
          await controller.load(site, query: originalQuery);
          expect(transport.requests.length, requestsBeforeDuplicate);
          replacementReply.complete();
          await replacement;
          expect(controller.stateFor(site.url, originalQuery).loaded, isTrue);
        }
      },
    );
  }

  test(
    'retirement clears rows and shared metadata without forgetting',
    () async {
      final transport = _ControllerTransport();
      final lifecycle = SiteLifecycle();
      final controller = UserDirectoryController(
        api: UserDirectoryApi(transport, const DiscourseModelCodec.core()),
        credentials: const _Credentials(),
        lifecycle: lifecycle,
      );
      addTearDown(controller.dispose);
      const site = DiscourseInstance(
        url: 'https://example.com',
        title: 'Example',
        user: DiscourseUser(username: 'admin', staff: true),
      );
      await controller.load(site, query: defaultQuery);
      lifecycle.invalidate(site.url);
      const otherQuery = UserDirectoryQuery(search: 'other');
      for (final query in [defaultQuery, otherQuery]) {
        final state = controller.stateFor(site.url, query);
        expect(state.items, isEmpty);
        expect(state.columns, isEmpty);
        expect(state.groupNames, isEmpty);
        expect(state.canManageColumns, isFalse);
        expect(state.loaded, isFalse);
      }
      await controller.load(site, query: defaultQuery);
      expect(controller.stateFor(site.url, defaultQuery).loaded, isTrue);
      expect(
        transport.requests.where(
          (path) => path == '/edit-directory-columns.json',
        ),
        hasLength(2),
      );
    },
  );

  test(
    'old metadata failure cannot release successor metadata or query',
    () async {
      final transport = _ControllerTransport();
      final lifecycle = SiteLifecycle();
      final controller = UserDirectoryController(
        api: UserDirectoryApi(transport, const DiscourseModelCodec.core()),
        credentials: const _Credentials(),
        lifecycle: lifecycle,
      );
      addTearDown(controller.dispose);
      const site = DiscourseInstance(
        url: 'https://example.com',
        title: 'Example',
      );
      final oldStarted = Completer<void>();
      final oldMetadata = Completer<Map<String, dynamic>>();
      transport.nextColumns = () {
        oldStarted.complete();
        return oldMetadata.future;
      };
      final former = controller.load(site, query: defaultQuery);
      await oldStarted.future;
      lifecycle.invalidate(site.url);
      final newStarted = Completer<void>();
      final newMetadata = Completer<Map<String, dynamic>>();
      transport.nextColumns = () {
        newStarted.complete();
        return newMetadata.future;
      };
      final replacement = controller.load(site, query: defaultQuery);
      await newStarted.future;
      oldMetadata.completeError(StateError('former metadata'));
      await former;
      expect(controller.stateFor(site.url, defaultQuery).loading, isTrue);
      expect(controller.stateFor(site.url, defaultQuery).error, isNull);
      await controller.load(site, query: defaultQuery);
      const other = UserDirectoryQuery(search: 'other');
      final concurrent = controller.load(site, query: other);
      await pumpEventQueue();
      expect(transport.requests, hasLength(2));
      newMetadata.complete(const {
        'directory_columns': [
          {'id': 1, 'name': 'likes_received', 'type': 'automatic'},
        ],
      });
      await Future.wait([replacement, concurrent]);
      expect(controller.stateFor(site.url, defaultQuery).loaded, isTrue);
      expect(controller.stateFor(site.url, other).loaded, isTrue);
    },
  );

  test('staff can load and update the complete column configuration', () async {
    final transport = _ControllerTransport();
    final controller = UserDirectoryController(
      api: UserDirectoryApi(transport, const DiscourseModelCodec.core()),
      credentials: const _Credentials(),
      lifecycle: SiteLifecycle(),
    );
    addTearDown(controller.dispose);
    const instance = DiscourseInstance(
      url: 'https://example.com',
      title: 'Example',
      user: DiscourseUser(username: 'admin', staff: true),
    );

    await controller.load(instance, query: defaultQuery);

    var state = controller.stateFor(instance.url, defaultQuery);
    expect(state.canManageColumns, isTrue);
    expect(state.columns.map((column) => column.name), ['likes_received']);
    expect(state.availableColumns.map((column) => column.name), [
      'likes_received',
      'solutions',
      'GitHub Username',
    ]);
    expect(
      transport.requests.where(
        (path) => path == '/edit-directory-columns.json',
      ),
      hasLength(1),
    );

    final update = controller.updateColumns(instance, [
      for (final column in state.availableColumns)
        column.name == 'solutions' ? column.copyWith(enabled: true) : column,
    ], query: defaultQuery);
    expect(controller.updatingColumnsFor(instance.url), isTrue);
    expect(await update, isTrue);
    expect(controller.updatingColumnsFor(instance.url), isFalse);

    state = controller.stateFor(instance.url, defaultQuery);
    expect(state.columns.map((column) => column.name), [
      'likes_received',
      'solutions',
    ]);
    expect(transport.writes.single.path, '/edit-directory-columns.json');
  });

  test(
    'retired column update cannot clear successor metadata or update ticket',
    () async {
      final transport = _ControllerTransport();
      final lifecycle = SiteLifecycle();
      final controller = UserDirectoryController(
        api: UserDirectoryApi(transport, const DiscourseModelCodec.core()),
        credentials: const _Credentials(),
        lifecycle: lifecycle,
      );
      addTearDown(controller.dispose);
      const site = DiscourseInstance(
        url: 'https://example.com',
        title: 'Example',
        user: DiscourseUser(username: 'admin', staff: true),
      );
      await controller.load(site, query: defaultQuery);
      final columns = controller
          .stateFor(site.url, defaultQuery)
          .availableColumns;
      final oldStarted = Completer<void>();
      final oldReply = Completer<void>();
      transport.beforeWriteReply = () {
        oldStarted.complete();
        return oldReply.future;
      };
      final former = controller.updateColumns(
        site,
        columns,
        query: defaultQuery,
      );
      await oldStarted.future;
      lifecycle.invalidate(site.url);
      expect(controller.updatingColumnsFor(site.url), isFalse);
      await controller.load(site, query: defaultQuery);
      final newStarted = Completer<void>();
      final newReply = Completer<void>();
      transport.beforeWriteReply = () {
        newStarted.complete();
        return newReply.future;
      };
      final replacement = controller.updateColumns(
        site,
        columns,
        query: defaultQuery,
      );
      await newStarted.future;
      oldReply.complete();
      expect(await former, isFalse);
      expect(controller.stateFor(site.url, defaultQuery).loaded, isTrue);
      expect(controller.updatingColumnsFor(site.url), isTrue);
      expect(
        await controller.updateColumns(site, columns, query: defaultQuery),
        isFalse,
      );
      expect(transport.writes, hasLength(2));
      newReply.complete();
      expect(await replacement, isTrue);
      expect(controller.updatingColumnsFor(site.url), isFalse);
    },
  );

  test(
    'retirement during column publication prevents its follow-up load',
    () async {
      final transport = _ControllerTransport();
      final lifecycle = SiteLifecycle();
      final controller = UserDirectoryController(
        api: UserDirectoryApi(transport, const DiscourseModelCodec.core()),
        credentials: const _Credentials(),
        lifecycle: lifecycle,
      );
      addTearDown(controller.dispose);
      const site = DiscourseInstance(
        url: 'https://example.com',
        title: 'Example',
        user: DiscourseUser(username: 'admin', staff: true),
      );
      await controller.load(site, query: defaultQuery);
      final columns = controller
          .stateFor(site.url, defaultQuery)
          .availableColumns;
      var retired = false;
      controller.addListener(() {
        if (!retired &&
            controller.updatingColumnsFor(site.url) &&
            !controller.stateFor(site.url, defaultQuery).loaded) {
          retired = true;
          lifecycle.invalidate(site.url);
        }
      });
      final requests = transport.requests.length;
      expect(
        await controller.updateColumns(site, columns, query: defaultQuery),
        isFalse,
      );
      expect(retired, isTrue);
      expect(transport.requests.length, requests);
      expect(controller.stateFor(site.url, defaultQuery).loaded, isFalse);
    },
  );

  test('forgotten metadata cannot repopulate a replacement account', () async {
    final transport = _ControllerTransport();
    final metadataStarted = Completer<void>();
    final oldMetadata = Completer<Map<String, dynamic>>();
    transport.nextColumns = () {
      metadataStarted.complete();
      return oldMetadata.future;
    };
    final controller = UserDirectoryController(
      api: UserDirectoryApi(transport, const DiscourseModelCodec.core()),
      credentials: const _Credentials(),
      lifecycle: SiteLifecycle(),
    );
    addTearDown(controller.dispose);
    const instance = DiscourseInstance(
      url: 'https://example.com',
      title: 'Example',
      user: DiscourseUser(username: 'former-account', groups: ['private']),
    );

    final loading = controller.load(instance, query: defaultQuery);
    await metadataStarted.future;
    controller.forget(instance.url);
    oldMetadata.complete(const {
      'directory_columns': [
        {'id': 9, 'name': 'former-column', 'type': 'plugin'},
      ],
    });
    await loading;

    expect(controller.stateFor(instance.url, defaultQuery).columns, isEmpty);
    expect(controller.stateFor(instance.url, defaultQuery).groupNames, isEmpty);
    expect(transport.requests, [
      '/directory-columns.json',
      '/groups/search.json?ignore_automatic=true',
    ]);

    await controller.load(
      instance.copyWith(user: const DiscourseUser(username: 'replacement')),
      query: defaultQuery,
    );
    final replacement = controller.stateFor(instance.url, defaultQuery);
    expect(replacement.columns.map((column) => column.name), [
      'likes_received',
    ]);
    expect(replacement.groupNames, ['design']);
  });

  test('updating columns invalidates cached directory queries', () async {
    final transport = _ControllerTransport();
    final controller = UserDirectoryController(
      api: UserDirectoryApi(transport, const DiscourseModelCodec.core()),
      credentials: const _Credentials(),
      lifecycle: SiteLifecycle(),
    );
    addTearDown(controller.dispose);
    const instance = DiscourseInstance(
      url: 'https://example.com',
      title: 'Example',
      user: DiscourseUser(username: 'admin', staff: true),
    );

    await controller.load(instance, query: defaultQuery);
    const searchQuery = UserDirectoryQuery(search: 'sam');
    await controller.load(instance, query: searchQuery);
    final columns = controller
        .stateFor(instance.url, searchQuery)
        .availableColumns;
    expect(
      await controller.updateColumns(instance, [
        for (final column in columns)
          column.name == 'solutions' ? column.copyWith(enabled: true) : column,
      ], query: searchQuery),
      isTrue,
    );
    expect(controller.stateFor(instance.url, defaultQuery).loaded, isFalse);
    expect(controller.stateFor(instance.url, searchQuery).loaded, isTrue);

    await controller.load(instance, query: defaultQuery);

    expect(
      controller
          .stateFor(instance.url, defaultQuery)
          .columns
          .map((column) => column.name),
      ['likes_received', 'solutions'],
    );
    expect(
      Uri.parse(transport.requests.last).queryParameters['plugin_column_ids'],
      '9',
    );
  });
}

final class _ControllerTransport
    implements PluginApiTransport, PluginJsonListTransport {
  final List<String> requests = [];
  final List<({String path, Map<String, Object?> body})> writes = [];
  final Map<int, bool> columnEnabled = {1: true, 9: false, 14: false};
  final Map<String, List<String>> usernamesBySearch = {};
  Future<Map<String, dynamic>> Function()? nextColumns;
  Object? columnsError;
  Future<void> Function(Uri uri)? beforeDirectoryReply;
  Future<void> Function()? beforeWriteReply;

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    requests.add(path);
    final uri = Uri.parse(path);
    if (columnsError case final error?
        when uri.path == '/directory-columns.json' ||
            uri.path == '/edit-directory-columns.json') {
      throw error;
    }
    if (nextColumns case final load?
        when uri.path == '/directory-columns.json' ||
            uri.path == '/edit-directory-columns.json') {
      nextColumns = null;
      return load();
    }
    if (uri.path == '/edit-directory-columns.json') {
      return {
        'directory_columns': [
          {
            'id': 1,
            'name': 'likes_received',
            'type': 'automatic',
            'position': 1,
            'enabled': columnEnabled[1],
          },
          {
            'id': 9,
            'name': 'solutions',
            'type': 'plugin',
            'position': 2,
            'enabled': columnEnabled[9],
          },
          {
            'id': 14,
            'name': 'GitHub Username',
            'type': 'user_field',
            'position': 3,
            'user_field_id': 42,
            'enabled': columnEnabled[14],
          },
        ],
      };
    }
    if (uri.path == '/directory-columns.json') {
      return const {
        'directory_columns': [
          {
            'id': 1,
            'name': 'likes_received',
            'type': 'automatic',
            'position': 1,
          },
        ],
      };
    }
    await beforeDirectoryReply?.call(uri);
    final page = int.tryParse(uri.queryParameters['page'] ?? '0') ?? 0;
    final usernames = page == 0
        ? usernamesBySearch[uri.queryParameters['name']] ??
              const ['sam', 'hawk']
        : const ['lindsey'];
    return {
      'directory_items': [
        for (var index = 0; index < usernames.length; index++)
          {
            'id': page * 10 + index + 1,
            'likes_received': 100 - index,
            'user': {'id': page * 10 + index + 1, 'username': usernames[index]},
          },
      ],
      'meta': {
        'total_rows_directory_items': 75,
        'last_updated_at': '2026-09-04T07:06:00Z',
        'load_more_directory_items':
            '/directory_items.json?period=weekly&page=${page + 1}',
      },
    };
  }

  @override
  Future<List<Map<String, dynamic>>> pluginGetJsonList({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    requests.add(path);
    return [
      {'id': 4, 'name': 'design', 'can_see_members': true},
    ];
  }

  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) async {
    writes.add((path: path, body: body));
    await beforeWriteReply?.call();
    final configuration = body['directory_columns'];
    if (configuration is Map) {
      for (final value in configuration.values) {
        if (value is Map) {
          final id = value['id'];
          final enabled = value['enabled'];
          if (id is int && enabled is bool) columnEnabled[id] = enabled;
        }
      }
    }
    return const {};
  }
}

final class _Credentials implements ApiCredentialReader {
  const _Credentials();

  @override
  Future<String?> apiKeyFor(String siteUrl) async => 'secret';

  @override
  Future<String> clientId() async => 'client';
}
