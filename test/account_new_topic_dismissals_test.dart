import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/account_new_topic_dismissals.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';

void main() {
  test('publishes busy before reentrant admission without a binding', () async {
    final fixture = _Fixture();
    Future<DismissNewTopicsFailure?>? reentrant;
    fixture.onChanged = () {
      if (fixture.owner.isBusy(_site)) {
        reentrant = fixture.owner.dismiss(fixture.command);
      }
    };
    final write = fixture.api.hold();
    final request = fixture.owner.dismiss(fixture.command);
    await write.started.future;
    expect(await reentrant, isNull);
    expect(fixture.api.calls, 1);
    expect(fixture.events, ['busy']);

    write.result.complete([7]);
    expect(await request, isNull);
    expect(fixture.events, [
      'busy',
      'dismiss_new',
      'dismiss_new_posts',
      'reload',
      'idle',
    ]);
  });

  for (final retire in ['lease', 'forget', 'dispose']) {
    test('$retire during busy publication cannot read credentials', () async {
      final credentials = _Credentials();
      final fixture = _Fixture(credentials: credentials);
      fixture.onChanged = () {
        switch (retire) {
          case 'lease':
            fixture.lifecycle.invalidate(_site);
          case 'forget':
            fixture.owner.forget(_site);
          case 'dispose':
            fixture.owner.dispose();
        }
      };

      expect(await fixture.owner.dismiss(fixture.command), isNull);
      expect(credentials.started.isCompleted, isFalse);
      expect(fixture.api.calls, 0);
      expect(fixture.events, ['busy']);
      expect(fixture.owner.isBusy(_site), isFalse);
    });
  }

  for (final retire in ['lease', 'forget']) {
    test(
      '$retire retirement isolates late completion from successor',
      () async {
        final fixture = _Fixture();
        final lease = fixture.lifecycle.capture(_site);
        final oldWrite = fixture.api.hold();
        final old = fixture.owner.dismiss(fixture.command);
        await oldWrite.started.future;
        if (retire == 'lease') {
          fixture.lifecycle.invalidate(_site);
        } else {
          fixture.owner.forget(_site);
          fixture.owner.forget(_site);
          expect(lease.isCurrent, isTrue);
        }
        expect(fixture.owner.isBusy(_site), isFalse);
        final nextWrite = fixture.api.hold();
        final next = fixture.owner.dismiss(fixture.command);
        await nextWrite.started.future;
        fixture.events.clear();

        oldWrite.result.complete([1]);
        expect(await old, isNull);
        expect(fixture.events, isEmpty);
        expect(fixture.owner.isBusy(_site), isTrue);
        expect(await fixture.owner.dismiss(fixture.command), isNull);
        expect(fixture.api.calls, 2);

        nextWrite.result.complete([7]);
        expect(await next, isNull);
        expect(fixture.acceptedIds, [
          [7],
          [7],
        ]);
        expect(fixture.events, [
          'dismiss_new',
          'dismiss_new_posts',
          'reload',
          'idle',
        ]);
      },
    );
  }

  test(
    'dispose retires pending work without retiring shared lifecycle',
    () async {
      final fixture = _Fixture();
      final lease = fixture.lifecycle.capture(_site);
      final write = fixture.api.hold();
      final request = fixture.owner.dismiss(fixture.command);
      await write.started.future;
      fixture.owner.dispose();
      fixture.owner.dispose();
      fixture.events.clear();
      expect(lease.isCurrent, isTrue);
      expect(fixture.owner.isBusy(_site), isFalse);
      expect(await fixture.owner.dismiss(fixture.command), isNull);

      write.result.complete([7]);
      expect(await request, isNull);
      expect(fixture.events, isEmpty);
      expect(fixture.api.calls, 1);
    },
  );

  for (final retire in ['lease', 'forget', 'dispose']) {
    test('$retire during tracking stops subsequent effects', () async {
      final fixture = _Fixture();
      fixture.onAccepted = () {
        switch (retire) {
          case 'lease':
            fixture.lifecycle.invalidate(_site);
          case 'forget':
            fixture.owner.forget(_site);
          case 'dispose':
            fixture.owner.dispose();
        }
      };
      final write = fixture.api.hold();
      final request = fixture.owner.dismiss(fixture.command);
      await write.started.future;
      write.result.complete([7]);

      expect(await request, isNull);
      expect(fixture.events, ['busy', 'dismiss_new']);
      expect(fixture.owner.isBusy(_site), isFalse);
    });
  }

  for (final retire in ['lease', 'forget', 'dispose']) {
    test('$retire during private credential IO cannot dispatch', () async {
      final credentials = _Credentials()..key = Completer<String?>();
      final fixture = _Fixture(credentials: credentials);
      final command = DismissNewTopicsCommand(
        instance: fixture.command.instance,
        route: ContentRoute.filteredTopicList(
          TopicListMode.newActivity,
          tags: const ['support', 'iOS'],
        ),
        mode: TopicListMode.newActivity,
        tagName: 'Support',
      );
      final request = fixture.owner.dismiss(command);
      await credentials.started.future;
      switch (retire) {
        case 'lease':
          fixture.lifecycle.invalidate(_site);
        case 'forget':
          fixture.owner.forget(_site);
        case 'dispose':
          fixture.owner.dispose();
      }
      fixture.events.clear();
      credentials.key!.complete('old-key');

      expect(await request, isNull);
      expect(fixture.api.calls, 0);
      expect(fixture.api.feedPaths, isEmpty);
      expect(fixture.events, isEmpty);
      expect(fixture.owner.isBusy(_site), isFalse);
    });
  }

  test('failed write has no automatic retry or accepted effects', () async {
    final fixture = _Fixture();
    final write = fixture.api.hold();
    final request = fixture.owner.dismiss(fixture.command);
    await write.started.future;
    write.result.completeError(StateError('response lost'));

    expect(await request, DismissNewTopicsFailure.failed);
    expect(fixture.events, ['busy', 'idle']);
    expect(fixture.api.calls, 1);
    final retryWrite = fixture.api.hold();
    final retry = fixture.owner.dismiss(fixture.command);
    await retryWrite.started.future;
    retryWrite.result.complete([7]);
    expect(await retry, isNull);
    expect(fixture.api.calls, 2);
    expect(fixture.acceptedIds, [
      [7],
      [7],
    ]);
  });
}

