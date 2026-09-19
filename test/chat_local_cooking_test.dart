import 'dart:async';

import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/plugin_api/cooking_plugin.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_cooking_coordinator.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_preview.dart';
import 'package:discourse_native/src/plugins/chat/chat_stream_target.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_controller_test.dart' as fixtures;
import 'support/fakes.dart';
import 'support/manual_scheduler.dart';

const _site = fixtures.site;
const _target = ChatChannelTarget(9);

Future<void> _flush() => Future<void>.delayed(Duration.zero);

final class _Rig {
  _Rig({FakeDiscourseApi? api}) : api = api ?? FakeDiscourseApi() {
    host = PluginCookingHost(
      request:
          ({
            required siteUrl,
            required raw,
            profile = CookingProfile.post,
            context = const CookingContext(),
            cachedMetadata,
          }) {
            if (throwOnBuild) throw StateError('snapshot unavailable');
            final request = CookingRequest(
              raw: raw,
              profile: profile,
              snapshot: CookingSnapshot(
                siteId: siteUrl,
                accountId: '7',
                accountGeneration: generation,
                context: context,
              ),
            );
            built.add(request);
            return request;
          },
      cook: (request) {
        final result = Completer<CookingResult>();
        cooking.add((request, result));
        return result.future;
      },
      isCurrent: (request) => request.snapshot.accountGeneration == generation,
      watch: ({required siteUrl, required raw, required onChanged}) {
        changes.add(onChanged);
        return () => changes.remove(onChanged);
      },
    );
    chat = ChatController(
      api: this.api,
      requests: FakePluginRequestHost(
        credentials: FakeApiCredentialReader()..keys[_site] = 'key',
      ),
      store: store,
      currentUserFor: (_) => fixtures.currentUser,
      cookingHost: host,
      cookingScheduler: ChatCookingCoordinator(
        cook: host.cook,
        timerFactory: timers.createTimer,
      ),
      clock: () => DateTime.utc(2026, 5, 5, 10, 1),
    );
    store.put(_site, fixtures.channel(9));
    addTearDown(chat.dispose);
  }

  final FakeDiscourseApi api;
  final store = Store();
  final timers = ManualScheduler();
  late final PluginCookingHost host;
  late final ChatController chat;
  final built = <CookingRequest>[];
  final cooking = <(CookingRequest, Completer<CookingResult>)>[];
  final changes = <void Function()>[];
  var generation = 0;
  var throwOnBuild = false;

  void draft(String raw) =>
      chat.retainComposerDraft(_site, _target, raw: raw, uploads: const []);
  Future<void> debounce() async {
    timers.advance(const Duration(milliseconds: 40));
    await _flush();
  }

  void complete(int index, String html) => cooking[index].$2.complete(
    CookingResult(html: html).forRequest(cooking[index].$1),
  );
  ChatMessage? row(int id) => store.read<ChatMessage>(_site, id);
}

