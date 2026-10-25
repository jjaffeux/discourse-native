import 'dart:async';

import 'package:discourse_native/src/data/recent_search_store.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/shell/global_search_api.dart';
import 'package:discourse_native/src/shell/global_search_controller.dart';
import 'package:discourse_native/src/shell/global_search_models.dart';
import 'package:discourse_native/src/shell/recent_search_history.dart';
import 'package:discourse_native/src/shell/shell_search_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://example.test';

void main() {
  test(
    'both controllers share history without observing shell presentation',
    () async {
      final rig = _Rig();
      final shell = ShellSearchController(history: rig.history)
        ..selectSite(_site, username: 'reader');
      final global =
          GlobalSearchController(
            api: rig.api,
            credentials: rig.credentials,
            lifecycle: rig.lifecycle,
            history: rig.history,
          )..configure(
            siteUrl: _site,
            capabilities: const GlobalSearchCapabilities(
              authenticated: true,
              username: 'reader',
            ),
          );
      addTearDown(shell.dispose);
      addTearDown(global.dispose);
      await pumpEventQueue();
      var changes = 0;
      global.addListener(() => changes++);
      shell.setPageWords(_site, 'tab', 'route', 'draft');
      expect(changes, 0);
      rig.server.recent = ['server'];
      shell.openPanel();
      await pumpEventQueue();
      expect(global.recentSearches, ['server']);
      expect(shell.recentSearches, global.recentSearches);
      global.removeRecentSearch('server');
      expect(shell.recentSearches, isEmpty);
      final afterHistory = changes;
      shell.closePanel();
      expect(changes, afterHistory);
    },
  );

  test(
    'one projection merges exact terms with local priority and a limit',
    () async {
      final rig = _Rig();
      rig.server.recent = ['one', 'two', 'three', 'four', 'five', 'six'];
      await rig.history.load();
      rig.history.remember(_request('two'));
      rig.history.remember(_request('Two'));
      expect(rig.history.terms, ['Two', 'two', 'one', 'three', 'four']);
      expect(() => rig.history.terms.add('mutation'), throwsUnsupportedError);
      rig.history.remove('two');
      expect(rig.history.terms, ['Two', 'one', 'three', 'four', 'five']);
      expect(rig.history.savedRequest('two'), isNull);
      rig.history.remember(_request('two'));
      expect(rig.history.terms, ['two', 'Two', 'one', 'three', 'four']);
      await rig.history.load();
      expect(rig.server.calls, 1);
    },
  );

  test('a term evicted past the limit stays gone after a removal', () async {
    final rig = _Rig();
    for (final term in ['one', 'two', 'three', 'four', 'five', 'six']) {
      rig.history.remember(_request(term));
    }
    expect(rig.history.terms, ['six', 'five', 'four', 'three', 'two']);
    expect(rig.history.savedRequest('one'), isNull);
    rig.history.remove('six');
    expect(rig.history.terms, ['five', 'four', 'three', 'two']);
  });

  for (final edit in ['remove', 'clear']) {
    test('a delayed server read cannot undo $edit', () async {
      final rig = _Rig();
      rig.server.gates.add(Completer<List<String>>());
      final loading = rig.history.load();
      await pumpEventQueue();
      if (edit == 'remove') {
        rig.history.remove('old');
      } else {
        await rig.history.clear();
      }
      rig.server.gates.single.complete(['old']);
      await loading;
      expect(rig.history.terms, isEmpty);
      rig.history.remember(_request('new'));
      expect(rig.history.terms, ['new']);
      rig.history.remember(_request('old'));
      expect(rig.history.terms, ['old', 'new']);
    });
  }

  for (final edit in ['remove', 'clear']) {
    test('a retried server read cannot undo $edit', () async {
      final rig = _Rig();
      rig.server.gates.add(Completer<List<String>>());
      final failed = rig.history.load();
      await pumpEventQueue();
      rig.server.gates.first.completeError(StateError('offline'));
      await failed;
      rig.server.gates.add(Completer<List<String>>());
      final retrying = rig.history.load();
      await pumpEventQueue();
      expect(rig.server.calls, 2);
      if (edit == 'remove') {
        rig.history.remove('old');
      } else {
        expect(await rig.history.clear(), RecentSearchClearOutcome.cleared);
      }
      rig.history.remember(_request('local'));
      rig.server.gates.last.complete(['old', 'other']);
      await retrying;
      expect(
        rig.history.terms,
        edit == 'remove' ? ['local', 'other'] : ['local'],
      );
    });
  }

  test(
    'a retired read failure cannot invalidate its successor cache',
    () async {
      final rig = _Rig();
      rig.server.gates.add(Completer<List<String>>());
      final retired = rig.history.load();
      await pumpEventQueue();
      rig.lifecycle.invalidate(_site);
      rig.history.configure(siteUrl: _site, username: 'other');
      rig.server.recent = ['current'];
      await rig.history.load();
      expect(rig.history.terms, ['current']);
      rig.server.gates.single.completeError(StateError('offline'));
      await retired;
      await rig.history.load();
      expect(rig.server.calls, 2);
      expect(rig.history.terms, ['current']);
    },
  );

  for (final edit in [
    'none',
    'remember',
    'remove',
    'clear',
    'account',
    'retire',
    'dispose',
  ]) {
    test('failed clear respects a newer $edit operation', () async {
      final rig = _Rig();
      rig.history.remember(_request('old'));
      rig.api.clearGates.add(Completer<void>());
      final clearing = rig.history.clear();
      await pumpEventQueue();
      switch (edit) {
        case 'remember':
          rig.history.remember(_request('new'));
        case 'remove':
          rig.history.remove('old');
        case 'clear':
          await rig.history.clear();
        case 'account':
          rig.history.configure(siteUrl: _site, username: 'other');
        case 'retire':
          rig.lifecycle.invalidate(_site);
        case 'dispose':
          rig.dispose();
      }
      rig.api.clearGates.single.completeError(StateError('offline'));
      expect(
        await clearing,
        edit == 'none'
            ? RecentSearchClearOutcome.failed
            : RecentSearchClearOutcome.superseded,
      );
      expect(rig.history.terms, switch (edit) {
        'none' => ['old'],
        'remember' => ['new'],
        _ => isEmpty,
      });
    });
  }

  for (final edit in ['none', 'remember', 'account']) {
    test('accepted clear reports a newer $edit operation', () async {
      final rig = _Rig();
      rig.history.remember(_request('old'));
      rig.api.clearGates.add(Completer<void>());
      final clearing = rig.history.clear();
      await pumpEventQueue();
      switch (edit) {
        case 'remember':
          rig.history.remember(_request('new'));
        case 'account':
          rig.history.configure(siteUrl: _site, username: 'other');
      }
      rig.api.clearGates.single.complete();
      expect(
        await clearing,
        edit == 'none'
            ? RecentSearchClearOutcome.cleared
            : RecentSearchClearOutcome.superseded,
      );
      expect(rig.history.terms, edit == 'remember' ? ['new'] : isEmpty);
    });
  }

  test('a failed clear shows the server history again', () async {
    final rig = _Rig();
    rig.server.recent = ['server'];
    await rig.history.load();
    rig.api.clearGates.add(Completer<void>());
    final clearing = rig.history.clear();
    await pumpEventQueue();
    expect(rig.history.terms, isEmpty);
    rig.api.clearGates.single.completeError(StateError('offline'));
    expect(await clearing, RecentSearchClearOutcome.failed);
    expect(rig.history.terms, ['server']);
  });

  test('an account switch before credentials resolve sends no clear', () async {
    final rig = _Rig();
    rig.history.remember(_request('old'));
    final clearing = rig.history.clear();
    rig.history.configure(siteUrl: _site, username: 'other');
    expect(await clearing, RecentSearchClearOutcome.superseded);
    expect(rig.api.clears, 0);
  });

  test(
    'late stored removals merge before newer edits and persist together',
    () async {
      final store = _Store()..readGate = Completer<Set<String>>();
      final rig = _Rig(store: store);
      rig.server.recent = ['old removal', 'remembered'];
      await rig.history.load();
      rig.history.remove('new removal');
      rig.history.remember(_request('remembered'));
      for (var index = 0; index < 6; index++) {
        rig.history.remember(_request('later $index'));
      }
      expect(store.writes, isEmpty);
      store.readGate!.complete({'old removal', 'remembered'});
      await pumpEventQueue();
      expect(store.writes.single.terms.toList(), [
        'old removal',
        'new removal',
      ]);
      expect(store.writes.single.username, 'reader');
      expect(rig.history.terms, isNot(contains('old removal')));
      rig.history.remove('later 5');
      expect(store.writes.last.terms, {
        'old removal',
        'new removal',
        'later 5',
      });
    },
  );

  test(
    'repeated removal keeps its newest position after restored removals',
    () async {
      final store = _Store()..readGate = Completer<Set<String>>();
      final rig = _Rig(store: store);
      rig.history.remove('first');
      rig.history.remove('second');
      rig.history.remove('first');
      store.readGate!.complete({'saved', 'first'});
      await pumpEventQueue();
      expect(store.writes.single.terms.toList(), ['saved', 'second', 'first']);
    },
  );

  for (final switchBack in [false, true]) {
    test(
      'an accepted removal persists after switching ${switchBack ? 'back before hydration' : 'away'}',
      () async {
        final store = _Store()..readGate = Completer<Set<String>>();
        final rig = _Rig(store: store);
        rig.history.remove('first edit');
        rig.history.configure(siteUrl: 'https://other.test');
        if (switchBack) {
          rig.history.configure(siteUrl: _site, username: 'reader');
          rig.history.remove('second edit');
        }
        store.readGate!.complete({'stored removal'});
        await pumpEventQueue();
        expect(store.writes, hasLength(1));
        expect(store.writes.single.site, _site);
        expect(store.writes.single.username, 'reader');
        expect(store.writes.single.terms.toList(), [
          'stored removal',
          'first edit',
          if (switchBack) 'second edit',
        ]);
        rig.server.recent = [
          'stored removal',
          'first edit',
          'second edit',
          'visible',
        ];
        await rig.history.load();
        expect(rig.history.terms, switchBack ? ['visible'] : isEmpty);
      },
    );
  }

  test('retired restoration cannot write into either account', () async {
    final store = _Store()..readGate = Completer<Set<String>>();
    final rig = _Rig(store: store);
    rig.history.remove('retired edit');
    final retiredRead = store.readGate!;
    store.readGate = null;
    rig.lifecycle.invalidate(_site);
    rig.history.configure(siteUrl: _site, username: 'other');
    rig.history.remove('current edit');
    retiredRead.complete({'retired saved'});
    await pumpEventQueue();
    expect(store.writes.single.username, 'other');
    expect(store.writes.single.terms, {'current edit'});
  });

  test('logging disable retires a read and reenabling loads afresh', () async {
    final rig = _Rig();
    rig.history.remember(_request('local'));
    rig.server.gates.add(Completer<List<String>>());
    final loading = rig.history.load();
    await pumpEventQueue();
    rig.history.configure(
      siteUrl: _site,
      username: 'reader',
      logSearchQueries: false,
    );
    rig.history.remember(_request('private'));
    await rig.history.load();
    expect(rig.history.terms, isEmpty);
    expect(rig.history.savedRequest('local'), isNull);
    rig.server.gates.single.complete(['stale']);
    await loading;
    expect(rig.server.calls, 1);
    rig.history.configure(siteUrl: _site, username: 'reader');
    rig.server.recent = ['fresh'];
    await rig.history.load();
    expect(rig.server.calls, 2);
    expect(rig.history.terms, ['local', 'fresh']);
  });

  test(
    'a new account loads before retired work settles without structured state',
    () async {
      final rig = _Rig();
      rig.server.gates.add(Completer<List<String>>());
      final loading = rig.history.load();
      rig.history.remember(_request('private', scope: GlobalSearchScope.users));
      await pumpEventQueue();
      rig.lifecycle.invalidate(_site);
      expect(rig.history.terms, isEmpty);
      expect(rig.history.savedRequest('private'), isNull);
      rig.history.configure(siteUrl: _site, username: 'other');
      rig.server.recent = ['current'];
      await rig.history.load();
      expect(rig.history.terms, ['current']);
      rig.server.gates.single.complete(['retired']);
      await loading;
      expect(rig.history.terms, ['current']);
    },
  );
}

