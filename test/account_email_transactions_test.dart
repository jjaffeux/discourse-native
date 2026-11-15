import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/account_email_transactions.dart';
import 'package:discourse_native/src/shell/account_writes.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://email.example';
const _reader = DiscourseInstance(
  url: _site,
  title: 'Email',
  user: DiscourseUser(id: 7, username: 'Reader'),
);
const _other = DiscourseInstance(
  url: _site,
  title: 'Email',
  user: DiscourseUser(id: 8, username: 'other'),
);

final class _EmailApi implements UserEmailApi {
  final List<String> calls = [];
  Future<void> Function(String email)? onRequest;

  @override
  Future<void> requestEmailChange({
    required String siteUrl,
    required String apiKey,
    required String username,
    required String email,
    String? clientId,
  }) async {
    calls.add('$username -> $email $apiKey $clientId');
    await onRequest?.call(email);
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
    emails = AccountEmailTransactions(
      api: api,
      credentials: credentials,
      lifecycle: lifecycle,
      onRequested: (instance, email) =>
          requested.add((instance.user!.username, email)),
    )..addListener(() => states.add(emails.stateFor(_site)));
    addTearDown(emails.dispose);
  }

  final api = _EmailApi();
  final credentials = _Credentials();
  final lifecycle = SiteLifecycle();
  final requested = <(String, String)>[];
  final states = <AccountWriteState<String>>[];
  late final AccountEmailTransactions emails;

  AccountWriteState<String> get state => emails.stateFor(_site);
}

void main() {
  test('a request is sent trimmed and rests as sent', () async {
    final h = _Harness();

    expect(await h.emails.requestChange(_reader, ' new@example.org '), isTrue);

    expect(h.api.calls, ['Reader -> new@example.org api-key client']);
    expect(h.requested, [('Reader', 'new@example.org')]);
    expect(h.states.map((state) => state.runtimeType), [
      AccountWriteBusy<String>,
      AccountWriteDone<String>,
    ]);
  });

  test('an empty address asks the site nothing', () async {
    final h = _Harness();

    expect(await h.emails.requestChange(_reader, '   '), isFalse);

    expect(h.api.calls, isEmpty);
    expect(h.states, isEmpty);
  });

  test('a refusal surfaces the site message and records nothing', () async {
    final h = _Harness();
    h.api.onRequest = (_) async => throw const WriteException(
      WriteFailure.validation,
      errors: ['Email is invalid.'],
    );

    expect(await h.emails.requestChange(_reader, 'nope'), isFalse);

    expect(
      (h.state as AccountWriteFailed<String>).message,
      'Email is invalid.',
    );
    expect(h.requested, isEmpty);
  });

  test(
    'editing the address clears a finished outcome, not a pending one',
    () async {
      final h = _Harness();
      await h.emails.requestChange(_reader, 'new@example.org');
      expect(h.state, isA<AccountWriteDone<String>>());

      h.emails.settle(_site);
      expect(h.state, isA<AccountWriteIdle<String>>());
      final settled = h.states.length;
      h.emails.settle(_site);
      expect(h.states, hasLength(settled));

      final request = Completer<void>();
      h.api.onRequest = (_) => request.future;
      final pending = h.emails.requestChange(_reader, 'next@example.org');
      await pumpEventQueue();
      h.emails.settle(_site);
      expect(h.state, isA<AccountWriteBusy<String>>());
      request.complete();
      expect(await pending, isTrue);
    },
  );

  test('a second request waits for the first to settle', () async {
    final h = _Harness();
    final first = Completer<void>();
    h.api.onRequest = (_) => first.future;

    final pending = h.emails.requestChange(_reader, 'one@example.org');
    await pumpEventQueue();
    expect(await h.emails.requestChange(_reader, 'two@example.org'), isFalse);
    expect(h.api.calls, hasLength(1));

    first.complete();
    expect(await pending, isTrue);
    expect(h.requested, [('Reader', 'one@example.org')]);
  });

  test(
    'an answer for the retired account cannot settle the next account\'s request',
    () async {
      final h = _Harness();
      final stale = Completer<void>();
      final fresh = Completer<void>();
      h.api.onRequest = (email) =>
          email.startsWith('stale') ? stale.future : fresh.future;

      final staleRequest = h.emails.requestChange(_reader, 'stale@example.org');
      await pumpEventQueue();
      h.lifecycle.invalidate(_site);
      await pumpEventQueue();
      expect(h.state, isA<AccountWriteIdle<String>>());
      final freshRequest = h.emails.requestChange(_other, 'fresh@example.org');
      await pumpEventQueue();

      stale.complete();
      expect(await staleRequest, isFalse);
      expect(h.requested, isEmpty);
      expect(
        (h.state as AccountWriteBusy<String>).subject,
        'fresh@example.org',
      );

      fresh.complete();
      expect(await freshRequest, isTrue);
      expect(h.requested, [('other', 'fresh@example.org')]);
    },
  );

  test('forgetting the site mid-request drops the outcome', () async {
    final h = _Harness();
    final request = Completer<void>();
    h.api.onRequest = (_) => request.future;

    final pending = h.emails.requestChange(_reader, 'new@example.org');
    await pumpEventQueue();
    h.emails.forget(_site);
    request.complete();

    expect(await pending, isFalse);
    expect(h.requested, isEmpty);
    expect(h.state, isA<AccountWriteIdle<String>>());
  });
}
