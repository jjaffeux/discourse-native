import 'dart:async';

import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/plugin_api/bookmark_host.dart';
import 'package:discourse_native/src/plugin_api/topic_reader.dart';
import 'package:discourse_native/src/shell/bookmark_transactions.dart';
import 'package:discourse_native/src/shell/topic_data_owner.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://reader.example';
const _topicId = 7;

Post _post(int id, String text, {String? raw}) => Post(
  id: id,
  postNumber: id,
  username: 'author',
  cooked: '<p>$text</p>',
  raw: raw,
  version: 1,
);

TopicPayload _payload({
  List<int> stream = const [1, 2],
  List<Post> posts = const [],
  int? lastRead,
  String title = 'Topic',
}) => (
  detail: TopicDetail(
    id: _topicId,
    title: title,
    stream: stream,
    postsCount: stream.length,
    lastReadPostNumber: lastRead,
  ),
  posts: posts,
);

final class _TopicRead {
  _TopicRead(this.postNumber);
  final int? postNumber;
  final result = Completer<TopicPayload>();
}

final class _Api extends FakeDiscourseApi {
  final reads = <_TopicRead>[];

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
    Future<void>? abortTrigger,
  }) {
    final read = _TopicRead(postNumber);
    reads.add(read);
    return read.result.future;
  }

  Future<void> waitReads(int count) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (reads.length < count) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Expected topic request $count, received ${reads.length}.');
      }
      await Future<void>.delayed(Duration.zero);
    }
  }
}

final class _Fixture {
  _Fixture({bool hasProvider = true}) {
    owner = TopicDataOwner(
      content: api,
      feeds: api,
      models: api.models,
      store: store,
      credentials: credentials,
      lifecycle: lifecycle,
      changed: () => changes++,
      liveChanged: (_) => changes++,
      published: (_, _) => false,
      prepareCategories: (_, _) async {},
      loadTimeout: const Duration(seconds: 5),
      bookmarkReads: (siteUrl, lease) => bookmarks.forLease(siteUrl, lease)!,
      usesReader: hasProvider ? (_, _) => customReader : null,
    );
    addTearDown(owner.dispose);
    addTearDown(bookmarks.dispose);
    addTearDown(bookmarkChanges.dispose);
  }

  final api = _Api();
  final store = Store();
  final credentials = FakeAuthenticator();
  final lifecycle = SiteLifecycle();
  final bookmarkChanges = ChangeNotifier();
  late final TopicDataOwner owner;
  late final bookmarks = BookmarkTransactions(
    api: api,
    store: store,
    credentials: credentials,
    lifecycle: lifecycle,
    instanceAt: (_) => null,
    siteContextFor: (_) =>
        const BookmarkSiteContext(suggestWeekendsInDatePickers: true),
    pluginStrategies: () => const [],
    topicData: (siteUrl, lease) => owner.forLease(siteUrl, lease),
    checklistWriting: (_, _) => false,
    topicSlug: (_, _) => 'topic',
    changes: bookmarkChanges,
    changed: () => changes++,
    refreshMenu: (_) async {},
    refreshList: (_) async {},
  );
  bool customReader = true;
  int changes = 0;
  TopicDataSession get data => owner.forSite(_site);

  TopicOpening opening({List<int>? resumed, bool canResume = false}) =>
      TopicOpening(
        received: (_) {},
        canResume: () => canResume,
        resume: (number) {
          resumed?.add(number);
          return (slug: 'topic', postNumber: number);
        },
      );

  Future<TopicDataSession> discover({List<Post>? posts}) async {
    final session = data;
    final opening = session.open(
      _topicId,
      slug: 'topic',
      opening: this.opening(),
    );
    await api.waitReads(1);
    api.reads.single.result.complete(
      _payload(posts: posts ?? [_post(1, 'initial')]),
    );
    await opening;
    expect(session.readerResolved(_topicId), isTrue);
    expect(session.usesReader(_topicId), isTrue);
    return session;
  }
}

