import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/account_writes.dart';
import 'package:discourse_native/src/shell/auth_token_transactions.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://security.example';
const _reader = DiscourseInstance(
  url: _site,
  title: 'Security',
  user: DiscourseUser(id: 7, username: 'Reader'),
);
const _other = DiscourseInstance(
  url: _site,
  title: 'Security',
  user: DiscourseUser(id: 8, username: 'other'),
);

final class _TokensApi implements UserAuthTokensApi {
  final List<String> calls = [];
  Future<void> Function(int tokenId)? onRevoke;

  @override
  Future<void> revokeAuthToken({
    required String siteUrl,
    required String apiKey,
    required String username,
    required int tokenId,
    String? clientId,
  }) async {
    calls.add('$username $tokenId $apiKey $clientId');
    await onRevoke?.call(tokenId);
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
    tokens = AuthTokenTransactions(
      api: api,
      credentials: credentials,
      lifecycle: lifecycle,
      onRevoked: (instance, tokenId) =>
          revoked.add((instance.user!.username, tokenId)),
    )..addListener(() => states.add(tokens.stateFor(_site)));
    addTearDown(tokens.dispose);
  }

  final api = _TokensApi();
  final credentials = _Credentials();
  final lifecycle = SiteLifecycle();
  final revoked = <(String, int)>[];
  final states = <AccountWriteState<int>>[];
  late final AuthTokenTransactions tokens;

  AccountWriteState<int> get state => tokens.stateFor(_site);
}

void main() {
  test('a session is signed out by its id for the account', () async {
    final h = _Harness();

    expect(await h.tokens.revoke(_reader, 41), isTrue);

    expect(h.api.calls, ['Reader 41 api-key client']);
    expect(h.revoked, [('Reader', 41)]);
    expect(h.states.map((state) => state.runtimeType), [
      AccountWriteBusy<int>,
      AccountWriteDone<int>,
    ]);
    expect((h.states.first as AccountWriteBusy<int>).subject, 41);
  });

  test('a refusal surfaces the site message and removes nothing', () async {
    final h = _Harness();
    h.api.onRevoke = (_) async => throw const WriteException(
      WriteFailure.validation,
      errors: ['You supplied an invalid value to the token_id parameter.'],
    );

    expect(await h.tokens.revoke(_reader, 41), isFalse);

    expect(
      (h.state as AccountWriteFailed<int>).message,
      'You supplied an invalid value to the token_id parameter.',
    );
    expect(h.revoked, isEmpty);
  });

  test('an account with no key is told to reconnect', () async {
    final h = _Harness()..credentials.key = null;

    expect(await h.tokens.revoke(_reader, 41), isFalse);

    expect(h.api.calls, isEmpty);
    expect(
      (h.state as AccountWriteFailed<int>).message,
      const WriteException(WriteFailure.forbidden).message,
    );
  });

  test('a second sign-out waits for the first to settle', () async {
    final h = _Harness();
    final first = Completer<void>();
    h.api.onRevoke = (_) => first.future;

    final pending = h.tokens.revoke(_reader, 41);
    await pumpEventQueue();
    expect(await h.tokens.revoke(_reader, 42), isFalse);
    expect(h.api.calls, hasLength(1));

    first.complete();
    expect(await pending, isTrue);
    expect(h.revoked, [('Reader', 41)]);
  });

  test(
    'an answer for the retired account cannot settle the next account\'s request',
    () async {
      final h = _Harness();
      final stale = Completer<void>();
      final fresh = Completer<void>();
      h.api.onRevoke = (id) => id == 41 ? stale.future : fresh.future;

      final staleRequest = h.tokens.revoke(_reader, 41);
      await pumpEventQueue();
      h.lifecycle.invalidate(_site);
      await pumpEventQueue();
      expect(h.state, isA<AccountWriteIdle<int>>());
      final freshRequest = h.tokens.revoke(_other, 77);
      await pumpEventQueue();

      stale.complete();
      expect(await staleRequest, isFalse);
      expect(h.revoked, isEmpty);
      expect((h.state as AccountWriteBusy<int>).subject, 77);

      fresh.complete();
      expect(await freshRequest, isTrue);
      expect(h.revoked, [('other', 77)]);
    },
  );

  test('forgetting the site mid-request drops the outcome', () async {
    final h = _Harness();
    final request = Completer<void>();
    h.api.onRevoke = (_) => request.future;

    final pending = h.tokens.revoke(_reader, 41);
    await pumpEventQueue();
    h.tokens.forget(_site);
    request.complete();

    expect(await pending, isFalse);
    expect(h.revoked, isEmpty);
    expect(h.state, isA<AccountWriteIdle<int>>());
  });
}
