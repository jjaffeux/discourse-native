// Kept free of testWidgets so constructing this controller stays pinned to a
// pure-Dart path with no Flutter binding.
import 'dart:async';

import 'package:discourse_native/src/foundation/latest_wins_queued_lookup_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LatestWinsQueuedLookupController', () {
    test('delivers the current lookup result', () async {
      final results = <String>[];
      final errors = <Object>[];
      final subject = LatestWinsQueuedLookupController<String, String>(
        lookup: (term) async => '$term result',
        onResult: results.add,
        onError: (error, _) => errors.add(error),
      );
      addTearDown(subject.dispose);

      subject.request('current');
      await _drainMicrotasks();

      expect(results, ['current result']);
      expect(errors, isEmpty);
    });

    test(
      'runs one lookup at a time and retains only the newest queued request',
      () async {
        final gates = <String, Completer<String>>{};
        final started = <String>[];
        final results = <String>[];
        var active = 0;
        var maximumActive = 0;
        final subject = LatestWinsQueuedLookupController<String, String>(
          lookup: (term) async {
            started.add(term);
            active++;
            maximumActive = active > maximumActive ? active : maximumActive;
            try {
              return await (gates[term] = Completer<String>()).future;
            } finally {
              active--;
            }
          },
          onResult: results.add,
          onError: (error, stackTrace) => fail('unexpected error: $error'),
        );
        addTearDown(subject.dispose);

        subject
          ..request('first')
          ..request('discarded')
          ..request('newest');

        expect(started, ['first']);

        gates['first']!.complete('stale first result');
        await _drainMicrotasks();

        expect(started, ['first', 'newest']);
        expect(results, isEmpty);

        gates['newest']!.complete('newest result');
        await _drainMicrotasks();

        expect(results, ['newest result']);
        expect(maximumActive, 1);
      },
    );

    test('rejects stale errors and delivers the newest error', () async {
      final first = Completer<String>();
      final second = Completer<String>();
      final errors = <Object>[];
      final subject = LatestWinsQueuedLookupController<String, String>(
        lookup: (term) => term == 'first' ? first.future : second.future,
        onResult: (_) => fail('unexpected result'),
        onError: (error, _) => errors.add(error),
      );
      addTearDown(subject.dispose);

      subject
        ..request('first')
        ..request('second');
      first.completeError(StateError('stale'));
      await _drainMicrotasks();

      expect(errors, isEmpty);

      second.completeError(ArgumentError('current'));
      await _drainMicrotasks();

      expect(errors, [isA<ArgumentError>()]);
    });

    test(
      'dispose drops queued work and ignores the active completion',
      () async {
        final active = Completer<String>();
        final started = <String>[];
        final results = <String>[];
        final errors = <Object>[];
        final subject = LatestWinsQueuedLookupController<String, String>(
          lookup: (term) {
            started.add(term);
            return active.future;
          },
          onResult: results.add,
          onError: (error, _) => errors.add(error),
        );

        subject
          ..request('active')
          ..request('queued')
          ..dispose()
          ..request('after disposal');
        active.complete('ignored');
        await _drainMicrotasks();

        expect(started, ['active']);
        expect(results, isEmpty);
        expect(errors, isEmpty);
      },
    );
  });
}

Future<void> _drainMicrotasks() => Future<void>.delayed(Duration.zero);