void main() {
  group('topic reader opening', () {
    test(
      'provider discovery precedes cached resume and selects one reader',
      () async {
        final f = _Fixture();
        f.store.put(_site, _payload(lastRead: 8).detail);
        f.store.put(_site, _post(1, 'cached'));
        final resumed = <int>[];
        final opening = f.data.open(
          _topicId,
          slug: 'topic',
          opening: f.opening(resumed: resumed, canResume: true),
        );
        await f.api.waitReads(1);
        expect(f.api.reads.single.postNumber, isNull);
        expect(resumed, isEmpty);
        f.api.reads.single.result.complete(
          _payload(lastRead: 9, posts: [_post(1, 'fresh')]),
        );
        await opening;
        expect(resumed, isEmpty);
        expect(f.data.usesReader(_topicId), isTrue);
        expect(f.api.reads, hasLength(1));
      },
    );

    test(
      'without a provider cached chronological resume remains immediate',
      () async {
        final f = _Fixture(hasProvider: false);
        f.store.put(_site, _payload(stream: [1, 8], lastRead: 8).detail);
        f.store.put(_site, _post(1, 'OP'));
        f.store.put(_site, _post(8, 'read position'));
        final resumed = <int>[];
        await f.data.open(
          _topicId,
          slug: 'topic',
          opening: f.opening(resumed: resumed, canResume: true),
        );
        expect(resumed, [8]);
        expect(f.api.reads, isEmpty);
      },
    );

    test(
      'declined discovery honors the explicit target before automatic resume',
      () async {
        final f = _Fixture()..customReader = false;
        final resumed = <int>[];
        final opening = f.data.open(
          _topicId,
          slug: 'topic',
          postNumber: 77,
          opening: f.opening(resumed: resumed, canResume: false),
        );
        await f.api.waitReads(1);
        expect(f.api.reads.first.postNumber, isNull);
        f.api.reads.first.result.complete(
          _payload(stream: [1, 77], lastRead: 4, posts: [_post(1, 'OP')]),
        );
        await f.api.waitReads(2);
        expect(f.api.reads.last.postNumber, 77);
        f.api.reads.last.result.complete(
          _payload(stream: [1, 77], posts: [_post(77, 'explicit target')]),
        );
        await opening;
        expect(resumed, [77]);
        expect(f.data.usesReader(_topicId), isFalse);
      },
    );

    test(
      'custom discovery keeps an explicit context target out of flat loading',
      () async {
        final f = _Fixture();
        final resumed = <int>[];
        final opening = f.data.open(
          _topicId,
          slug: 'topic',
          postNumber: 77,
          opening: f.opening(resumed: resumed, canResume: true),
        );
        await f.api.waitReads(1);
        expect(f.api.reads.single.postNumber, isNull);
        f.api.reads.single.result.complete(
          _payload(lastRead: 9, posts: [_post(1, 'OP')]),
        );
        await opening;
        expect(resumed, isEmpty);
        expect(f.api.reads, hasLength(1));
        expect(f.data.usesReader(_topicId), isTrue);
      },
    );
  });

  group('reader canonical publication', () {
    for (final renewed in [false, true]) {
      test(
        'ordinary reads respect ${renewed ? 'renewed' : 'active reader'} redaction',
        () async {
          final f = _Fixture();
          final data = await f.discover(
            posts: [_post(1, 'secret', raw: 'secret')],
          );
          Future<void> redact() async {
            await data.ingestReaderContent(
              _topicId,
              () async => TopicContentResult(
                value: 'redacted',
                posts: [
                  TopicContentPost(
                    _post(1, ''),
                    disposition: TopicContentDisposition.redacted,
                  ),
                ],
              ),
              sourceCurrent: () => true,
            );
          }

          await redact();
          final refresh = data.refresh(_topicId);
          await f.api.waitReads(2);
          if (renewed) {
            await redact();
            f.customReader = false;
          }
          f.api.reads.last.result.complete(
            _payload(posts: [_post(1, 'old secret', raw: 'old secret')]),
          );
          await refresh;
          expect(f.store.read<Post>(_site, 1)?.contentRedacted, isTrue);
          expect(f.store.read<Post>(_site, 1)?.raw, isNull);
        },
      );
    }

    test(
      'fresh ordinary content replaces a retired reader redaction',
      () async {
        final f = _Fixture();
        final data = await f.discover();
        await data.ingestReaderContent(
          _topicId,
          () async => TopicContentResult(
            value: 'hidden',
            posts: [
              TopicContentPost(
                _post(1, 'hidden'),
                disposition: TopicContentDisposition.redacted,
              ),
            ],
          ),
          sourceCurrent: () => true,
        );
        f.customReader = false;
        final refresh = data.refresh(_topicId);
        await f.api.waitReads(2);
        f.api.reads.last.result.complete(
          _payload(posts: [_post(1, 'visible', raw: 'visible')]),
        );
        await refresh;
        final post = f.store.read<Post>(_site, 1)!;
        expect(post.contentRedacted, isFalse);
        expect(post.cooked, '<p>visible</p>');
        expect(post.raw, 'visible');
      },
    );

    test(
      'provider withdrawal during publication stops the remaining batch',
      () async {
        final f = _Fixture();
        final data = await f.discover();
        f.store.ref<Post>(_site, 10).addListener(() => f.customReader = false);
        final receipt = await data.ingestReaderContent(
          _topicId,
          () async => TopicContentResult(
            value: 'retired provider',
            metadata: _payload(title: 'Obsolete title').detail,
            posts: [
              TopicContentPost(_post(10, 'first')),
              TopicContentPost(_post(11, 'second')),
            ],
          ),
          sourceCurrent: () => true,
        );
        expect(receipt, isNull);
        expect(f.store.read<Post>(_site, 11), isNull);
        expect(f.store.read<TopicDetail>(_site, _topicId)?.title, 'Topic');
      },
    );

    test(
      'discovery refresh exposes failures and clears them on retry',
      () async {
        final f = _Fixture();
        final data = f.data;
        final failed = data.refresh(_topicId);
        await f.api.waitReads(1);
        f.api.reads.first.result.completeError(StateError('offline'));
        await failed;
        expect(data.readerResolved(_topicId), isFalse);
        expect(data.readerFailure(_topicId), isA<StateError>());
        final retry = data.refresh(_topicId);
        await f.api.waitReads(2);
        expect(data.readerFailure(_topicId), isNull);
        f.api.reads.last.result.complete(_payload(posts: [_post(1, 'OP')]));
        await retry;
        expect(data.readerResolved(_topicId), isTrue);
        expect(data.readerFailure(_topicId), isNull);
      },
    );

    test(
      'preserved concurrent canonical data still registers membership',
      () async {
        final f = _Fixture();
        final data = await f.discover();
        f.store.put(_site, _post(99, 'cached outside current stream'));
        final response = Completer<TopicContentResult<String>>();
        final pending = data.ingestReaderContent(
          _topicId,
          () => response.future,
          sourceCurrent: () => true,
        );
        data.acceptEditedPost(_post(99, 'new edit'), raw: 'new edit');
        response.complete(
          TopicContentResult(
            value: 'page',
            posts: [TopicContentPost(_post(99, 'stale'))],
          ),
        );
        expect((await pending)?.postIds, {99});
        expect(f.store.read<Post>(_site, 99)?.raw, 'new edit');
        expect(data.containsPost(_topicId, 99), isTrue);
        expect(data.readerPostIds(_topicId), contains(99));
      },
    );

    test(
      'additional posts and metadata do not replace the flat stream',
      () async {
        final f = _Fixture();
        final data = await f.discover();
        final receipt = await data.ingestReaderContent(
          _topicId,
          () async => TopicContentResult(
            value: 'page',
            metadata: _payload(stream: [99], title: 'Refreshed').detail,
            posts: [TopicContentPost(_post(99, 'branch'))],
          ),
          sourceCurrent: () => true,
        );
        expect(receipt?.postIds, {99});
        expect(receipt?.value, 'page');
        expect(f.store.read<TopicDetail>(_site, _topicId)?.stream, [1, 2]);
        expect(f.store.read<TopicDetail>(_site, _topicId)?.title, 'Refreshed');
        expect(data.containsPost(_topicId, 99), isTrue);
        expect(data.readerPostIds(_topicId), contains(99));
        expect(f.store.read<Post>(_site, 99)?.cooked, '<p>branch</p>');
      },
    );

    test(
      'a retired source cannot publish a response or change a successor',
      () async {
        final f = _Fixture();
        final data = await f.discover();
        final response = Completer<TopicContentResult<String>>();
        var current = true;
        final incoming = data.ingestReaderContent(
          _topicId,
          () => response.future,
          sourceCurrent: () => current,
        );
        current = false;
        f.store.put(_site, _post(99, 'successor'));
        final changes = f.changes;
        response.complete(
          TopicContentResult(
            value: 'obsolete',
            posts: [TopicContentPost(_post(99, 'old response'))],
          ),
        );
        expect(await incoming, isNull);
        expect(f.store.read<Post>(_site, 99)?.cooked, '<p>successor</p>');
        expect(f.changes, changes);
      },
    );

    test(
      'source retirement during a post notification stops metadata publication',
      () async {
        final f = _Fixture();
        final data = await f.discover();
        var current = true;
        f.store.ref<Post>(_site, 99).addListener(() => current = false);
        final receipt = await data.ingestReaderContent(
          _topicId,
          () async => TopicContentResult(
            value: 'old route',
            metadata: _payload(stream: [99], title: 'Obsolete title').detail,
            posts: [TopicContentPost(_post(99, 'newly loaded'))],
          ),
          sourceCurrent: () => current,
        );
        expect(current, isFalse);
        expect(receipt, isNull);
        expect(f.store.read<TopicDetail>(_site, _topicId)?.title, 'Topic');
        expect(f.store.read<TopicDetail>(_site, _topicId)?.stream, [1, 2]);
      },
    );

    test('account retirement rejects an in-flight reader response', () async {
      final f = _Fixture();
      final data = await f.discover();
      final response = Completer<TopicContentResult<String>>();
      final incoming = data.ingestReaderContent(
        _topicId,
        () => response.future,
        sourceCurrent: () => true,
      );
      f.lifecycle.invalidate(_site);
      final successor = f.data;
      f.store.put(_site, _post(99, 'new account'));
      response.complete(
        TopicContentResult(
          value: 'old account',
          posts: [TopicContentPost(_post(99, 'old account'))],
        ),
      );
      expect(await incoming, isNull);
      expect(data.isCurrent, isFalse);
      expect(successor.isCurrent, isTrue);
      expect(f.store.read<Post>(_site, 99)?.cooked, '<p>new account</p>');
    });

    test(
      'lease retirement during publication stops the rest of the batch',
      () async {
        final f = _Fixture();
        final data = await f.discover();
        var retired = false;
        f.store.ref<Post>(_site, 10).addListener(() {
          if (retired) return;
          retired = true;
          f.lifecycle.invalidate(_site);
          f.store.put(_site, _post(10, 'successor'));
        });
        final receipt = await data.ingestReaderContent(
          _topicId,
          () async => TopicContentResult(
            value: 'two posts',
            posts: [
              TopicContentPost(_post(10, 'first')),
              TopicContentPost(_post(11, 'second')),
            ],
          ),
          sourceCurrent: () => true,
        );
        expect(retired, isTrue);
        expect(receipt, isNull);
        expect(f.store.read<Post>(_site, 10)?.cooked, '<p>successor</p>');
        expect(f.store.read<Post>(_site, 11), isNull);
      },
    );

    test('newer canonical edits survive an older reader response', () async {
      final f = _Fixture();
      final data = await f.discover(
        posts: [_post(1, 'initial', raw: 'initial')],
      );
      final response = Completer<TopicContentResult<String>>();
      final incoming = data.ingestReaderContent(
        _topicId,
        () => response.future,
        sourceCurrent: () => true,
      );
      data.acceptEditedPost(_post(1, 'new edit'), raw: 'new edit');
      response.complete(
        TopicContentResult(
          value: 'stale page',
          posts: [
            TopicContentPost(_post(1, 'old response', raw: 'old response')),
          ],
        ),
      );
      final receipt = await incoming;
      expect(receipt?.postIds, {1});
      expect(f.store.read<Post>(_site, 1)?.cooked, '<p>new edit</p>');
      expect(f.store.read<Post>(_site, 1)?.raw, 'new edit');
    });

    test('a reader response cannot overwrite an active post write', () async {
      final f = _Fixture();
      final data = await f.discover(posts: [_post(1, 'initial')]);
      final release = data.beginPostWrite(1)!;
      final receipt = await data.ingestReaderContent(
        _topicId,
        () async => TopicContentResult(
          value: 'during write',
          posts: [TopicContentPost(_post(1, 'network response'))],
        ),
        sourceCurrent: () => true,
      );
      expect(receipt?.postIds, {1});
      expect(f.store.read<Post>(_site, 1)?.cooked, '<p>initial</p>');
      expect(data.postWriting(1), isTrue);
      release();
      expect(data.postWriting(1), isFalse);
    });

    test(
      'a removal after dispatch is not resurrected or acknowledged',
      () async {
        final f = _Fixture();
        final data = await f.discover(posts: [_post(1, 'initial')]);
        final response = Completer<TopicContentResult<String>>();
        final incoming = data.ingestReaderContent(
          _topicId,
          () => response.future,
          sourceCurrent: () => true,
        );
        data.removePost(_topicId, 1);
        response.complete(
          TopicContentResult(
            value: 'stale',
            posts: [TopicContentPost(_post(1, 'removed post'))],
          ),
        );
        expect((await incoming)?.postIds, isEmpty);
        expect(f.store.read<Post>(_site, 1), isNull);
        expect(data.containsPost(_topicId, 1), isFalse);
      },
    );

    test(
      'an accepted bookmark is preserved across an older reader page',
      () async {
        final f = _Fixture();
        final data = await f.discover(posts: [_post(1, 'initial')]);
        final response = Completer<TopicContentResult<String>>();
        final incoming = data.ingestReaderContent(
          _topicId,
          () => response.future,
          sourceCurrent: () => true,
        );
        f.bookmarks
            .forSite(_site)
            .acceptBookmark(
              _topicId,
              const Bookmark(
                id: 12,
                bookmarkableId: 1,
                bookmarkableType: 'Post',
              ),
              isPost: true,
            );
        response.complete(
          TopicContentResult(
            value: 'before bookmark',
            posts: [TopicContentPost(_post(1, 'old page'))],
          ),
        );
        expect((await incoming)?.postIds, {1});
        expect(f.store.read<Post>(_site, 1)?.bookmark?.id, 12);
      },
    );

    test(
      'redaction clears held raw and survives a stale ordinary refresh',
      () async {
        final f = _Fixture();
        final data = await f.discover(
          posts: [_post(1, 'secret', raw: 'secret')],
        );
        final ordinaryRefresh = data.refresh(_topicId);
        await f.api.waitReads(2);
        final receipt = await data.ingestReaderContent(
          _topicId,
          () async => TopicContentResult(
            value: 'redacted',
            posts: [
              TopicContentPost(
                _post(1, ''),
                disposition: TopicContentDisposition.redacted,
              ),
            ],
          ),
          sourceCurrent: () => true,
        );
        expect(receipt?.postIds, {1});
        expect(f.store.read<Post>(_site, 1)?.raw, isNull);
        expect(f.store.read<Post>(_site, 1)?.cooked, isEmpty);
        expect(f.store.read<Post>(_site, 1)?.canEdit, isFalse);
        f.api.reads.last.result.complete(
          _payload(posts: [_post(1, 'secret', raw: 'secret')]),
        );
        await ordinaryRefresh;
        expect(f.store.read<Post>(_site, 1)?.contentRedacted, isTrue);
        expect(f.store.read<Post>(_site, 1)?.raw, isNull);
        expect(f.store.read<Post>(_site, 1)?.cooked, isEmpty);
      },
    );

    test(
      'authoritative redaction does not leave editable text under a write hold',
      () async {
        final f = _Fixture();
        final data = await f.discover(
          posts: [_post(1, 'secret', raw: 'secret')],
        );
        final release = data.beginPostWrite(1)!;
        try {
          await data.ingestReaderContent(
            _topicId,
            () async => TopicContentResult(
              value: 'redacted',
              posts: [
                TopicContentPost(
                  _post(1, ''),
                  disposition: TopicContentDisposition.redacted,
                ),
              ],
            ),
            sourceCurrent: () => true,
          );
          expect(f.store.read<Post>(_site, 1)?.raw, isNull);
          expect(f.store.read<Post>(_site, 1)?.cooked, isEmpty);
          expect(data.postWriting(1), isTrue);
        } finally {
          release();
        }
      },
    );

    test(
      'fresh authorized content can replace a previously redacted record',
      () async {
        final f = _Fixture();
        final data = await f.discover(posts: [_post(1, 'initial')]);
        await data.ingestReaderContent(
          _topicId,
          () async => TopicContentResult(
            value: 'redacted',
            posts: [
              TopicContentPost(
                _post(1, ''),
                disposition: TopicContentDisposition.redacted,
              ),
            ],
          ),
          sourceCurrent: () => true,
        );
        await data.ingestReaderContent(
          _topicId,
          () async => TopicContentResult(
            value: 'authorized',
            posts: [TopicContentPost(_post(1, 'restored', raw: 'restored'))],
          ),
          sourceCurrent: () => true,
        );
        expect(f.store.read<Post>(_site, 1)?.contentRedacted, isFalse);
        expect(f.store.read<Post>(_site, 1)?.raw, 'restored');
        expect(f.store.read<Post>(_site, 1)?.cooked, '<p>restored</p>');
      },
    );

    test(
      'foreign topic metadata is rejected before it publishes posts',
      () async {
        final f = _Fixture();
        final data = await f.discover();
        await expectLater(
          data.ingestReaderContent(
            _topicId,
            () async => TopicContentResult(
              value: 'wrong topic',
              metadata: const TopicDetail(id: 8, title: 'Other', stream: []),
              posts: [TopicContentPost(_post(99, 'wrong envelope'))],
            ),
            sourceCurrent: () => true,
          ),
          throwsFormatException,
        );
        expect(f.store.read<Post>(_site, 99), isNull);
        expect(f.store.read<TopicDetail>(_site, _topicId)?.title, 'Topic');
      },
    );
  });
}
