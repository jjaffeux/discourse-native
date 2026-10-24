import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/current_user_reconciler.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/user_status.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/shell/do_not_disturb_controller.dart';
import 'package:discourse_native/src/shell/profile_write_transactions.dart';
import 'package:discourse_native/src/shell/user_status_overrides.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://forum.example';
const _user = DiscourseUser(id: 7, username: 'reader', hidePresence: false);

void main() {
  late _Harness h;

  setUp(() {
    h = _Harness();
    addTearDown(h.dispose);
  });

  test(
    'presence publishes its optimistic and confirmed notifications once',
    () async {
      final request = h.owner.togglePresence(_site);
      expect(h.owner.hidePresenceFor(_site), isTrue);
      expect(h.owner.presenceInFlight(_site), isTrue);
      expect(h.events, ['changed']);
      await pumpEventQueue();
      expect(h.api.presenceRequests, hasLength(1));

      h.api.presenceRequests.single.complete();
      await request;

      expect(h.current.instance.user?.hidePresence, isTrue);
      expect(h.owner.presenceInFlight(_site), isFalse);
      expect(h.events, ['changed', 'presence', 'persist', 'changed']);
    },
  );

  test(
    'status normalizes publication and preserves notification/persist order',
    () async {
      h.statuses.addListener(() => h.events.add('override'));
      final end = DateTime.utc(2030, 2);
      final request = h.owner.setStatus(
        _site,
        description: ' Working ',
        emoji: ' :house: ',
        endsAt: end,
      );
      await pumpEventQueue();
      expect(h.api.userStatusesSet.single, (
        description: ' Working ',
        emoji: ' :house: ',
        endsAt: end,
      ));
      h.api.statusRequests.single.complete();
      expect(await request, isNull);
      expect(
        h.current.instance.user?.status,
        UserStatus(description: 'Working', emoji: 'house', endsAt: end),
      );
      expect(
        h.statuses.statusFor(_site, 7, null),
        h.current.instance.user?.status,
      );
      expect(h.events, [
        'changed',
        'override',
        'status',
        'changed',
        'persist',
        'changed',
      ]);

      final clear = h.owner.clearStatus(_site);
      await pumpEventQueue();
      h.api.statusRequests.last.complete();
      expect(await clear, isNull);
      expect(h.current.instance.user?.status, isNull);
      expect(
        h.statuses.statusFor(
          _site,
          7,
          const UserStatus(description: 'old', emoji: 'house'),
        ),
        isNull,
      );
    },
  );

  test('uncertain status failure does not publish or retry', () async {
    final request = h.status();
    await pumpEventQueue();
    h.api.statusRequests.single.completeError(StateError('connection lost'));
    expect(
      await request,
      const WriteException(WriteFailure.unreachable).message,
    );
    await pumpEventQueue();
    expect(h.api.statusRequests, hasLength(1));
    expect(h.owner.statusInFlight(_site), isFalse);
    expect(h.current.instance.user?.status, isNull);
    expect(h.events, ['changed', 'changed']);
  });

  test(
    'direct retirement removes stale presence optimism and busy state',
    () async {
      final request = h.owner.togglePresence(_site);
      await pumpEventQueue();
      h.lifecycle.invalidate(_site);
      expect(h.owner.presenceInFlight(_site), isFalse);
      expect(h.owner.hidePresenceFor(_site), isFalse);
      final events = h.events.toList();
      h.api.presenceRequests.single.complete();
      await request;
      expect(h.events, events);
      expect(h.current.instance.user?.hidePresence, isFalse);
    },
  );

  test(
    'direct retirement removes the original account presence error',
    () async {
      final request = h.owner.togglePresence(_site);
      await pumpEventQueue();
      h.api.presenceRequests.single.completeError(
        const WriteException(WriteFailure.forbidden),
      );
      await request;
      expect(h.owner.presenceErrorFor(_site), isNotNull);
      h.lifecycle.invalidate(_site);
      expect(h.owner.presenceErrorFor(_site), isNull);
    },
  );

  for (final action in ['presence', 'status', 'retry']) {
    for (final retirement in ['forget', 'dispose']) {
      test(
        '$action $retirement from admission listener stops private reads',
        () async {
          if (action == 'retry') {
            h.current.replace(_user.withHidePresence(null));
          }
          final lease = h.lifecycle.capture(_site);
          h.onChanged = () {
            h.onChanged = null;
            if (retirement == 'forget') {
              h.owner.forget(_site);
            } else {
              h.owner.dispose();
            }
          };
          await h.act(action);
          expect(lease.isCurrent, isTrue);
          expect(h.credentials.keyReads, 0);
          expect(h.credentials.clientReads, 0);
          expect(h.api.presenceRequests, isEmpty);
          expect(h.api.statusRequests, isEmpty);
          expect(h.current.refreshes, 0);
        },
      );
    }
  }

  for (final action in ['presence', 'status']) {
    test('$action forget during key read prevents client-id IO', () async {
      final gate = Completer<String?>();
      h.credentials.keyGate = gate;
      final request = h.act(action);
      expect(h.credentials.keyReads, 1);
      final lease = h.lifecycle.capture(_site);
      h.owner.forget(_site);
      gate.complete('key');
      await request;
      expect(lease.isCurrent, isTrue);
      expect(h.credentials.clientReads, 0);
      expect(h.api.presenceRequests, isEmpty);
      expect(h.api.statusRequests, isEmpty);
    });
  }

  for (final action in ['presence', 'status']) {
    for (final failure in [false, true]) {
      test(
        '$action same-URL successor survives old ${failure ? 'failure' : 'success'}',
        () async {
          final old = h.act(action);
          await pumpEventQueue();
          h.lifecycle.invalidate(_site);
          h.current.replace(
            const DiscourseUser(
              id: 8,
              username: 'successor',
              hidePresence: false,
            ),
          );
          final replacement = h.act(action);
          await pumpEventQueue();
          final requests = action == 'presence'
              ? h.api.presenceRequests
              : h.api.statusRequests;
          expect(requests, hasLength(2));
          if (failure) {
            requests.first.completeError(
              const WriteException(WriteFailure.forbidden),
            );
          } else {
            requests.first.complete();
          }
          await old;
          expect(
            action == 'presence'
                ? h.owner.presenceInFlight(_site)
                : h.owner.statusInFlight(_site),
            isTrue,
          );
          expect(h.current.instance.user?.id, 8);
          expect(h.current.instance.user?.status, isNull);
          expect(h.current.instance.user?.hidePresence, isFalse);
          requests.last.complete();
          await replacement;
          expect(
            action == 'presence'
                ? h.owner.presenceInFlight(_site)
                : h.owner.statusInFlight(_site),
            isFalse,
          );
          expect(
            action == 'presence'
                ? h.current.instance.user?.hidePresence
                : h.current.instance.user?.status?.description,
            action == 'presence' ? true : 'Working',
          );
        },
      );
    }
  }

  for (final action in ['presence', 'status']) {
    test(
      '$action explicit forget keeps same-URL successor admission',
      () async {
        final old = h.act(action);
        await pumpEventQueue();
        h.owner.forget(_site);
        final successor = h.act(action);
        await pumpEventQueue();
        final requests = action == 'presence'
            ? h.api.presenceRequests
            : h.api.statusRequests;
        expect(requests, hasLength(2));
        requests.first.complete();
        await old;
        expect(
          action == 'presence'
              ? h.owner.presenceInFlight(_site)
              : h.owner.statusInFlight(_site),
          isTrue,
        );
        requests.last.complete();
        await successor;
        expect(
          action == 'presence'
              ? h.owner.presenceInFlight(_site)
              : h.owner.statusInFlight(_site),
          isFalse,
        );
      },
    );
  }

  test(
    'retirement observer cannot remove a reentrant same-URL successor',
    () async {
      Future<void>? successor;
      final detach = h.lifecycle.capture(_site).onRetire(() {
        h.current.replace(
          const DiscourseUser(
            id: 8,
            username: 'successor',
            hidePresence: false,
          ),
        );
        successor = h.owner.togglePresence(_site);
      });
      addTearDown(detach);
      final old = h.owner.togglePresence(_site);
      await pumpEventQueue();
      h.lifecycle.invalidate(_site);
      await pumpEventQueue();
      expect(h.api.presenceRequests, hasLength(2));
      h.api.presenceRequests.first.complete();
      await old;
      expect(h.owner.presenceInFlight(_site), isTrue);
      h.api.presenceRequests.last.complete();
      await successor;
      expect(h.current.instance.user?.id, 8);
      expect(h.current.instance.user?.hidePresence, isTrue);
      expect(h.owner.presenceInFlight(_site), isFalse);
    },
  );

  test(
    'late failed retry after forget emits no stale error or notification',
    () async {
      h.current.replace(_user.withHidePresence(null));
      h.current.refreshGate = Completer<void>();
      final request = h.owner.retryPresence(_site);
      await pumpEventQueue();
      expect(h.current.refreshes, 1);
      h.owner.forget(_site);
      final events = h.events.toList();
      h.current.refreshGate!.completeError(StateError('old refresh'));
      await request;
      expect(h.events, events);
      expect(h.owner.presenceErrorFor(_site), isNull);
    },
  );

  test(
    'override listener retirement stops canonical confirmation persistence and DND',
    () async {
      h.statuses.addListener(() => h.lifecycle.invalidate(_site));
      final request = h.status(pause: true);
      await pumpEventQueue();
      h.api.statusRequests.single.complete();
      expect(await request, isNull);
      expect(h.current.instance.user?.status, isNull);
      expect(
        h.events.where((event) => event == 'status' || event == 'persist'),
        isEmpty,
      );
      expect(h.api.doNotDisturbDurations, isEmpty);
    },
  );

  test(
    'changed listener retirement after canonical status stops persistence and DND',
    () async {
      h.onChanged = () {
        if (h.current.instance.user?.status != null) {
          h.lifecycle.invalidate(_site);
        }
      };
      final request = h.status(pause: true);
      await pumpEventQueue();
      h.api.statusRequests.single.complete();
      expect(await request, isNull);
      expect(h.current.instance.user?.status?.description, 'Working');
      expect(h.events.where((event) => event == 'persist'), isEmpty);
      expect(h.api.doNotDisturbDurations, isEmpty);
    },
  );

  test(
    'reentrant presence confirmation stops persistence after retirement',
    () async {
      h.current.onPresence = () => h.lifecycle.invalidate(_site);
      final request = h.owner.togglePresence(_site);
      await pumpEventQueue();
      h.api.presenceRequests.single.complete();
      await request;
      expect(h.current.instance.user?.hidePresence, isTrue);
      expect(h.events.where((event) => event == 'persist'), isEmpty);
      expect(h.events, ['changed', 'presence']);
    },
  );

  test(
    'forget settles pending presence precedence on its original reconciler',
    () async {
      final reconciler = h.current.reconcilerFor(_site);
      final request = h.owner.togglePresence(_site);
      await pumpEventQueue();
      h.owner.forget(_site);
      final result = reconciler.reconcile(
        reconciler.beginSnapshot(),
        previous: _user,
        incoming: _user.withHidePresence(true),
      );
      expect(result?.user.hidePresence, isTrue);
      h.api.presenceRequests.single.complete();
      await request;
    },
  );

  test('disposal is idempotent and rejects later write admission', () async {
    h.owner.dispose();
    h.owner.dispose();
    await h.owner.togglePresence(_site);
    expect(await h.status(), isNull);
    h.current.replace(_user.withHidePresence(null));
    await h.owner.retryPresence(_site);
    expect(h.credentials.keyReads, 0);
    expect(h.credentials.clientReads, 0);
    expect(h.events, isEmpty);
    expect(h.owner.presenceInFlight(_site), isFalse);
    expect(h.owner.statusInFlight(_site), isFalse);
  });
}

