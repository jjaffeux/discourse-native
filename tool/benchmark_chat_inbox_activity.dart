import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox_filters.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart';

import '../test/support/fakes.dart';

const _site = 'https://inbox-derived.example';

class _Chat extends ChatController {
  _Chat({required super.api, required super.requests, required super.store});
  void emit() => notifySafely();
}

int _checksum(List<ChatChannel> channels) {
  var value = 0;
  for (var i = 0; i < channels.length; i++) {
    value += (i + 1) * channels[i].id;
  }
  return value;
}

List<ChatChannel> _oracle(
  Iterable<ChatChannel> channels,
  ChatInboxFilter filter,
) {
  final ranked =
      [
        for (final channel in channels)
          if (!filter.unreadOnly ||
              channel.tracking.unreadCount > 0 ||
              channel.urgentCount > 0 ||
              channel.unreadThreadOverview.values.any(
                (at) =>
                    channel.membership.lastViewedAt == null ||
                    !at.isBefore(channel.membership.lastViewedAt!),
              ))
            (
              channel: channel,
              activity: [
                if ((channel.lastMessageId ?? 0) > 0 &&
                    channel.lastMessageAt != null)
                  channel.lastMessageAt!,
                ...channel.unreadThreadOverview.values,
              ]..sort(),
            ),
      ]..sort((a, b) {
        final at = a.activity.lastOrNull, bt = b.activity.lastOrNull;
        final recency = at == null
            ? (bt == null ? 0 : 1)
            : bt == null
            ? -1
            : bt.compareTo(at);
        if (recency != 0) return recency;
        final title = a.channel.title.toLowerCase().compareTo(
          b.channel.title.toLowerCase(),
        );
        return title != 0 ? title : a.channel.id.compareTo(b.channel.id);
      });
  return [for (final entry in ranked) entry.channel];
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kProfileMode) throw StateError('Run in profile mode');
  try {
    final rows = <Map<String, Object?>>[];
    final profiles = <Object?>[];
    for (final (size, threads) in [
      (50, 32),
      (175, 32),
      (1000, 32),
      (175, 256),
    ]) {
      final now = DateTime.utc(2026, 10, 1);
      final channels = List.generate(
        size,
        (i) => ChatChannel.fromJson(
          {
            'id': i + 1,
            'title': 'Channel ${size - i}',
            'chatable_type': i < size * 4 ~/ 7 ? 'Category' : 'DirectMessage',
            'threading_enabled': true,
            'current_user_membership': {
              'following': true,
              'last_viewed_at': now.toIso8601String(),
            },
            'last_message': {
              'id': i + 1,
              'created_at': now
                  .add(Duration(minutes: (i * 13) % size))
                  .toIso8601String(),
            },
          },
          _site,
          unreadThreadOverview: {
            for (var t = 0; t < threads; t++)
              t: now.add(Duration(minutes: (i * 37 + t * 11) % size)),
          },
        ),
      );
      final store = Store();
      final chat = _Chat(
        api: FakeDiscourseApi(
          chatChannelsBySite: {
            _site: ChatChannels(
              public: channels.where((c) => !c.isDirectMessage).toList(),
              direct: channels.where((c) => c.isDirectMessage).toList(),
            ),
          },
        ),
        requests: FakePluginRequestHost(
          credentials: FakeApiCredentialReader()..keys[_site] = 'key',
        ),
        store: store,
      );
      await chat.loadChannels(_site);
      for (final unread in [false, true]) {
        final filter = ChatInboxFilter(unreadOnly: unread);
        final reference = _oracle(channels, filter);
        final expected = _checksum(reference);
        expect(
          chatInboxConversations(
            chat,
            _site,
            filter,
          ).map((c) => c.id).join(','),
          reference.map((c) => c.id).join(','),
        );
        expect(chatInboxConversations(chat, _site, filter).length, size);
        for (final event in ['unchanged', 'preview']) {
          var checksum = 0;
          var callbacks = 0;
          var sequence = 0;
          void observe() {
            checksum += _checksum(chatInboxConversations(chat, _site, filter));
            callbacks++;
          }

          chat.addListener(observe);
          int run() {
            final oldSum = checksum, oldCalls = callbacks;
            final oldGeneration = store.generationOf<ChatChannel>(_site);
            final watch = Stopwatch()..start();
            for (var n = 0; n < 40; n++) {
              if (event == 'preview') {
                final id = n % size + 1;
                store.put(
                  _site,
                  chat
                      .channel(_site, id)!
                      .withLastMessagePreview('Preview ${sequence++}'),
                );
              }
              chat.emit();
            }
            watch.stop();
            expect(checksum - oldSum, expected * 40);
            expect(callbacks - oldCalls, 40);
            expect(
              store.generationOf<ChatChannel>(_site) - oldGeneration,
              event == 'preview' ? 40 : 0,
            );
            return watch.elapsedMicroseconds;
          }

          for (var warm = 0; warm < 5; warm++) {
            run();
          }
          for (var round = 0; round < 7; round++) {
            rows.add({
              'size': size,
              'threads': threads,
              'unreadOnly': unread,
              'event': event,
              'round': round,
              'elapsedUs': run(),
              'events': 40,
              'checksum': expected,
              'callbacks': 40,
              'errors': 0,
            });
          }
          chat.removeListener(observe);
        }
      }
      if (Platform.environment['CHAT_DERIVED_PROFILE'] == '1' &&
          size == 175 &&
          threads == 32) {
        final uri = (await developer.Service.getInfo()).serverWebSocketUri!;
        final service = await vmServiceConnectUri(uri.toString());
        final isolate = developer.Service.getIsolateId(Isolate.current)!;
        for (final unread in [false, true]) {
          final filter = ChatInboxFilter(unreadOnly: unread);
          final expected = _checksum(_oracle(channels, filter));
          expect(
            _checksum(chatInboxConversations(chat, _site, filter)),
            expected,
          );
          final start = developer.Timeline.now;
          var iterations = 0, checksum = 0;
          while (developer.Timeline.now - start < 2000000) {
            checksum += _checksum(chatInboxConversations(chat, _site, filter));
            iterations++;
          }
          final end = developer.Timeline.now;
          expect(checksum, expected * iterations);
          final samples = await service.getCpuSamples(
            isolate,
            start,
            end - start,
          );
          profiles.add({
            'size': size,
            'threads': threads,
            'unreadOnly': unread,
            'iterations': iterations,
            'checksum': checksum,
            'cpu': samples.toJson(),
          });
        }
        try {
          final classes = await service.getClassList(isolate);
          final iterator = classes.classes!.singleWhere(
            (c) => c.name == '_CompactIterator',
          );
          await service.setTraceClassAllocation(isolate, iterator.id!, true);
          try {
            for (final unread in [false, true]) {
              final filter = ChatInboxFilter(unreadOnly: unread);
              for (final event in ['unchanged', 'preview', 'viewed']) {
                chatInboxConversations(chat, _site, filter);
                for (var repeat = 0; repeat < 3; repeat++) {
                  final held = chat.channel(_site, 1)!;
                  if (event == 'preview') {
                    store.put(
                      _site,
                      held.withLastMessagePreview('Trace $repeat'),
                    );
                  }
                  if (event == 'viewed') {
                    store.put(
                      _site,
                      held.withLastViewedAt(
                        now.add(Duration(microseconds: repeat + 1)),
                      ),
                    );
                  }
                  await service.clearCpuSamples(isolate);
                  final start = developer.Timeline.now;
                  final result = chatInboxConversations(chat, _site, filter);
                  final end = developer.Timeline.now;
                  expect(result.length, size);
                  final trace = await service.getAllocationTraces(
                    isolate,
                    classId: iterator.id!,
                    timeOriginMicros: start,
                    timeExtentMicros: end - start,
                  );
                  final activityFrames = <int>{
                    for (final (index, function) in trace.functions!.indexed)
                      if (function.function case vm.FuncRef(name: final name)
                          when name == 'chatInboxActivityAt' ||
                              name == 'get:latestUnreadThreadAt' ||
                              name == 'get:unreadThreadsCountSinceLastViewed' ||
                              name == '_bounds' ||
                              name == 'countSince')
                        index,
                  };
                  final allocations = trace.samples!
                      .where(
                        (sample) => sample.stack!.any(activityFrames.contains),
                      )
                      .length;
                  profiles.add({
                    'kind': 'threadIteratorAllocation',
                    'unreadOnly': unread,
                    'event': event,
                    'repeat': repeat,
                    'allocations': allocations,
                    'threadsPerIterator': threads,
                    'checksum': _checksum(result),
                  });
                }
              }
            }
          } finally {
            await service.setTraceClassAllocation(isolate, iterator.id!, false);
          }
        } on vm.RPCError catch (error) {
          profiles.add({
            'kind': 'allocationUnavailable',
            'code': error.code,
            'message': error.message,
          });
        }
        await service.dispose();
      }
      chat.dispose();
    }
    stdout.writeln(
      'CHAT_INBOX_ACTIVITY_REPORT ${jsonEncode({'mode': 'warmed macOS Flutter profile AOT real ChatController notification path, no rendering/device FPS', 'sdk': Platform.version, 'processors': Platform.numberOfProcessors, 'rows': rows, 'profiles': profiles})}',
    );
    exit(0);
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(1);
  }
}

void expect(Object? actual, Object? expected) {
  if (actual != expected) throw StateError('Expected $expected, got $actual');
}
