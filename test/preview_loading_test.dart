import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/post_likers.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/shell/preview_requests.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _oldCard = UserCard(username: 'Sam', name: 'Old');
const _newCard = UserCard(username: 'Sam', name: 'New');
const _likers = PostLikers(postId: 12, likers: []);

void main() {
  test(
    'cards coalesce by lowercase key and preserve transport casing',
    () async {
      final f = _Fixture();
      final first = f.card('SaM');
      await pumpEventQueue();
      await f.card('sam', force: true);
      expect(f.api.cardCalls.single.username, 'SaM');
      expect(f.api.cardCalls.single.apiKey, 'key');
      expect(f.api.cardCalls.single.clientId, isNull);
      f.api.cardCalls.single.response.complete(_oldCard);
      await first;
      expect(f.store.read<UserCard>(_site, 'sam'), same(_oldCard));
      await f.card('SAM');
      expect(f.api.cardCalls, hasLength(1));
      final forced = f.card('SAM', force: true);
      await pumpEventQueue();
      f.api.cardCalls.last.response.complete(_newCard);
      await forced;
      expect(f.store.read<UserCard>(_site, 'sam'), same(_newCard));
      expect(f.credentials.clientReads, 0);
    },
  );

  test('likers coalesce while pending and refetch after completion', () async {
    final f = _Fixture();
    f.credentials.key = null;
    final first = f.likers();
    await pumpEventQueue();
    await f.likers();
    expect(f.api.likers, hasLength(1));
    expect(f.api.likers.single.apiKey, isNull);
    expect(f.api.likers.single.clientId, isNull);
    f.api.likers.single.response.complete(_likers);
    await first;
    expect(f.store.read<PostLikers>(_site, 12), same(_likers));
    final next = f.likers();
    await pumpEventQueue();
    expect(f.api.likers, hasLength(2));
    f.api.likers.last.response.complete(_likers);
    await next;
    expect(f.credentials.clientReads, 0);
  });

  for (final card in [true, false]) {
    for (final failure in [
      const SiteLookupException(SiteLookupFailure.notDiscourse, _site),
      const SiteLookupException(SiteLookupFailure.unreachable, _site),
      StateError('offline'),
    ]) {
      test(
        '${card ? 'card' : 'likers'} maps $failure and keeps retry policy',
        () async {
          final f = _Fixture();
          final load = card ? f.card('SaM') : f.likers();
          await pumpEventQueue();
          if (card) {
            f.api.cardCalls.single.response.completeError(failure);
          } else {
            f.api.likers.single.response.completeError(failure);
          }
          await load;
          final expected = failure is SiteLookupException
              ? failure.failure == SiteLookupFailure.notDiscourse
                    ? card
                          ? "Couldn't see that profile."
                          : "Couldn't see who liked this."
                    : "Couldn't reach meta.discourse.org."
              : card
              ? "Couldn't load @SaM."
              : "Couldn't load who liked this.";
          expect(
            card
                ? f.owner.userCardRequests.errorFor(_site, 'sam')
                : f.owner.likerRequests.errorFor(_site, 12),
            expected,
          );
          if (card) {
            await f.card('sam');
            expect(f.api.cardCalls, hasLength(1));
          }
          final retry = card ? f.card('SaM', force: true) : f.likers();
          await pumpEventQueue();
          expect(
            card
                ? f.owner.userCardRequests.errorFor(_site, 'sam')
                : f.owner.likerRequests.errorFor(_site, 12),
            isNull,
          );
          if (card) {
            expect(f.api.cardCalls, hasLength(2));
            f.api.cardCalls.last.response.completeError(failure);
          } else {
            expect(f.api.likers, hasLength(2));
            f.api.likers.last.response.completeError(failure);
          }
          await retry;
          f.lifecycle.invalidate(_site);
          expect(f.owner.userCardRequests.errorFor(_site, 'sam'), isNull);
          expect(f.owner.likerRequests.errorFor(_site, 12), isNull);
        },
      );
    }

    test(
      '${card ? 'card' : 'likers'} begin rotation clears pending before credential IO',
      () async {
        final f = _Fixture();
        var rotated = false;
        void rotate() {
          if (rotated) return;
          rotated = true;
          f.lifecycle.invalidate(_site);
        }

        if (card) {
          f.owner.userCardRequests.addListener(rotate);
        } else {
          f.owner.likerRequests.addListener(rotate);
        }
        await (card ? f.card('Sam') : f.likers());
        expect(f.credentials.keyReads, 0);
        expect(f.api.cardCalls, isEmpty);
        expect(f.api.likers, isEmpty);
        expect(f.owner.userCardRequests.isPending(_site, 'sam'), isFalse);
        expect(f.owner.likerRequests.isPending(_site, 12), isFalse);
      },
    );

    test(
      '${card ? 'card' : 'likers'} retirement during credential IO prevents transport',
      () async {
        final f = _Fixture();
        final gate = Completer<String?>();
        f.credentials.gate = gate;
        final load = card ? f.card('Sam') : f.likers();
        expect(f.credentials.keyReads, 1);
        f.lifecycle.invalidate(_site);
        gate.complete('old-key');
        await load;
        expect(f.api.cardCalls, isEmpty);
        expect(f.api.likers, isEmpty);
        expect(f.owner.userCardRequests.isPending(_site, 'sam'), isFalse);
        expect(f.owner.likerRequests.isPending(_site, 12), isFalse);
      },
    );

    for (final oldFirst in [true, false]) {
      for (final oldFails in [true, false]) {
        test(
          '${card ? 'card' : 'likers'} retired response oldFirst=$oldFirst oldFails=$oldFails cannot finish successor',
          () async {
            final f = _Fixture();
            final old = card ? f.card('Sam') : f.likers();
            await pumpEventQueue();
            f.lifecycle.invalidate(_site);
            final next = card ? f.card('Sam') : f.likers();
            await pumpEventQueue();
            void completeOld() {
              if (card) {
                if (oldFails) {
                  f.api.cardCalls.first.response.completeError(
                    StateError('old'),
                  );
                } else {
                  f.api.cardCalls.first.response.complete(_oldCard);
                }
              } else {
                if (oldFails) {
                  f.api.likers.first.response.completeError(StateError('old'));
                } else {
                  f.api.likers.first.response.complete(_likers);
                }
              }
            }

            if (oldFirst) {
              completeOld();
              await old;
              expect(
                card
                    ? f.owner.userCardRequests.isPending(_site, 'sam')
                    : f.owner.likerRequests.isPending(_site, 12),
                isTrue,
              );
              expect(f.store.read<UserCard>(_site, 'sam'), isNull);
              expect(f.store.read<PostLikers>(_site, 12), isNull);
            }
            if (card) {
              f.api.cardCalls.last.response.complete(_newCard);
            } else {
              f.api.likers.last.response.complete(_likers);
            }
            await next;
            if (!oldFirst) {
              completeOld();
              await old;
            }
            expect(
              card
                  ? f.owner.userCardRequests.errorFor(_site, 'sam')
                  : f.owner.likerRequests.errorFor(_site, 12),
              isNull,
            );
            expect(
              card
                  ? f.store.read<UserCard>(_site, 'sam')
                  : f.store.read<PostLikers>(_site, 12),
              same(card ? _newCard : _likers),
            );
          },
        );
      }
    }
  }

  for (final card in [true, false]) {
    test(
      '${card ? 'card' : 'likers'} credential failure always finishes the request',
      () async {
        final f = _Fixture();
        f.credentials.failure = StateError('private storage unavailable');
        await (card ? f.card('Sam') : f.likers());
        expect(f.owner.userCardRequests.isPending(_site, 'sam'), isFalse);
        expect(f.owner.likerRequests.isPending(_site, 12), isFalse);
        expect(
          card
              ? f.owner.userCardRequests.errorFor(_site, 'sam')
              : f.owner.likerRequests.errorFor(_site, 12),
          card ? "Couldn't load @Sam." : "Couldn't load who liked this.",
        );
        expect(f.api.cardCalls, isEmpty);
        expect(f.api.likers, isEmpty);
      },
    );
  }

  test('retiring one site leaves another site request owned', () async {
    final f = _Fixture();
    const other = 'https://other.example';
    final first = f.likers();
    final second = f.owner.loadLikers(instance('other.example'), 12);
    await pumpEventQueue();
    f.lifecycle.invalidate(_site);
    expect(f.owner.likerRequests.isPending(_site, 12), isFalse);
    expect(f.owner.likerRequests.isPending(other, 12), isTrue);
    f.api.likers.first.response.complete(_likers);
    f.api.likers.last.response.complete(_likers);
    await Future.wait([first, second]);
    expect(f.store.read<PostLikers>(_site, 12), isNull);
    expect(f.store.read<PostLikers>(other, 12), same(_likers));
  });

  test(
    'retirement clears both notifiers before a listener starts successor work',
    () async {
      final f = _Fixture();
      final oldCard = f.card('Sam');
      final oldLikers = f.likers();
      await pumpEventQueue();
      Future<void>? successor;
      f.owner.userCardRequests.addListener(() {
        if (successor == null &&
            !f.owner.userCardRequests.isPending(_site, 'sam')) {
          successor = f.likers();
        }
      });
      f.lifecycle.invalidate(_site);
      await pumpEventQueue();
      expect(f.api.likers, hasLength(2));
      expect(f.owner.likerRequests.isPending(_site, 12), isTrue);
      f.api.cardCalls.first.response.complete(_oldCard);
      f.api.likers.first.response.completeError(StateError('old'));
      await Future.wait([oldCard, oldLikers]);
      expect(f.owner.likerRequests.isPending(_site, 12), isTrue);
      f.api.likers.last.response.complete(_likers);
      await successor;
      expect(f.store.read<PostLikers>(_site, 12), same(_likers));
    },
  );

  test('Store publication rotation cannot complete a successor card', () async {
    final f = _Fixture();
    Future<void>? successor;
    var rotated = false;
    f.store.ref<UserCard>(_site, 'sam').addListener(() {
      if (rotated) return;
      rotated = true;
      f.lifecycle.invalidate(_site);
      f.store.forget(_site);
      successor = f.card('Sam', force: true);
    });
    final old = f.card('Sam');
    await pumpEventQueue();
    f.api.cardCalls.first.response.complete(_oldCard);
    await old;
    await pumpEventQueue();
    expect(f.owner.userCardRequests.isPending(_site, 'sam'), isTrue);
    f.api.cardCalls.last.response.complete(_newCard);
    await successor;
    expect(f.store.read<UserCard>(_site, 'sam'), same(_newCard));
  });

  test(
    'cleanup notification cannot lend its successor account to the interrupted load',
    () async {
      final f = _Fixture();
      Future<void>? interrupted;
      Future<void>? successor;
      f.lifecycle.capture(_site).onRetire(() {
        interrupted = f.card('Alex');
      });
      final old = f.card('Sam');
      await pumpEventQueue();
      var rotated = false;
      f.owner.userCardRequests.addListener(() {
        if (rotated || f.owner.userCardRequests.isPending(_site, 'sam')) return;
        rotated = true;
        f.lifecycle.invalidate(_site);
        successor = f.likers();
      });
      f.lifecycle.invalidate(_site);
      await interrupted;
      await pumpEventQueue();
      expect(f.credentials.keyReads, 2);
      expect(f.api.cardCalls.map((call) => call.username), ['Sam']);
      expect(f.api.likers, hasLength(1));
      f.api.cardCalls.single.response.complete(_oldCard);
      f.api.likers.single.response.complete(_likers);
      await old;
      await successor;
      expect(f.store.read<UserCard>(_site, 'sam'), isNull);
      expect(f.store.read<UserCard>(_site, 'alex'), isNull);
      expect(f.store.read<PostLikers>(_site, 12), same(_likers));
    },
  );

  test(
    'an earlier retirement observer can start a replacement account request',
    () async {
      final f = _Fixture();
      Future<void>? successor;
      f.lifecycle.capture(_site).onRetire(() {
        successor = f.card('Sam', force: true);
      });
      final old = f.card('Sam');
      await pumpEventQueue();
      f.lifecycle.invalidate(_site);
      await pumpEventQueue();
      expect(f.api.cardCalls, hasLength(2));
      f.api.cardCalls.first.response.complete(_oldCard);
      await old;
      expect(f.owner.userCardRequests.isPending(_site, 'sam'), isTrue);
      f.api.cardCalls.last.response.complete(_newCard);
      await successor;
      expect(f.store.read<UserCard>(_site, 'sam'), same(_newCard));
    },
  );

  test(
    'dispose prevents late publication and releases request state',
    () async {
      final f = _Fixture();
      final card = f.card('Sam');
      final likers = f.likers();
      await pumpEventQueue();
      f.owner.dispose();
      f.api.cardCalls.single.response.complete(_oldCard);
      f.api.likers.single.response.completeError(StateError('old'));
      await Future.wait([card, likers]);
      expect(f.store.read<UserCard>(_site, 'sam'), isNull);
      expect(f.owner.userCardRequests.isPending(_site, 'sam'), isFalse);
      expect(f.owner.likerRequests.isPending(_site, 12), isFalse);
      f.lifecycle.invalidate(_site);
      await f.card('Sam');
      await f.likers();
      expect(f.api.cardCalls, hasLength(1));
      expect(f.api.likers, hasLength(1));
    },
  );
}

