import 'dart:async';

import 'package:discourse_native/src/data/push_registration.dart';
import 'package:discourse_native/src/data/push_registration_ledger.dart';
import 'package:discourse_native/src/shell/push_registration_health.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://meta.discourse.org';
const _other = 'https://try.discourse.org';

PushRegistration _registration(String token) =>
    PushRegistration(clientId: token, pushUrl: 'https://push.example/');

PushAuthorization _authorization(String? token, {bool accepted = true}) =>
    PushAuthorization(
      registration: token == null ? null : _registration(token),
      accepted: accepted,
    );

final class _MemoryLedger implements PushRegistrationLedger {
  final records = <String, PushRegistrationRecord>{};
  final dismissals = <String, String>{};
  Completer<void>? readGate;

  String _key(String siteUrl, String username) =>
      '$siteUrl ${username.toLowerCase()}';

  @override
  Future<PushRegistrationRecord?> read(String siteUrl, String username) async {
    final held = records[_key(siteUrl, username)];
    await readGate?.future;
    return held;
  }

  @override
  Future<void> write(
    String siteUrl,
    String username,
    PushRegistrationRecord record,
  ) async => records[_key(siteUrl, username)] = record;

  @override
  Future<String?> dismissed(String siteUrl, String username) async =>
      dismissals[_key(siteUrl, username)];

  @override
  Future<void> dismiss(
    String siteUrl,
    String username,
    String fingerprint,
  ) async => dismissals[_key(siteUrl, username)] = fingerprint;
}

final class _Device {
  String? token;
  String? lastAuthorized;
  final accounts = <PushAccount>[(siteUrl: _site, username: 'Reader')];
  final ledger = _MemoryLedger();
  final reads = <Completer<PushRegistration?>>[];
  bool gated = false;

  PushRegistrationHealth launch() {
    final health = PushRegistrationHealth(
      current: () {
        if (!gated) {
          return Future.value(token == null ? null : _registration(token!));
        }
        final read = Completer<PushRegistration?>();
        reads.add(read);
        return read.future;
      },
      lastAuthorizedClientId: () async => lastAuthorized,
      accounts: () => accounts,
      ledger: ledger,
    );
    addTearDown(health.dispose);
    return health;
  }
}

