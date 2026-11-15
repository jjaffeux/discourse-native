import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/account_writes.dart';
import 'package:discourse_native/src/shell/ignored_users_transactions.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://ignores.example';
const _reader = DiscourseInstance(
  url: _site,
  title: 'Ignores',
  user: DiscourseUser(id: 7, username: 'Reader'),
);
const _other = DiscourseInstance(
  url: _site,
  title: 'Ignores',
  user: DiscourseUser(id: 8, username: 'other'),
);
final _now = DateTime.utc(2026, 11, 15, 12);

final class _IgnoresApi implements UserIgnoresApi {
  final List<String> calls = [];
  Future<void> Function(String username)? onRequest;

  @override
  Future<void> ignoreUser({
    required String siteUrl,
    required String apiKey,
    required String username,
    required DateTime until,
    String? clientId,
  }) async {
    calls.add(
      'ignore $username until ${until.toIso8601String()} $apiKey $clientId',
    );
    await onRequest?.call(username);
  }

  @override
  Future<void> stopIgnoringUser({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) async {
    calls.add('normal $username $apiKey $clientId');
    await onRequest?.call(username);
  }
}

final class _Credentials implements ApiCredentialReader {
  String? key = 'api-key';

  @override
  Future<String?> apiKeyFor(String siteUrl) async => key;

  @override
  Future<String> clientId() async => 'client';
}

final class _Harness {
  _Harness() {
    ignores = IgnoredUsersTransactions(
      api: api,
      credentials: credentials,
      lifecycle: lifecycle,
      clock: () => _now,
      onChanged: (instance, username, {required ignored}) =>
          changes.add((instance.user!.username, username, ignored)),
    )..addListener(() => states.add(ignores.stateFor(_site)));
    addTearDown(ignores.dispose);
  }

  final api = _IgnoresApi();
  final credentials = _Credentials();
  final lifecycle = SiteLifecycle();
  final changes = <(String, String, bool)>[];
  final states = <AccountWriteState<String>>[];
  late final IgnoredUsersTransactions ignores;

