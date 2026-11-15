import 'dart:async';

import 'package:discourse_native/src/models/found_user.dart';
import 'package:discourse_native/src/shell/user_lookup_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a lookup waits for typing to pause and needs two letters', () async {
    final terms = <String>[];
    final lookup = UserLookupController(
      searchUsers: (term) async {
        terms.add(term);
        return [FoundUser(username: term)];
      },
      debounce: const Duration(milliseconds: 20),
    );
    addTearDown(lookup.dispose);

    lookup.search('r');
    expect(lookup.searching, isFalse);
    expect(lookup.queryIsTooShort, isTrue);
    lookup.search('ro');
    lookup.search(' rob ');
    expect(lookup.searching, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(terms, ['rob']);
    expect(lookup.results.single.username, 'rob');
    expect(lookup.searching, isFalse);
  });

  test('the answer to an earlier query never replaces a later one', () async {
    final answers = <String, Completer<List<FoundUser>>>{};
    final lookup = UserLookupController(
      searchUsers: (term) => (answers[term] = Completer()).future,
      debounce: Duration.zero,
    );
    addTearDown(lookup.dispose);

    lookup.search('sa');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    lookup.search('ro');
    answers['sa']!.complete(const [FoundUser(username: 'sam')]);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(lookup.results, isEmpty);
    expect(lookup.searching, isTrue);

    answers['ro']!.complete(const [FoundUser(username: 'robin')]);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(lookup.results.single.username, 'robin');
  });

  test('a failed search offers nobody and a cleared query stops', () async {
    final lookup = UserLookupController(
      searchUsers: (_) async => throw StateError('offline'),
      debounce: Duration.zero,
    );
    addTearDown(lookup.dispose);

    lookup.search('ro');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(lookup.results, isEmpty);
    expect(lookup.searching, isFalse);

    lookup.search('');
    expect(lookup.searching, isFalse);
  });

  test('a disposed lookup ignores a late answer', () async {
    final answer = Completer<List<FoundUser>>();
    final lookup = UserLookupController(
      searchUsers: (_) => answer.future,
      debounce: Duration.zero,
    );
    var notified = 0;
    lookup.addListener(() => notified++);
    lookup.search('ro');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final before = notified;

    lookup.dispose();
    answer.complete(const [FoundUser(username: 'robin')]);
    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(notified, before);
  });
}
