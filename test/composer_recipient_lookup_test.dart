import 'dart:async';

import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/found_group.dart';
import 'package:discourse_native/src/models/found_user.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/composer/recipient_lookup.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://meta.discourse.org';
const _sam = FoundUsersAndGroups(
  users: [FoundUser(username: 'sam')],
  groups: [FoundGroup(name: 'team')],
);

void main() {
  testWidgets('debounce searches only the latest trimmed query at 200ms', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.lookup.search('sa');
    await tester.pump(const Duration(milliseconds: 199));
    expect(fixture.terms, isEmpty);
    fixture.lookup.search(' sam ');
    await tester.pump(const Duration(milliseconds: 199));
    expect(fixture.terms, isEmpty);
    expect(fixture.lookup.query, ' sam ');
    await tester.pump(const Duration(milliseconds: 1));
    expect(fixture.terms, ['sam']);
    fixture.pending.single.complete(_sam);
    await tester.pump();
    expect(fixture.lookup.results, same(_sam));
  });

  testWidgets('a superseded response cannot replace the current results', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.lookup.search('old');
    await tester.pump(const Duration(milliseconds: 200));
    fixture.lookup.search('new');
    await tester.pump(const Duration(milliseconds: 200));
    fixture.pending.last.complete(_sam);
    await tester.pump();
    fixture.pending.first.complete(const FoundUsersAndGroups());
    await tester.pump();
    expect(fixture.lookup.results, same(_sam));
    expect(fixture.lookup.query, 'new');
  });

  for (final duringRequest in [false, true]) {
    testWidgets('account retirement clears and cancels lookup '
        '${duringRequest ? 'during request' : 'during debounce'}', (
      tester,
    ) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      fixture.lookup.search('sam');
      if (duringRequest) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      fixture.lifecycle.invalidate(_site);
      fixture.lifecycle.capture(_site);
      if (duringRequest) fixture.pending.single.complete(_sam);
      await tester.pump(const Duration(milliseconds: 200));
      expect(fixture.terms, duringRequest ? ['sam'] : isEmpty);
      expect(fixture.lookup.query, isEmpty);
      expect(fixture.lookup.results.users, isEmpty);
      fixture.lookup.select(['sam']);
      expect(fixture.composer.target.targetRecipients, 'alex');
    });
  }

  test(
    'matching uses the original source and account across adapter recreation',
    () {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      expect(
        fixture.lookup.matches(fixture.composer, fixture.capability()),
        isTrue,
      );
      expect(
        fixture.lookup.matches(
          fixture.composer,
          fixture.capability(source: Object()),
        ),
        isFalse,
      );
      final other = _composer();
      addTearDown(other.dispose);
      expect(fixture.lookup.matches(other, fixture.capability()), isFalse);
      fixture.lifecycle.invalidate(_site);
      expect(
        fixture.lookup.matches(fixture.composer, fixture.capability()),
        isFalse,
      );
    },
  );

  testWidgets('source disposal rejects pending results and selection', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.lookup.search('sam');
    await tester.pump(const Duration(milliseconds: 200));
    fixture.sourceCurrent = false;
    fixture.pending.single.complete(_sam);
    await tester.pump();
    expect(fixture.lookup.results.users, isEmpty);
    fixture.lookup.select(['sam']);
    fixture.lookup.search('other');
    await tester.pump(const Duration(milliseconds: 200));
    expect(fixture.composer.target.targetRecipients, 'alex');
    expect(fixture.terms, ['sam']);
  });

  testWidgets('source disposal during the debounce sends no lookup', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.lookup.search('sam');
    await tester.pump(const Duration(milliseconds: 199));
    fixture.sourceCurrent = false;
    await tester.pump(const Duration(milliseconds: 1));
    expect(fixture.terms, isEmpty);
  });

  testWidgets(
    'selected users and groups survive rejected stale selection reset',
    (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      fixture.lookup.search('sam');
      await tester.pump(const Duration(milliseconds: 200));
      fixture.pending.single.complete(_sam);
      await tester.pump();
      fixture.lookup.select(['alex', 'sam', 'team']);
      expect(fixture.lookup.recipients, ['alex', 'sam', 'team']);
      fixture.lookup.search('alice');
      fixture.lookup.select(['alex', 'sam', 'team', 'stale']);
      fixture.lookup.search('', selectionReset: true);
      expect(fixture.lookup.query, 'alice');
      expect(fixture.lookup.recipients, ['alex', 'sam', 'team']);
      await tester.pump(const Duration(milliseconds: 200));
      expect(fixture.terms, ['sam', 'alice']);
      fixture.pending.last.complete(const FoundUsersAndGroups());
      await tester.pump();
      fixture.lookup.search('', selectionReset: true);
      expect(fixture.lookup.query, isEmpty);
      await tester.pump(const Duration(milliseconds: 200));
      expect(fixture.terms, ['sam', 'alice', '']);
      fixture.pending.last.complete(const FoundUsersAndGroups());
      await tester.pump();
    },
  );
}

ComposerController _composer() => ComposerController(
  const PrivateMessageComposerTarget(
    siteUrl: _site,
    topicTitle: 'New message',
    targetRecipients: 'alex',
  ),
);

final class _Fixture {
  _Fixture() {
    lookup = ComposerRecipientLookup(composer: composer, search: capability());
  }

  final lifecycle = SiteLifecycle();
  final source = Object();
  final composer = _composer();
  final terms = <String>[];
  final pending = <Completer<FoundUsersAndGroups>>[];
  bool sourceCurrent = true;
  late final ComposerRecipientLookup lookup;

  ComposerRecipientSearch capability({Object? source}) =>
      ComposerRecipientSearch(
        siteUrl: _site,
        sourceIdentity: source ?? this.source,
        lease: lifecycle.capture(_site),
        isSourceCurrent: () => sourceCurrent,
        search: (term) {
          terms.add(term);
          final result = Completer<FoundUsersAndGroups>();
          pending.add(result);
          return result.future;
        },
      );

  void dispose() {
    lookup.dispose();
    composer.dispose();
  }
}