  AccountWriteState<String> get state => ignores.stateFor(_site);
}

void main() {
  test(
    'an ignore names its person and ends the chosen time from now',
    () async {
      final h = _Harness();

      expect(
        await h.ignores.ignore(_reader, 'sam', IgnoreDuration.oneWeek),
        isTrue,
      );

      expect(h.api.calls, [
        'ignore sam until 2026-11-22T12:00:00.000Z api-key client',
      ]);
      expect(h.changes, [('Reader', 'sam', true)]);
      expect(h.states.map((state) => state.runtimeType), [
        AccountWriteBusy<String>,
        AccountWriteDone<String>,
      ]);
      expect((h.states.first as AccountWriteBusy<String>).subject, 'sam');
    },
  );

  test('the list is told before the state says done', () async {
    final h = _Harness();
    final seen = <Object>[];
    h.ignores.addListener(() {
      if (h.state is AccountWriteDone<String>) seen.add(h.changes.length);
    });

    await h.ignores.ignore(_reader, 'sam', IgnoreDuration.forever);

    expect(seen, [1]);
  });

  test('stopping returns the person to the normal level', () async {
    final h = _Harness();

    expect(await h.ignores.stopIgnoring(_reader, 'sam'), isTrue);

    expect(h.api.calls, ['normal sam api-key client']);
    expect(h.changes, [('Reader', 'sam', false)]);
  });

  test('the reader cannot ignore themselves', () async {
    final h = _Harness();

    expect(
      await h.ignores.ignore(_reader, 'reader', IgnoreDuration.oneDay),
      isFalse,
    );

    expect(h.api.calls, isEmpty);
    expect(h.states, isEmpty);
  });

  test('a refusal surfaces the site message, or a plain one', () async {
    final h = _Harness();
    h.api.onRequest = (_) async => throw const WriteException(
      WriteFailure.validation,
      errors: ['You cannot ignore that user.'],
    );
    expect(
      await h.ignores.ignore(_reader, 'sam', IgnoreDuration.oneDay),
      isFalse,
    );
    final refused = h.state as AccountWriteFailed<String>;
    expect(refused.message, 'You cannot ignore that user.');
    expect(refused.subject, 'sam');
    expect(h.changes, isEmpty);

    h.api.onRequest = (_) async => throw StateError('socket');
    expect(await h.ignores.stopIgnoring(_reader, 'sam'), isFalse);
    expect(
      (h.state as AccountWriteFailed<String>).message,
      const WriteException(WriteFailure.unreachable).message,
    );

    h.api.onRequest = null;
    expect(await h.ignores.stopIgnoring(_reader, 'sam'), isTrue);
    expect(h.state, isA<AccountWriteDone<String>>());
  });

  test('an account with no key is told to reconnect', () async {
    final h = _Harness()..credentials.key = null;

    expect(
      await h.ignores.ignore(_reader, 'sam', IgnoreDuration.oneDay),
      isFalse,
    );

    expect(h.api.calls, isEmpty);
    expect(
      (h.state as AccountWriteFailed<String>).message,
      const WriteException(WriteFailure.forbidden).message,
    );
  });

  test('a second request waits for the first to settle', () async {
    final h = _Harness();
    final first = Completer<void>();
    h.api.onRequest = (_) => first.future;

    final pending = h.ignores.ignore(_reader, 'sam', IgnoreDuration.oneDay);
    await pumpEventQueue();
    expect(await h.ignores.stopIgnoring(_reader, 'robin'), isFalse);
    expect(h.api.calls, hasLength(1));
    expect((h.state as AccountWriteBusy<String>).subject, 'sam');

    first.complete();
    expect(await pending, isTrue);
    expect(h.changes, [('Reader', 'sam', true)]);
  });

  test('a retired session ignores its late answer', () async {
    final h = _Harness();
    final request = Completer<void>();
    h.api.onRequest = (_) => request.future;

    final pending = h.ignores.ignore(_reader, 'sam', IgnoreDuration.oneDay);
    await pumpEventQueue();
    expect(h.state, isA<AccountWriteBusy<String>>());

    h.lifecycle.invalidate(_site);
    await pumpEventQueue();
    expect(h.state, isA<AccountWriteIdle<String>>());

    request.complete();
    expect(await pending, isFalse);
    expect(h.changes, isEmpty);
    expect(h.state, isA<AccountWriteIdle<String>>());
  });

  test(
    'an answer for the retired account cannot settle the next account\'s request',
    () async {
      final h = _Harness();
      final stale = Completer<void>();
      final fresh = Completer<void>();
      h.api.onRequest = (username) =>
          username == 'sam' ? stale.future : fresh.future;

      final staleRequest = h.ignores.ignore(
        _reader,
        'sam',
        IgnoreDuration.oneDay,
      );
      await pumpEventQueue();
      h.lifecycle.invalidate(_site);
      final freshRequest = h.ignores.stopIgnoring(_other, 'robin');
      await pumpEventQueue();
      expect((h.state as AccountWriteBusy<String>).subject, 'robin');

      stale.completeError(const WriteException(WriteFailure.unreachable));
      expect(await staleRequest, isFalse);
      expect((h.state as AccountWriteBusy<String>).subject, 'robin');
      expect(h.changes, isEmpty);

      fresh.complete();
      expect(await freshRequest, isTrue);
      expect(h.changes, [('other', 'robin', false)]);
    },
  );

  test('forgetting the site mid-request drops the outcome', () async {
    final h = _Harness();
    final request = Completer<void>();
    h.api.onRequest = (_) => request.future;

    final pending = h.ignores.stopIgnoring(_reader, 'sam');
    await pumpEventQueue();
    h.ignores.forget(_site);
    expect(h.state, isA<AccountWriteIdle<String>>());

    request.complete();
    expect(await pending, isFalse);
    expect(h.changes, isEmpty);
  });

  test('a disposed owner starts nothing and tolerates a late answer', () async {
    final h = _Harness();
    final request = Completer<void>();
    h.api.onRequest = (_) => request.future;
    final pending = h.ignores.stopIgnoring(_reader, 'sam');
    await pumpEventQueue();

    h.ignores.dispose();
    request.complete();

    expect(await pending, isFalse);
    expect(await h.ignores.stopIgnoring(_reader, 'sam'), isFalse);
    expect(h.changes, isEmpty);
  });
}