final class _Harness {
  _Harness() {
    current = _CurrentUser(lifecycle, events);
    dnd = DoNotDisturbController(
      api: api,
      credentials: credentials,
      lifecycle: lifecycle,
      onCommitted: (_, _) => events.add('dnd'),
    );
    owner = ProfileWriteTransactions(
      currentUser: current,
      api: api,
      credentials: credentials,
      lifecycle: lifecycle,
      userStatuses: statuses,
      doNotDisturb: dnd,
      changed: () {
        events.add('changed');
        onChanged?.call();
      },
    );
  }

  final lifecycle = SiteLifecycle();
  final credentials = _Credentials();
  final api = _Api();
  final statuses = UserStatusOverrides();
  final events = <String>[];
  late final _CurrentUser current;
  late final DoNotDisturbController dnd;
  late final ProfileWriteTransactions owner;
  void Function()? onChanged;

  Future<String?> status({bool? pause}) => owner.setStatus(
    _site,
    description: 'Working',
    emoji: 'house',
    pauseNotifications: pause,
  );

  Future<void> act(String action) async {
    switch (action) {
      case 'presence':
        await owner.togglePresence(_site);
      case 'status':
        await status();
      case 'retry':
        await owner.retryPresence(_site);
    }
  }

  void dispose() {
    owner.dispose();
    dnd.dispose();
    statuses.dispose();
  }
}

