import 'package:discourse_native/src/foundation/error_log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String stored(String message) {
    final log = ErrorLog()
      ..record(Exception(message), null, source: ErrorSource.zone);
    return log.entries.single.message;
  }

  test('keeps the newest entries, oldest first, with no binding', () {
    var tick = 0;
    final log = ErrorLog(
      capacity: 3,
      now: () => DateTime.utc(2026, 1, 1, 0, 0, tick++),
    );

    for (var i = 0; i < 5; i++) {
      log.record(StateError('failure $i'), null, source: ErrorSource.zone);
    }

    expect(BindingBase.debugBindingType(), isNull);
    expect(log.entries.map((entry) => entry.message), [
      'Bad state: failure 2',
      'Bad state: failure 3',
      'Bad state: failure 4',
    ]);
    expect(log.entries.map((entry) => entry.at.second), [2, 3, 4]);
    expect(log.entries.first.type, 'StateError');
  });

  test('collapses a consecutive repeat instead of evicting history', () {
    var tick = 0;
    final log = ErrorLog(
      capacity: 2,
      now: () => DateTime.utc(2026, 1, 1, 0, 0, tick++),
    );
    final stack = StackTrace.fromString('#0      paint (package:a/b.dart:1:2)');

    log.record(StateError('first'), null, source: ErrorSource.zone);
    for (var frame = 0; frame < 10; frame++) {
      log.record(StateError('overflow'), stack, source: ErrorSource.framework);
    }

    expect(log.entries.map((entry) => entry.count), [1, 10]);
    expect(log.entries.last.at.second, 1);
    expect(log.entries.last.lastAt.second, 10);
  });

  test('records one throw once when two handlers observe it', () {
    final log = ErrorLog();
    final error = StateError('seen twice');

    log.record(error, null, source: ErrorSource.zone);
    log.record(error, null, source: ErrorSource.platform);

    expect(log.entries.single.source, ErrorSource.zone);
    expect(log.entries.single.count, 1);
  });

  test('never throws, whatever the error does when printed', () {
    final log = ErrorLog();

    log.record(_Unprintable(), _UnprintableStack(), source: ErrorSource.zone);
    log.record('a thrown string', null, source: ErrorSource.zone);
    log.record(42, null, source: ErrorSource.zone);

    expect(log.entries.map((entry) => entry.message), [
      '<unprintable>',
      'a thrown string',
      '42',
    ]);
    expect(log.entries.first.stack, '<unprintable>');
  });

  group('redaction', () {
    test('removes URLs, hosts and addresses', () {
      final message = stored(
        "ClientException with SocketException: Failed host lookup: "
        "'forum.example.com' (OS Error: nodename nor servname provided, "
        'errno = 8), address = forum.example.com, port = 443, '
        'uri=https://user:hunter2@forum.example.com/t/secret-plans/42.json'
        '?api_key=abcdef&page=2 from 192.168.1.20 and [2001:db8::1]',
      );

      for (final secret in [
        'example',
        'hunter2',
        'secret-plans',
        'abcdef',
        'page=2',
        '192.168',
        '2001:db8',
      ]) {
        expect(message, isNot(contains(secret)), reason: message);
      }
      expect(message, contains('Failed host lookup'));
      expect(message, contains('errno = 8'));
      expect(message, contains('https://<redacted>'));
    });

    test('removes credentials, keys and cookies', () {
      for (final (message, secrets) in [
        (
          'Request failed, User-Api-Key: 0123abcd4567 rest of headers',
          ['0123abcd4567', 'rest of headers'],
        ),
        ('Rejected cookie: _t=abc123; _forum_session=zzz', ['abc123', 'zzz']),
        ('Authorization=Bearer tok_live_1', ['tok_live_1']),
        ('got Bearer abc.def.ghi back', ['abc.def.ghi']),
        (
          'bad {"api_key": "s3cr3t", "password": "hunter2"}',
          ['s3cr3t', 'hunter2'],
        ),
        ('refresh_token=r-1 and client_secret: c-2', ['r-1', 'c-2']),
        (
          'unexpected value 3f786850e387550fdab836ed7e6dc881de23001b here',
          ['3f786850e387550fdab836ed7e6dc881de23001b'],
        ),
        ('mail for sam@example.org bounced', ['sam@', 'example.org']),
      ]) {
        final redacted = stored(message);
        for (final secret in secrets) {
          expect(redacted, isNot(contains(secret)), reason: redacted);
        }
      }
    });

    test('drops request bodies and user content', () {
      final body = stored(
        'FormatException: Unexpected character (at character 1)\n'
        '{"raw":"my private draft","title":"Salary review"}\n'
        '^',
      );
      expect(body, isNot(contains('private draft')));
      expect(body, isNot(contains('Salary')));
      expect(body, contains('Unexpected character'));

      final quoted = stored('Could not parse "my private draft" as a date');
      expect(quoted, 'Exception: Could not parse "<redacted>" as a date');

      final path = stored(
        "PathNotFoundException: Cannot open file, path = "
        "'/Users/sam/Library/drafts/Salary review.json' and "
        '/home/sam/.config/app/prefs.json',
      );
      expect(path, isNot(contains('sam')));
      expect(path, isNot(contains('Salary')));

      expect(stored('x' * 2000).length, lessThan(500));
    });

    test('keeps what a developer needs to read the failure', () {
      expect(
        stored("type 'Null' is not a subtype of type 'Map<String, dynamic>'"),
        "Exception: type 'Null' is not a subtype of type "
        "'Map<String, dynamic>'",
      );
      expect(
        stored("The getter 'length' was called on null in RenderBox.size"),
        "Exception: The getter 'length' was called on null in RenderBox.size",
      );
      expect(
        stored(
          "'package:flutter/src/widgets/framework.dart': Failed assertion: "
          "line 6161 pos 14: '_dependents.isEmpty': is not true.",
        ),
        "Exception: 'package:flutter/src/widgets/framework.dart': Failed "
        "assertion: line 6161 pos 14: '_dependents.isEmpty': is not true.",
      );
    });

    test('keeps frames but not the paths and URLs inside them', () {
      final log = ErrorLog()
        ..record(
          StateError('x'),
          StackTrace.fromString(
            '#0      main (file:///Users/sam/Code/app/lib/main.dart:3:5)\n'
            '#1      _run (package:discourse_native/src/app.dart:10:2)\n'
            '#2      load (https://forum.example.com/assets/a.js?v=1:1:1)\n'
            '#00 abs 000000010 virt 00000001 '
            '_kDartIsolateSnapshotInstructions+0x1a2b3c\n'
            '${List.filled(100, '#9      deep (dart:async/zone.dart:1:1)').join('\n')}',
          ),
          source: ErrorSource.zone,
        );
      final stack = log.entries.single.stack;

      expect(stack, contains('#0      main (main.dart:3:5)'));
      expect(stack, contains('(package:discourse_native/src/app.dart:10:2)'));
      expect(stack, contains('_kDartIsolateSnapshotInstructions+0x1a2b3c'));
      expect(stack, isNot(contains('sam')));
      expect(stack, isNot(contains('example')));
      expect(stack.split('\n'), hasLength(40));
    });
  });

  test('exports every entry with its header', () {
    final log = ErrorLog(now: () => DateTime.utc(2026, 1, 2, 3, 4, 5))
      ..record(
        StateError('first'),
        StackTrace.fromString('#0      a (package:a/a.dart:1:1)'),
        source: ErrorSource.framework,
      )
      ..record(ArgumentError('second'), null, source: ErrorSource.platform);

    final text = log.export(appVersion: '1.2.3');

    expect(text, startsWith('Discourse Native error log\nversion: 1.2.3\n'));
    expect(text, contains('entries: 2 '));
    expect(
      text,
      contains(
        '[1] 2026-01-02T03:04:05.000Z framework StateError\n'
        'Bad state: first\n'
        '#0      a (package:a/a.dart:1:1)\n',
      ),
    );
    expect(text, contains('[2] 2026-01-02T03:04:05.000Z platform '));
    expect(text.indexOf('first'), lessThan(text.indexOf('second')));

    log.clear();
    expect(log.isEmpty, isTrue);
  });
}

final class _Unprintable {
  @override
  String toString() => throw StateError('no');
}

final class _UnprintableStack implements StackTrace {
  @override
  String toString() => throw StateError('no');
}
