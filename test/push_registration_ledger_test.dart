import 'package:discourse_native/src/data/push_registration.dart';
import 'package:discourse_native/src/data/push_registration_ledger.dart';
import 'package:flutter_test/flutter_test.dart';

PushRegistrationRecord _record(String? token, {bool accepted = true}) =>
    PushRegistrationRecord(
      fingerprint: token == null ? null : pushTokenFingerprint(token),
      accepted: accepted,
    );

void main() {
  test('the same token is not drift', () {
    expect(
      pushRegistrationDrift(
        _record('token-a'),
        pushTokenFingerprint('token-a'),
      ),
      PushRegistrationDrift.none,
    );
  });

  test('a different token is a rotation', () {
    expect(
      pushRegistrationDrift(
        _record('token-a'),
        pushTokenFingerprint('token-b'),
      ),
      PushRegistrationDrift.rotated,
    );
  });

  test('a token where the authorization had none is newly available', () {
    expect(
      pushRegistrationDrift(_record(null), pushTokenFingerprint('token-a')),
      PushRegistrationDrift.newlyAvailable,
    );
  });

  test('no current token is never drift', () {
    for (final record in [_record('token-a'), _record(null)]) {
      expect(pushRegistrationDrift(record, null), PushRegistrationDrift.none);
    }
  });

  test('a forum that declined push is not asked again for a new token', () {
    expect(
      pushRegistrationDrift(
        _record('token-a', accepted: false),
        pushTokenFingerprint('token-b'),
      ),
      PushRegistrationDrift.none,
    );
  });

  test('a record round-trips without holding the token', () {
    const token = '0123456789abcdef-device-token';
    for (final record in [
      PushRegistrationRecord.authorized(
        const PushAuthorization(
          registration: PushRegistration(
            clientId: token,
            pushUrl: 'https://push.example/',
          ),
          accepted: true,
        ),
      ),
      _record(null, accepted: false),
    ]) {
      final stored = record.encode();
      expect(stored, isNot(contains(token)));
      final read = PushRegistrationRecord.decode(stored)!;
      expect(read.fingerprint, record.fingerprint);
      expect(read.accepted, record.accepted);
    }
    expect(PushRegistrationRecord.decode(null), isNull);
    expect(PushRegistrationRecord.decode('garbage'), isNull);
  });
}