final class _CurrentUser implements ProfileCurrentUser {
  _CurrentUser(this.lifecycle, this.events) {
    replace(_user);
  }

  final SiteLifecycle lifecycle;
  final List<String> events;
  late DiscourseInstance instance;
  late CurrentUserReconciler reconciler;
  Completer<void>? refreshGate;
  void Function()? onPresence;
  int refreshes = 0;

  void replace(DiscourseUser user) {
    instance = const DiscourseInstance(
      url: _site,
      title: 'Forum',
      apiVersion: 4,
      config: SiteConfig(userStatusEnabled: true),
    ).copyWith(user: user);
    reconciler = CurrentUserReconciler(
      lease: lifecycle.capture(_site),
      models: const DiscourseModelCodec.core(),
    );
  }

  @override
  ProfileUserSnapshot? snapshotFor(String siteUrl) => siteUrl == _site
      ? ProfileUserSnapshot(user: instance.user, statusEnabled: true)
      : null;

  @override
  CurrentUserReconciler reconcilerFor(String siteUrl) => reconciler;

  @override
  Future<void> refresh(String siteUrl, String apiKey, SiteLease lease) async {
    refreshes++;
    await refreshGate?.future;
  }

  @override
  void confirmPresence(String siteUrl, bool hidden) {
    instance = instance.copyWith(user: instance.user!.withHidePresence(hidden));
    events.add('presence');
    onPresence?.call();
  }