final class _Fixture {
  _Fixture({_Credentials? credentials}) {
    owner = NewTopicDismissals(
      api: api,
      credentials: credentials ?? _Credentials(),
      lifecycle: lifecycle,
      acceptTracking: (siteUrl, lease, message) {
        expect(siteUrl, _site);
        expect(lease.isCurrent, isTrue);
        final data = message! as Map<String, Object>;
        events.add(data['message_type']! as String);
        final payload = data['payload']! as Map<String, List<int>>;
        acceptedIds.add(payload['topic_ids']!);
        onAccepted?.call();
      },
      reloadSource: (captured, lease) async {
        expect(captured, same(command));
        expect(lease.isCurrent, isTrue);
        events.add('reload');
      },
      changed: () {
        events.add(owner.isBusy(_site) ? 'busy' : 'idle');
        onChanged?.call();
      },
    );
    addTearDown(owner.dispose);
  }

  final api = _Api();
  final lifecycle = SiteLifecycle();
  final events = <String>[];
  final acceptedIds = <List<int>>[];
  final command = DismissNewTopicsCommand(
    instance: instance('meta.discourse.org').copyWith(
      user: const DiscourseUser(
        id: 7,
        username: 'reader',
        unifiedNewEnabled: true,
      ),
    ),
    route: ContentRoute.topicList(TopicListMode.newActivity),
    mode: TopicListMode.newActivity,
    tagName: null,
  );
  late final NewTopicDismissals owner;
  void Function()? onChanged;
  void Function()? onAccepted;
}

final class _Credentials implements ApiCredentialReader {
  Completer<String?>? key;
  final started = Completer<void>();

  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    if (!started.isCompleted) started.complete();
    return key == null ? 'key' : await key!.future;
  }

  @override
  Future<String> clientId() async => '';
}

final class _Write {
  final started = Completer<void>();
  final result = Completer<List<int>>();
}

final class _Api extends FakeDiscourseApi {
  final _writes = <_Write>[];
  int calls = 0;

  _Write hold() {
    final write = _Write();
    _writes.add(write);
    addTearDown(() {
      if (!write.result.isCompleted) write.result.complete([]);
    });
    return write;
  }

  @override
  Future<List<int>> dismissNewTopics({
    required String siteUrl,
    required String apiKey,
    required bool dismissTopics,
    required bool dismissPosts,
    int? categoryId,
    String? tagName,
    List<int>? topicIds,
    String? clientId,
  }) {
    calls++;
    final write = _writes.removeAt(0);
    write.started.complete();
    return write.result.future;
  }
}
