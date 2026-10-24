import 'dart:async';

import 'package:discourse_native/src/data/account_request_session.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_flag.dart';
import 'package:discourse_native/src/plugin_api/bookmark_host.dart';
import 'package:discourse_native/src/shell/bookmark_transactions.dart';
import 'package:discourse_native/src/shell/flag_transactions.dart';
import 'package:discourse_native/src/shell/topic_data_owner.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://flags.example';
const _reason = PostFlagType(
  id: 3,
  nameKey: 'off_topic',
  name: 'Off topic',
  description: '',
  appliesTo: ['Post', 'Topic'],
);
const _messageReason = PostFlagType(
  id: 3,
  nameKey: 'explanation',
  name: 'Explanation',
  description: '',
  appliesTo: ['Post', 'Topic'],
  requireMessage: true,
);
const _post = Post(
  id: 42,
  postNumber: 2,
  username: 'author',
  cooked: '<p>Original</p>',
  postActions: [PostActionSummary(id: 3, canAct: true)],
);
const _topic = TopicDetail(
  id: 7,
  title: 'Original',
  stream: [42],
  canFlagTopic: true,
  topicActions: [PostActionSummary(id: 3, canAct: true)],
);
const _obsolete =
    'Your connection changed. Reopen the flag form and try again.';

final class _Call<T> {
  _Call(this.key, this.message, this.reason)
    : session = AccountRequestScope.current!.session;
  final String key;
  final String? message;
  final int reason;
  final Object session;
  final result = Completer<T>();
}

final class _Api extends FakeDiscourseApi {
  final postCalls = <_Call<Post>>[];
  final topicCalls = <_Call<void>>[];

  @override
  Future<Post> createPostFlag({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required int postActionTypeId,
    String? message,
    String? clientId,
  }) {
    final call = _Call<Post>(apiKey, message, postActionTypeId);
    postCalls.add(call);
    return call.result.future;
  }

  @override
  Future<void> createTopicFlag({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required int postActionTypeId,
    String? message,
    String? clientId,
  }) {
    final call = _Call<void>(apiKey, message, postActionTypeId);
    topicCalls.add(call);
    return call.result.future;
  }
}

final class _Credentials extends FakeAuthenticator {
  Completer<String?>? gate;
  Object? readFailure;

  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    if (readFailure case final error?) throw error;
    return gate == null ? keys[siteUrl] : await gate!.future;
  }

  @override
  Future<String> clientId() => throw StateError('Flags read only the key.');
}