  @override
  void confirmStatus(String siteUrl, int userId, UserStatus? status) {
    instance = instance.copyWith(user: instance.user!.withStatus(status));
    events.add('status');
  }

  @override
  void persist() => events.add('persist');
}

final class _Credentials implements ApiCredentialReader {
  int keyReads = 0;
  int clientReads = 0;
  Completer<String?>? keyGate;

  @override
  Future<String?> apiKeyFor(String siteUrl) {
    keyReads++;
    return keyGate?.future ?? Future.value('key');
  }

  @override
  Future<String> clientId() async {
    clientReads++;
    return '';
  }
}

final class _Api extends FakeDiscourseApi {
  final presenceRequests = <Completer<void>>[];
  final statusRequests = <Completer<void>>[];

  Future<void> _request(List<Completer<void>> requests) {
    final request = Completer<void>();
    requests.add(request);
    return request.future;
  }

  @override
  Future<void> updateHidePresence({
    required String siteUrl,
    required String apiKey,
    required String username,
    required bool hidePresence,
    String? clientId,
  }) => _request(presenceRequests);

  @override
  Future<void> setUserStatus({
    required String siteUrl,
    required String apiKey,
    required String description,
    required String emoji,
    DateTime? endsAt,
    String? clientId,
  }) {
    userStatusesSet.add((
      description: description,
      emoji: emoji,
      endsAt: endsAt,
    ));
    return _request(statusRequests);
  }

  @override
  Future<void> clearUserStatus({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) {
    userStatusesCleared.add(siteUrl);
    return _request(statusRequests);
  }
}