final class _Fixture {
  _Fixture() {
    owner = PreviewLoadingOwner(
      site: api,
      topicContent: api,
      credentials: credentials,
      lifecycle: lifecycle,
      store: store,
    );
    addTearDown(owner.dispose);
  }
  final api = _Api();
  final credentials = _Credentials();
  final lifecycle = SiteLifecycle();
  final store = Store();
  late final PreviewLoadingOwner owner;
  Future<void> card(String username, {bool force = false}) => owner
      .loadUserCard(instance('meta.discourse.org'), username, force: force);
  Future<void> likers() => owner.loadLikers(instance('meta.discourse.org'), 12);
}

final class _Credentials implements ApiCredentialReader {
  String? key = 'key';
  Object? failure;
  Completer<String?>? gate;
  int keyReads = 0;
  int clientReads = 0;
  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    keyReads++;
    if (failure case final error?) throw error;
    return gate == null ? key : await gate!.future;
  }

  @override
  Future<String> clientId() async {
    clientReads++;
    return 'must-not-read';
  }
}

final class _Api extends FakeDiscourseApi {
  final cardCalls =
      <
        ({
          String username,
          String? apiKey,
          String? clientId,
          Completer<UserCard> response,
        })
      >[];
  final likers =
      <({String? apiKey, String? clientId, Completer<PostLikers> response})>[];
  @override
  Future<UserCard> userCard({
    required String siteUrl,
    required String username,
    String? apiKey,
    String? clientId,
  }) {
    final response = Completer<UserCard>();
    cardCalls.add((
      username: username,
      apiKey: apiKey,
      clientId: clientId,
      response: response,
    ));
    return response.future;
  }

  @override
  Future<PostLikers> postLikers({
    required String siteUrl,
    required int postId,
    int limit = 25,
    String? apiKey,
    String? clientId,
  }) {
    final response = Completer<PostLikers>();
    likers.add((apiKey: apiKey, clientId: clientId, response: response));
    return response.future;
  }
}
