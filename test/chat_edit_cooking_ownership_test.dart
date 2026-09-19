import 'dart:async';

import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/plugin_api/cooking_plugin.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_cooking_coordinator.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_controller_test.dart' as fixtures;
import 'support/fakes.dart';
import 'support/manual_scheduler.dart';

const _site = fixtures.site;

void main() {
  for (final state in ['queued', 'active', 'ready']) {
    test(
      'closing a $state editor preserves the other editor and its save',
      () async {
        final rig = _Rig();
        final firstOwner = Object();
        final secondOwner = Object();
        rig.prepare(firstOwner, 'first draft');
        if (state != 'queued') {
          await rig.debounce();
          if (state == 'ready') {
            rig.complete(0, '<p>first ready</p>');
            await _flush();
          }
        }
        rig.prepare(secondOwner, 'second draft');
        rig.chat.cancelEditCooking(_site, 12, owner: firstOwner);
        expect(rig.watchedSources.values, ['second draft']);
        await rig.debounce();
        if (state == 'active') {
          // Retiring a consumer must not free its physical worker slot early.
          expect(rig.requests, hasLength(1));
          rig.complete(0, '<p>retired first result</p>');
          await _flush();
        }
        expect(rig.requests.last.raw, 'second draft');
        rig.complete(rig.requests.length - 1, '<p>second ready</p>');
        await _flush();
        final requestsBeforeSave = rig.requests.length;

        final saving = rig.chat.editMessage(
          _site,
          12,
          'second draft',
          cookingOwner: secondOwner,
        );
        expect(rig.message.provisionalCooked, '<p>second ready</p>');
        expect(rig.message.raw, 'second draft');
        expect(await saving, isNull);
        expect(rig.api.chatMessagesEdited.single.message, 'second draft');
        expect(rig.requests, hasLength(requestsBeforeSave));
      },
    );
  }

  test(
    'saving cannot borrow another editor\'s ready HTML for identical raw',
    () async {
      final rig = _Rig();
      final preparedOwner = Object();
      final savingOwner = Object();
      rig.prepare(preparedOwner, 'shared source');
      await rig.debounce();
      rig.complete(0, '<p>other editor ready</p>');
      await _flush();

      final saving = rig.chat.editMessage(
        _site,
        12,
        'shared source',
        cookingOwner: savingOwner,
      );
      expect(rig.message.provisionalCooked, isNull);
      expect(rig.message.raw, 'shared source');
      await _flush();
      expect(rig.requests, hasLength(2));
      rig.complete(1, '<p>submitted source</p>');
      await _flush();
      expect(rig.message.provisionalCooked, '<p>submitted source</p>');
      expect(await saving, isNull);
    },
  );

  test('direct callers can still prepare and save without an owner', () async {
    final rig = _Rig();
    rig.chat.prepareEditCooking(_site, rig.message, 'direct edit');
    await rig.debounce();
    rig.complete(0, '<p>direct ready</p>');
    await _flush();
    final saving = rig.chat.editMessage(_site, 12, 'direct edit');
    expect(rig.message.provisionalCooked, '<p>direct ready</p>');
    expect(await saving, isNull);
    expect(rig.requests, hasLength(1));
    rig.chat.cancelEditCooking(_site, 12);
    expect(rig.watchedSources, isEmpty);
  });
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

final class _Rig {
  _Rig() {
    final host = PluginCookingHost(
      request:
          ({
            required siteUrl,
            required raw,
            profile = CookingProfile.post,
            context = const CookingContext(),
            cachedMetadata,
          }) => CookingRequest(
            raw: raw,
            profile: profile,
            snapshot: CookingSnapshot(
              siteId: siteUrl,
              accountId: '7',
              context: context,
            ),
          ),
      cook: (request) {
        requests.add(request);
        final completion = Completer<CookingResult>();
        completions.add(completion);
        return completion.future;
      },
      watch: ({required siteUrl, required raw, required onChanged}) {
        final token = Object();
        watchedSources[token] = raw;
        return () => watchedSources.remove(token);
      },
    );
    chat = ChatController(
      api: api,
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
    store.put(_site, fixtures.message(12, raw: 'before', authorId: 7));
    addTearDown(chat.dispose);
  }

  final api = FakeDiscourseApi();
  final store = Store();
  final timers = ManualScheduler();
  final requests = <CookingRequest>[];
  final completions = <Completer<CookingResult>>[];
  final watchedSources = <Object, String>{};
  late final ChatController chat;

  ChatMessage get message => store.read<ChatMessage>(_site, 12)!;

  void prepare(Object owner, String raw) =>
      chat.prepareEditCooking(_site, message, raw, owner: owner);

  Future<void> debounce() async {
    timers.advance(const Duration(milliseconds: 40));
    await _flush();
  }

  void complete(int index, String html) => completions[index].complete(
    CookingResult(html: html).forRequest(requests[index]),
  );
}