void main() {
  test(
    'stages and sends while cooking is held, preserving concurrent state',
    () async {
      final rig = _Rig();
      final sent = rig.chat.sendMessage(
        _site,
        9,
        OutgoingChatMessage.text('**hello**'),
      )!;
      expect(rig.built, isEmpty);
      expect(rig.row(sent.localId)!.raw, '**hello**');
      expect(rig.row(sent.localId)!.preview, isA<SourceFallback>());
      expect(rig.chat.stream(_site, 9).localMessageIds, [sent.localId]);
      await _flush();
      expect(rig.api.chatMessagesSent.single.message, '**hello**');
      expect(await sent.settled, ChatSendResult.sent);
      expect(rig.cooking, hasLength(1));
      rig.store.update<ChatMessage>(
        _site,
        sent.localId,
        (row) =>
            row.withReactions(const [ChatReaction(emoji: 'heart', count: 1)]),
      );
      rig.complete(0, '<p><strong>hello</strong></p>');
      await _flush();
      expect(
        rig.row(sent.localId)!.provisionalCooked,
        contains('<strong>hello'),
      );
      expect(rig.row(sent.localId)!.reactions.single.emoji, 'heart');
    },
  );

  test(
    'duplicate document signals coalesce and prepared HTML stages synchronously',
    () async {
      final rig = _Rig();
      rig.draft('hello');
      rig.draft('hello');
      expect(rig.built, isEmpty);
      await rig.debounce();
      expect(rig.cooking, hasLength(1));
      rig.complete(0, '<p>ready</p>');
      await _flush();
      final sent = rig.chat.sendMessage(
        _site,
        9,
        OutgoingChatMessage.text('hello'),
      )!;
      expect(rig.row(sent.localId)!.provisionalCooked, '<p>ready</p>');
      expect(rig.built, hasLength(1));
      rig.draft('');
      await sent.settled;
      expect(rig.cooking, hasLength(1));
      expect(rig.timers.activeTimerCount, 0);
    },
  );

  test('A B A cannot reuse the first A after a source revision', () async {
    final rig = _Rig();
    rig.draft('A');
    await rig.debounce();
    rig.draft('B');
    rig.draft('A');
    rig.complete(0, '<p>obsolete A</p>');
    await _flush();
    final sent = rig.chat.sendMessage(_site, 9, OutgoingChatMessage.text('A'))!;
    expect(rig.row(sent.localId)!.provisionalCooked, isNull);
    rig.draft('');
    await _flush();
    rig.complete(1, '<p>current A</p>');
    await _flush();
    expect(rig.row(sent.localId)!.provisionalCooked, '<p>current A</p>');
  });

  test(
    'send then new typing keeps separate draft and message ownership',
    () async {
      final rig = _Rig();
      final sent = rig.chat.sendMessage(
        _site,
        9,
        OutgoingChatMessage.text('sent'),
      )!;
      rig.draft('');
      rig.draft('next');
      await rig.debounce();
      expect(rig.cooking.single.$1.raw, 'sent');
      rig.complete(0, '<p>sent</p>');
      await _flush();
      expect(rig.row(sent.localId)!.provisionalCooked, '<p>sent</p>');
      expect(rig.cooking.last.$1.raw, 'next');
      rig.complete(1, '<p>next</p>');
      await _flush();
      expect(rig.chat.composerDraftFor(_site, _target)!.raw, 'next');
      expect(rig.row(sent.localId)!.provisionalCooked, '<p>sent</p>');
    },
  );

  test(
    'prepared result is invalid immediately when cached context changes',
    () async {
      final rig = _Rig();
      rig.draft('hello');
      await rig.debounce();
      rig.complete(0, '<p>old account</p>');
      await _flush();
      rig.generation++;
      // A synchronous send must be safe even before notification delivery.
      final sent = rig.chat.sendMessage(
        _site,
        9,
        OutgoingChatMessage.text('hello'),
      )!;
      expect(rig.row(sent.localId)!.provisionalCooked, isNull);
      rig.draft('');
      await _flush();
      rig.complete(1, '<p>new account</p>');
      await _flush();
      expect(rig.row(sent.localId)!.provisionalCooked, '<p>new account</p>');
    },
  );

  test('forget cancels drafts and rejects late submitted output', () async {
    final rig = _Rig();
    final sent = rig.chat.sendMessage(
      _site,
      9,
      OutgoingChatMessage.text('old'),
    )!;
    await _flush();
    rig.draft('draft');
    rig.chat.forget(_site);
    expect(rig.timers.activeTimerCount, 0);
    expect(rig.changes, isEmpty);
    rig.complete(0, '<p>late</p>');
    await _flush();
    expect(rig.row(sent.localId), isNull);
  });

  test('locale change rejects an already running submitted cook', () async {
    final rig = _Rig();
    final sent = rig.chat.sendMessage(
      _site,
      9,
      OutgoingChatMessage.text('hello'),
    )!;
    await _flush();
    expect(rig.cooking.single.$1.snapshot.context.locale, 'en');
    rig.chat.setCookingLocale(_site, 'fr');
    rig.complete(0, '<p>old locale</p>');
    await _flush();
    expect(rig.row(sent.localId)!.provisionalCooked, isNull);
    expect(rig.row(sent.localId)!.raw, 'hello');
    expect(await sent.settled, ChatSendResult.sent);
  });

  test('successive edits A B A reject the first active result', () async {
    final rig = _Rig();
    rig.store.put(_site, fixtures.message(12, raw: 'before', authorId: 7));
    expect(await rig.chat.editMessage(_site, 12, 'A'), isNull);
    await _flush();
    expect(rig.cooking, hasLength(1));
    expect(await rig.chat.editMessage(_site, 12, 'B'), isNull);
    expect(await rig.chat.editMessage(_site, 12, 'A'), isNull);
    rig.complete(0, '<p>old A</p>');
    await _flush();
    expect(rig.row(12)!.raw, 'A');
    expect(rig.row(12)!.provisionalCooked, isNull);
    expect(rig.cooking, hasLength(2));
    expect(rig.cooking.last.$1.raw, 'A');
    rig.complete(1, '<p>current A</p>');
    await _flush();
    expect(rig.row(12)!.provisionalCooked, '<p>current A</p>');
  });

  test(
    'canonical empty event before HTTP and cook remains authoritative',
    () async {
      final sendGate = Completer<void>();
      final rig = _Rig(api: FakeDiscourseApi(chatSendGate: sendGate));
      final tracker = fixtures.attachTracker(rig.chat);
      final sent = rig.chat.sendMessage(
        _site,
        9,
        OutgoingChatMessage.text('hello'),
      )!;
      await _flush();
      tracker.deliverPluginMessage(
        '/chat/9',
        fixtures.sentEvent(stagedId: sent.stagedId, cooked: ''),
      );
      rig.complete(0, '<p>late</p>');
      await _flush();
      final rows = rig.chat.messages(_site, 9);
      expect(rows.single.canonicalReceived, isTrue);
      expect(rows.single.cooked, isEmpty);
      expect(rows.single.provisionalCooked, isNull);
      sendGate.complete();
      await sent.settled;
      expect(rig.chat.messages(_site, 9).single.cooked, isEmpty);
    },
  );

  test('snapshot error cannot fail a send or delay its readable row', () async {
    final rig = _Rig()..throwOnBuild = true;
    final sent = rig.chat.sendMessage(
      _site,
      9,
      OutgoingChatMessage.text('<raw>'),
    )!;
    expect(rig.row(sent.localId)!.raw, '<raw>');
    expect(await sent.settled, ChatSendResult.sent);
    await _flush();
    expect(rig.row(sent.localId)!.provisionalCooked, isNull);
    expect(rig.cooking, isEmpty);
  });

  test(
    'page adoption without staged ID retires the row before late cooking',
    () async {
      final sendGate = Completer<void>();
      final pages = {fixtures.key(9): fixtures.page([])};
      final rig = _Rig(
        api: FakeDiscourseApi(
          chatMessagesByKey: pages,
          chatSendGate: sendGate,
          chatSentMessageId: 42,
        ),
      );
      await rig.chat.openChannel(_site, 9);
      final sent = rig.chat.sendMessage(
        _site,
        9,
        OutgoingChatMessage.text('hello'),
      )!;
      await _flush();
      final canonical = ChatMessage(
        id: 42,
        channelId: 9,
        raw: 'hello',
        cooked: '',
        author: const ChatMessageAuthor(id: 7, username: 'reader'),
        createdAt: DateTime.utc(2026, 5, 5, 10, 1),
      );
      pages[fixtures.key(9)] = fixtures.page([canonical]);
      await rig.chat.openChannel(_site, 9, force: true);
      expect(rig.chat.stream(_site, 9).localMessageIds, isEmpty);
      rig.complete(0, '<p>late</p>');
      await _flush();
      expect(rig.row(sent.localId), isNull);
      expect(rig.chat.messages(_site, 9), [canonical]);
      sendGate.complete();
      await sent.settled;
      expect(rig.chat.messages(_site, 9), [canonical]);
    },
  );

  for (final raw in ['', 'with attachment']) {
    test('attachments stay separate from cooking source: "$raw"', () async {
      final rig = _Rig();
      final sent = rig.chat.sendMessage(
        _site,
        9,
        OutgoingChatMessage.text(
          raw,
          uploads: const [
            ComposerUploadResult(
              id: 31,
              originalFilename: 'a.png',
              shortUrl: 'upload://a',
              url: '/a.png',
            ),
          ],
        ),
      )!;
      await _flush();
      expect(rig.cooking.single.$1.raw, raw);
      expect(rig.api.chatMessagesSent.single.uploadIds, [31]);
      expect(rig.api.chatMessagesSent.single.message, raw);
      rig.complete(0, raw.isEmpty ? '' : '<p>with attachment</p>');
      await _flush();
      expect(rig.row(sent.localId)!.uploads.single.id, 31);
      expect(
        rig.row(sent.localId)!.provisionalCooked,
        isNot(contains('a.png')),
      );
    });
  }

  for (final newerCanonical in [false, true]) {
    test(
      'edit refusal preserves ${newerCanonical ? 'newer canonical content' : 'concurrent reactions'} and rejects late cooking',
      () async {
        final editGate = Completer<void>();
        final rig = _Rig(
          api: FakeDiscourseApi(
            chatEditGate: editGate,
            chatEditFailure: const WriteException(WriteFailure.forbidden),
          ),
        );
        rig.store.put(_site, fixtures.message(12, raw: 'before', authorId: 7));
        final editing = rig.chat.editMessage(_site, 12, 'after');
        expect(rig.row(12)!.raw, 'after');
        expect(rig.built, isEmpty);
        await _flush();
        expect(rig.api.chatMessagesEdited.single.message, 'after');
        if (newerCanonical) {
          rig.store.put(
            _site,
            fixtures.message(12, raw: 'newer server edit', authorId: 7),
          );
        } else {
          rig.store.update<ChatMessage>(
            _site,
            12,
            (row) => row.withReactions(const [
              ChatReaction(emoji: 'heart', count: 1),
            ]),
          );
        }
        editGate.complete();
        expect(await editing, isNotNull);
        rig.complete(0, '<p>late edit</p>');
        await _flush();
        expect(
          rig.row(12)!.raw,
          newerCanonical ? 'newer server edit' : 'before',
        );
        expect(rig.row(12)!.canonicalReceived, isTrue);
        expect(rig.row(12)!.provisionalCooked, isNull);
        if (!newerCanonical) {
          expect(rig.row(12)!.reactions.single.emoji, 'heart');
        }
      },
    );
  }
}