void main() {
  test('an unchanged token raises nothing', () async {
    final device = _Device()..token = 'token-a';
    final health = device.launch();
    await health.authorized(_site, 'reader', _authorization('token-a'));

    await health.check();

    expect(health.prompts, isEmpty);
  });

  test(
    'a rotated token prompts for the account that registered the old one',
    () async {
      final device = _Device()..token = 'token-a';
      final health = device.launch();
      await health.authorized(_site, 'reader', _authorization('token-a'));
      var notifications = 0;
      health.addListener(() => notifications++);

      device.token = 'token-b';
      await health.check();
      await health.check();

      expect(health.prompts, [
        PushReauthorizationPrompt(
          siteUrl: _site,
          username: 'Reader',
          drift: PushRegistrationDrift.rotated,
          fingerprint: pushTokenFingerprint('token-b'),
        ),
      ]);
      expect(notifications, 1);
    },
  );

  test('permission granted after a sign-in without push prompts', () async {
    final device = _Device();
    final health = device.launch();
    await health.authorized(_site, 'reader', _authorization(null));
    await health.check();
    expect(health.prompts, isEmpty);

    device.token = 'token-a';
    await health.check();

    expect(health.prompts.single.drift, PushRegistrationDrift.newlyAvailable);
  });

  test('without a token nothing is asked and nothing is recorded', () async {
    final device = _Device();
    final health = device.launch();

    await health.check();

    expect(health.prompts, isEmpty);
    expect(device.ledger.records, isEmpty);
  });

  test(
    'a dismissed prompt stays away across launches until the token moves',
    () async {
      final device = _Device()..token = 'token-a';
      var health = device.launch();
      await health.authorized(_site, 'reader', _authorization('token-a'));
      device.token = 'token-b';
      await health.check();

      await health.dismiss(health.prompts.single);
      expect(health.prompts, isEmpty);
      await health.check();
      expect(health.prompts, isEmpty);

      health = device.launch();
      await health.check();
      expect(health.prompts, isEmpty);

      device.token = 'token-c';
      await health.check();
      expect(
        health.prompts.single.fingerprint,
        pushTokenFingerprint('token-c'),
      );
    },
  );

  test('an undismissed prompt returns on the next launch', () async {
    final device = _Device()..token = 'token-a';
    await device.launch().authorized(
      _site,
      'reader',
      _authorization('token-a'),
    );
    device.token = 'token-b';

    for (var launch = 0; launch < 2; launch++) {
      final health = device.launch();
      await health.check();
      expect(health.prompts, hasLength(1));
    }
  });

  test('signing in again answers the prompt', () async {
    final device = _Device()..token = 'token-a';
    final health = device.launch();
    await health.authorized(_site, 'reader', _authorization('token-a'));
    device.token = 'token-b';
    await health.check();

    await health.authorized(_site, 'reader', _authorization('token-b'));
    expect(health.prompts, isEmpty);
    await health.check();
    expect(health.prompts, isEmpty);
  });

  test('a stale platform read cannot replace a newer check', () async {
    final device = _Device()..gated = true;
    final health = device.launch();
    await health.authorized(_site, 'reader', _authorization('token-b'));

    final stale = health.check();
    final newest = health.check();
    device.reads[1].complete(_registration('token-b'));
    await newest;
    device.reads[0].complete(_registration('token-a'));
    await stale;

    expect(health.prompts, isEmpty);
  });

  test(
    'a check in flight cannot prompt over an authorization that landed',
    () async {
      final device = _Device()..gated = true;
      final health = device.launch();
      await health.authorized(_site, 'reader', _authorization('token-a'));

      final check = health.check();
      await health.authorized(_site, 'reader', _authorization('token-b'));
      device.reads.single.complete(_registration('token-b'));
      await check;
      expect(health.prompts, isEmpty);

      final gate = device.ledger.readGate = Completer<void>();
      final second = health.check();
      device.reads.last.complete(_registration('token-c'));
      await Future<void>.delayed(Duration.zero);
      await health.authorized(_site, 'reader', _authorization('token-c'));
      gate.complete();
      await second;

      expect(health.prompts, isEmpty);
    },
  );

  test(
    'an answer given while another account is read is not republished',
    () async {
      final device = _Device()
        ..token = 'token-a'
        ..accounts.add((siteUrl: _other, username: 'reader'));
      final health = device.launch();
      await health.authorized(_site, 'reader', _authorization('token-a'));
      await health.authorized(_other, 'reader', _authorization('token-a'));
      device.token = 'token-b';
      await health.check();
      expect(health.prompts, hasLength(2));

      final gate = device.ledger.readGate = Completer<void>();
      final check = health.check();
      await Future<void>.delayed(Duration.zero);
      await health.dismiss(
        health.prompts.firstWhere((prompt) => prompt.siteUrl == _site),
      );
      await health.authorized(_other, 'reader', _authorization('token-b'));
      gate.complete();
      await check;

      expect(health.prompts, isEmpty);
    },
  );

  test('an account from before records existed is compared with the token '
      'this install last authorized', () async {
    final device = _Device()
      ..token = 'token-b'
      ..lastAuthorized = 'token-a'
      ..accounts.add((siteUrl: _other, username: 'reader'));
    final health = device.launch();
    await health.authorized(_other, 'reader', _authorization('token-b'));

    await health.check();

    expect(health.prompts.single.siteUrl, _site);
    expect(health.prompts.single.drift, PushRegistrationDrift.rotated);
  });

  test('a prompt leaves with its account', () async {
    final device = _Device()..token = 'token-a';
    final health = device.launch();
    await health.authorized(_site, 'reader', _authorization('token-a'));
    device.token = 'token-b';
    await health.check();
    expect(health.prompts, hasLength(1));

    device.accounts.clear();

    expect(health.prompts, isEmpty);
  });
}