GlobalSearchRequest _request(
  String query, {
  GlobalSearchScope scope = GlobalSearchScope.all,
}) => GlobalSearchRequest(
  query: query,
  scope: scope,
  capabilities: const GlobalSearchCapabilities(),
);

final class _Rig {
  _Rig({_Store? store}) {
    history = RecentSearchHistory(
      api: api,
      server: server,
      credentials: credentials,
      lifecycle: lifecycle,
      store: store ?? _Store(),
    )..configure(siteUrl: _site, username: 'reader');
    addTearDown(dispose);
  }
  final lifecycle = SiteLifecycle();
  final credentials = FakeApiCredentialReader()..keys[_site] = 'key';
  final server = _Server();
  final api = _Api();
  late final RecentSearchHistory history;
  bool _disposed = false;
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    history.dispose();
  }
}

final class _Server extends FakeDiscourseApi {
  List<String> recent = const [];
  final gates = <Completer<List<String>>>[];
  int calls = 0;
  @override
  Future<List<String>> recentSearches({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    final index = calls++;
    return index < gates.length ? gates[index].future : recent;
  }
}

final class _Api extends GlobalSearchApi {
  _Api() : super(transport: FakeDiscourseApi());
  final clearGates = <Completer<void>>[];
  int clears = 0;
  @override
  Future<void> clearRecentSearches({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    final index = clears++;
    if (index < clearGates.length) await clearGates[index].future;
  }
}

final class _Store extends RecentSearchStore {
  Completer<Set<String>>? readGate;
  final writes = <({String site, String username, Set<String> terms})>[];
  @override
  Future<Set<String>> read(String site, String username) async =>
      readGate?.future ?? <String>{};
  @override
  Future<void> write(String site, String username, Set<String> terms) async {
    writes.add((site: site, username: username, terms: Set.of(terms)));
  }
}