Future<void> _until(bool Function() ready) async {
  for (var turn = 0; turn < 100; turn++) {
    if (ready()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('The flag request did not arrive.');
}

final class _Fixture {
  _Fixture() {
    credentials.keys[_site] = 'original-key';
    store.put(_site, _post);
    store.put(_site, _topic);
    data = TopicDataOwner(
      content: api,
      feeds: api,
      models: api.models,
      store: store,
      credentials: credentials,
      lifecycle: lifecycle,
      changed: () => onChange?.call(),
      liveChanged: (_) {},
      published: (_, _) => false,
      prepareCategories: (_, _) async {},
      loadTimeout: const Duration(seconds: 5),
      bookmarkReads: (site, lease) => bookmarks.forLease(site, lease)!,
    );
    flags = FlagTransactions(
      store: store,
      api: api,
      credentials: credentials,
      lifecycle: lifecycle,
      topicData: data,
      siteContextFor: (_) => context,
      changed: () => onChange?.call(),
    );
    addTearDown(flags.dispose);
    addTearDown(data.dispose);
    addTearDown(bookmarks.dispose);
    addTearDown(bookmarkChanges.dispose);
  }

  final api = _Api();
  final credentials = _Credentials();
  final store = Store();
  final lifecycle = SiteLifecycle();
  final bookmarkChanges = ChangeNotifier();
  late final bookmarks = BookmarkTransactions(
    api: api,
    store: store,
    credentials: credentials,
    lifecycle: lifecycle,
    instanceAt: (_) => null,
    siteContextFor: (_) =>
        const BookmarkSiteContext(suggestWeekendsInDatePickers: true),
    pluginStrategies: () => const [],
    topicData: (site, lease) => data.forLease(site, lease),
    checklistWriting: (_, _) => false,
    topicSlug: (_, _) => 'topic',
    changes: bookmarkChanges,
    changed: () {},
    refreshMenu: (_) async {},
    refreshList: (_) async {},
  );
  late final TopicDataOwner data;
  late final FlagTransactions flags;
  void Function()? onChange;
  FlagSiteContext context = const FlagSiteContext(
    connected: true,
    catalog: SitePostActionCatalog(postFlags: [_reason], topicFlags: [_reason]),
    minimumMessageLength: 10,
  );

  Future<String?> topic() => flags.createTopic(_site, _topic, _reason);
  Future<String?> post() => flags.createPost(_site, _post, _reason);
}

void main() {
  test('duplicate topic flags share admission until completion', () async {
    final f = _Fixture();
    final first = f.topic();
    await _until(() => f.api.topicCalls.isNotEmpty);
    expect(f.flags.topicWriting(_site, 7), isTrue);
    expect(await f.topic(), 'Another flag on this topic is still being saved.');
    expect(f.api.topicCalls, hasLength(1));
    expect(f.api.topicCalls.single.key, 'original-key');
    f.store.update<TopicDetail>(
      _site,
      7,
      (held) => held.copyWith(title: 'Newer'),
    );
    f.api.topicCalls.single.result.complete();
    expect(await first, isNull);
    expect(f.flags.topicWriting(_site, 7), isFalse);
    final held = f.store.read<TopicDetail>(_site, 7)!;
    expect(held.title, 'Newer');
    expect(held.topicActions.single.acted, isTrue);
  });

  for (final retire in ['lease', 'forget']) {
    test(
      '$retire keeps late topic cleanup out of successor admission',
      () async {
        final f = _Fixture();
        final original = f.topic();
        await _until(() => f.api.topicCalls.isNotEmpty);
        if (retire == 'lease') {
          f.lifecycle.invalidate(_site);
        } else {
          f.flags.forget(_site);
        }
        expect(f.flags.topicWriting(_site, 7), isFalse);
        f.credentials.keys[_site] = 'successor-key';
        final successor = f.topic();
        await _until(() => f.api.topicCalls.length == 2);
        f.api.topicCalls.first.result.complete();
        expect(await original, _obsolete);
        expect(f.flags.topicWriting(_site, 7), isTrue);
        expect(
          f.store.read<TopicDetail>(_site, 7)!.topicActions.single.acted,
          isFalse,
        );
        expect(
          await f.topic(),
          'Another flag on this topic is still being saved.',
        );
        expect(f.api.topicCalls.last.key, 'successor-key');
        if (retire == 'lease') {
          expect(
            f.api.topicCalls.first.session,
            isNot(same(f.api.topicCalls.last.session)),
          );
        }
        f.api.topicCalls.last.result.complete();
        expect(await successor, isNull);
        expect(f.flags.topicWriting(_site, 7), isFalse);
      },
    );
  }

  test(
    'retired post completion cannot release the successor post hold',
    () async {
      final f = _Fixture();
      final original = f.post();
      await _until(() => f.api.postCalls.isNotEmpty);
      f.lifecycle.invalidate(_site);
      final successor = f.post();
      await _until(() => f.api.postCalls.length == 2);
      f.api.postCalls.first.result.complete(_post.withLike(true));
      expect(await original, _obsolete);
      expect(f.store.read<Post>(_site, 42)!.liked, isFalse);
      expect(f.data.forSite(_site).postWriting(42), isTrue);
      f.api.postCalls.last.result.complete(_post);
      expect(await successor, isNull);
      expect(f.data.forSite(_site).postWriting(42), isFalse);
    },
  );

  test('canonical post writers block flag admission', () async {
    final f = _Fixture();
    final release = f.data.forSite(_site).holdPostWrite(42);
    expect(await f.post(), 'Another action on this post is still being saved.');
    expect(f.api.postCalls, isEmpty);
    release();
    final flag = f.post();
    await _until(() => f.api.postCalls.isNotEmpty);
    expect(f.data.forSite(_site).beginPostWrite(42), isNull);
    f.api.postCalls.single.result.complete(_post);
    expect(await flag, isNull);
  });

  for (final target in ['post', 'topic']) {
    test(
      '$target validates held records and current catalog message policy',
      () async {
        final f = _Fixture();
        f.context = const FlagSiteContext(
          connected: true,
          catalog: SitePostActionCatalog(
            postFlags: [_messageReason],
            topicFlags: [_messageReason],
          ),
          minimumMessageLength: 10,
        );
        Future<String?> send(String message) => target == 'post'
            ? f.flags.createPost(_site, _post, _reason, message: message)
            : f.flags.createTopic(_site, _topic, _reason, message: message);
        expect(
          await send('short'),
          'Your message must be between 10 and 500 characters.',
        );
        expect(
          await send('x' * 501),
          'Your message must be between 10 and 500 characters.',
        );
        final writing = send('  explanation  ');
        await _until(
          () => f.api.postCalls.isNotEmpty || f.api.topicCalls.isNotEmpty,
        );
        if (target == 'post') {
          expect(f.api.postCalls.single.message, '  explanation  ');
          f.api.postCalls.single.result.complete(_post);
        } else {
          expect(f.api.topicCalls.single.message, '  explanation  ');
          f.api.topicCalls.single.result.complete();
        }
        expect(await writing, isNull);
        if (target == 'post') {
          f.store.put(_site, _post.copyWith(hidden: true));
        }
        expect(
          await send('short'),
          target == 'post'
              ? 'This post can no longer be flagged.'
              : 'This topic can no longer be flagged.',
        );
      },
    );

    test(
      '$target credential failures clear admission without dispatch',
      () async {
        final f = _Fixture();
        f.credentials.keys.clear();
        Future<String?> send() => target == 'post' ? f.post() : f.topic();
        expect(
          await send(),
          const WriteException(WriteFailure.forbidden).message,
        );
        f.credentials.readFailure = StateError('Storage unavailable');
        expect(await send(), "Couldn't reach the site.");
        expect(f.api.postCalls, isEmpty);
        expect(f.api.topicCalls, isEmpty);
        expect(f.flags.topicWriting(_site, 7), isFalse);
        expect(f.data.forSite(_site).postWriting(42), isFalse);
      },
    );

    test('$target uncertain transport failure sends only once', () async {
      final f = _Fixture();
      final writing = target == 'post' ? f.post() : f.topic();
      await _until(
        () => f.api.postCalls.isNotEmpty || f.api.topicCalls.isNotEmpty,
      );
      final failure = StateError('Lost response');
      if (target == 'post') {
        f.api.postCalls.single.result.completeError(failure);
      } else {
        f.api.topicCalls.single.result.completeError(failure);
      }
      expect(await writing, "Couldn't reach the site.");
      expect(f.api.postCalls.length + f.api.topicCalls.length, 1);
      expect(
        f.store.read<TopicDetail>(_site, 7)!.topicActions.single.acted,
        isFalse,
      );
      expect(f.flags.topicWriting(_site, 7), isFalse);
      expect(f.data.forSite(_site).postWriting(42), isFalse);
    });

    test('$target credential retirement never dispatches', () async {
      final f = _Fixture();
      final gate = Completer<String?>();
      f.credentials.gate = gate;
      final writing = target == 'post' ? f.post() : f.topic();
      f.lifecycle.invalidate(_site);
      gate.complete('late-key');
      expect(await writing, _obsolete);
      expect(f.api.postCalls, isEmpty);
      expect(f.api.topicCalls, isEmpty);
      expect(f.flags.topicWriting(_site, 7), isFalse);
    });

    test('$target retains late transport refusal and does not retry', () async {
      final f = _Fixture();
      final writing = target == 'post' ? f.post() : f.topic();
      await _until(
        () => f.api.postCalls.isNotEmpty || f.api.topicCalls.isNotEmpty,
      );
      f.lifecycle.invalidate(_site);
      const failure = WriteException(
        WriteFailure.validation,
        errors: ['Server refusal'],
      );
      if (target == 'post') {
        f.api.postCalls.single.result.completeError(failure);
      } else {
        f.api.topicCalls.single.result.completeError(failure);
      }
      expect(await writing, 'Server refusal');
      expect(f.api.postCalls.length + f.api.topicCalls.length, 1);
    });
  }

  test(
    'publication listener retirement preserves reentrant successor admission',
    () async {
      final f = _Fixture();
      final original = f.topic();
      await _until(() => f.api.topicCalls.isNotEmpty);
      Future<String?>? successor;
      var replaced = false;
      f.store.ref<TopicDetail>(_site, 7).addListener(() {
        if (replaced) return;
        replaced = true;
        f.lifecycle.invalidate(_site);
        f.store.put(_site, _topic);
        successor = f.topic();
      });
      f.api.topicCalls.first.result.complete();
      expect(await original, isNull);
      await _until(() => f.api.topicCalls.length == 2);
      expect(f.flags.topicWriting(_site, 7), isTrue);
      f.api.topicCalls.last.result.complete();
      expect(await successor, isNull);
    },
  );

  test(
    'dispose retires in-flight flag publication and is idempotent',
    () async {
      final f = _Fixture();
      final post = f.post();
      final topic = f.topic();
      await _until(
        () => f.api.postCalls.isNotEmpty && f.api.topicCalls.isNotEmpty,
      );
      f.flags.dispose();
      f.flags.dispose();
      expect(f.flags.topicWriting(_site, 7), isFalse);
      f.api.postCalls.single.result.complete(_post.withLike(true));
      f.api.topicCalls.single.result.complete();
      expect(await post, _obsolete);
      expect(await topic, _obsolete);
      expect(f.store.read<Post>(_site, 42)!.liked, isFalse);
      expect(
        f.store.read<TopicDetail>(_site, 7)!.topicActions.single.acted,
        isFalse,
      );
      expect(await f.post(), _obsolete);
      expect(await f.topic(), _obsolete);
    },
  );
}
