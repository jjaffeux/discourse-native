import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox_filters.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart';

import 'support/counting_thread_overview.dart';
import 'support/fakes.dart';

const _site = 'https://inbox-benchmark.example';
const _burst = 40;
const _threads = 32;
typedef _Project =
    List<ChatChannel> Function(ChatController, String, ChatInboxFilter);

List<ChatChannel> _baseline(
  ChatController chat,
  String siteUrl,
  ChatInboxFilter filter,
) {
  if (filter.kind == ChatInboxKind.voiceRooms) return const [];
  final settings = chat.siteConfigFor(siteUrl).chatSettings;
  return [
      if (settings.publicChannelsEnabled &&
          filter.kind != ChatInboxKind.directMessages)
        ...chat.publicChannels(siteUrl),
      if (filter.kind != ChatInboxKind.channels)
        ...chat.directChannels(siteUrl),
    ].where((channel) => !filter.unreadOnly || channel.badge.isVisible).toList()
    ..sort((a, b) {
      final aTime = chatInboxActivityAt(a);
      final bTime = chatInboxActivityAt(b);
      final recent = aTime == null
          ? (bTime == null ? 0 : 1)
          : bTime == null
          ? -1
          : bTime.compareTo(aTime);
      if (recent != 0) return recent;
      final title = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      return title != 0 ? title : a.id.compareTo(b.id);
    });
}

final class _BurstChat extends ChatController {
  _BurstChat({
    required super.api,
    required super.requests,
    required super.store,
  });
  void emit() => notifySafely();
}

Future<({_BurstChat chat, Store store, List<CountingThreadOverview> counts})>
_fixture(int size, {bool counting = false}) async {
  final counts = <CountingThreadOverview>[];
  final channels = List.generate(size, (i) {
    final overview = <int, DateTime>{
      for (var t = 0; t < _threads; t++)
        t: DateTime.utc(
          2026,
          10,
          1,
        ).add(Duration(minutes: (i * 37 + t * 11) % size)),
    };
    final measured = counting ? CountingThreadOverview(overview) : null;
    if (measured != null) counts.add(measured);
    return ChatChannel(
      id: i + 1,
      title: 'Channel ${size - i}',
      slug: 'channel-${size - i}',
      kind: i % 5 == 0
          ? ChatChannelKind.directMessage
          : ChatChannelKind.category,
      membership: ChatMembership(
        following: true,
        lastViewedAt: DateTime.utc(2026, 10, 1),
      ),
      unreadThreadOverview: measured ?? overview,
      threadingEnabled: true,
      lastMessageId: i + 1,
      lastMessageAt: DateTime.utc(
        2026,
        10,
        1,
      ).add(Duration(minutes: (i * 13) % size)),
    );
  });
  final store = Store();
  final api = FakeDiscourseApi(
    chatChannelsBySite: {
      _site: ChatChannels(
        public: channels.where((c) => !c.isDirectMessage).toList(),
        direct: channels.where((c) => c.isDirectMessage).toList(),
      ),
    },
  );
  final chat = _BurstChat(
    api: api,
    requests: FakePluginRequestHost(
      lifecycle: SiteLifecycle(),
      credentials: FakeApiCredentialReader()..keys[_site] = 'key',
    ),
    store: store,
  );
  await chat.loadChannels(_site);
  for (final count in counts) {
    count.visits = 0;
  }
  return (chat: chat, store: store, counts: counts);
}

int _consume(List<ChatChannel> channels) {
  var checksum = 0;
  for (var i = 0; i < channels.length; i++) {
    checksum += (i + 1) * channels[i].id;
  }
  return checksum;
}

void _verifyBurst(
  ({int callbacks, int checksum, int writes}) actual,
  int checksum,
  int writes,
) {
  if (actual.callbacks != _burst ||
      actual.checksum != checksum ||
      actual.writes != writes) {
    throw StateError(
      'Notification burst did not produce the expected work: $actual',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'chat inbox ordering burst benchmark',
    () async {
      final output =
          Platform.environment['CHAT_INBOX_BENCH_OUTPUT'] ??
          '/tmp/chat-inbox-sort.json';
      final isolate = developer.Service.getIsolateId(Isolate.current)!;
      final info = await developer.Service.getInfo();
      final service = await vmServiceConnectUri(
        info.serverWebSocketUri!.toString(),
      );
      addTearDown(service.dispose);
      final results = <Map<String, Object?>>[];
      for (final size in [50, 250, 1000]) {
        final fixture = await _fixture(size);
        final counted = await _fixture(size, counting: true);
        addTearDown(fixture.chat.dispose);
        addTearDown(counted.chat.dispose);
        for (final unread in [false, true]) {
          final filter = ChatInboxFilter(unreadOnly: unread);
          final expected = _baseline(
            fixture.chat,
            _site,
            filter,
          ).map((c) => c.id).toList();
          expect(
            chatInboxConversations(
              fixture.chat,
              _site,
              filter,
            ).map((c) => c.id),
            expected,
          );
          for (final entry in {
            'baseline': _baseline,
            'candidate': chatInboxConversations,
          }.entries) {
            final before = counted.counts.fold(0, (sum, c) => sum + c.visits);
            final projected = entry.value(counted.chat, _site, filter);
            final visits =
                counted.counts.fold(0, (sum, c) => sum + c.visits) - before;
            expect(projected.map((c) => c.id), expected);
            results.add({
              'size': size,
              'unreadOnly': unread,
              'side': entry.key,
              'kind': 'work',
              'threadVisits': visits,
              'checksum': _consume(projected),
            });
          }
          for (final event in ['unchanged', 'preview']) {
            var checksum = 0;
            var callbacks = 0;
            var burstSequence = 0;
            final expectedChecksum =
                _consume(_baseline(fixture.chat, _site, filter)) * _burst;
            final expectedWrites = event == 'preview' ? _burst : 0;
            _Project currentProjection = _baseline;
            void projectNotification() {
              checksum += _consume(
                currentProjection(fixture.chat, _site, filter),
              );
              callbacks++;
            }

            fixture.chat.addListener(projectNotification);
            ({int callbacks, int checksum, int writes}) run(_Project project) {
              currentProjection = project;
              final beforeChecksum = checksum;
              final beforeCallbacks = callbacks;
              final beforeGeneration = fixture.store.generationOf<ChatChannel>(
                _site,
              );
              final sequence = burstSequence++;
              for (var i = 0; i < _burst; i++) {
                if (event == 'preview') {
                  final id = i % size + 1;
                  final held = fixture.chat.channel(_site, id)!;
                  fixture.store.put(
                    _site,
                    held.withLastMessagePreview('Preview $sequence:$i'),
                  );
                }
                fixture.chat.emit();
              }
              return (
                callbacks: callbacks - beforeCallbacks,
                checksum: checksum - beforeChecksum,
                writes:
                    fixture.store.generationOf<ChatChannel>(_site) -
                    beforeGeneration,
              );
            }

            for (var warm = 0; warm < 3; warm++) {
              _verifyBurst(run(_baseline), expectedChecksum, expectedWrites);
              _verifyBurst(
                run(chatInboxConversations),
                expectedChecksum,
                expectedWrites,
              );
            }
            for (var round = 0; round < 7; round++) {
              final entries = round.isEven
                  ? {
                      'baseline': _baseline,
                      'candidate': chatInboxConversations,
                    }.entries
                  : {
                      'candidate': chatInboxConversations,
                      'baseline': _baseline,
                    }.entries;
              for (final entry in entries) {
                final watch = Stopwatch()..start();
                final observed = run(entry.value);
                watch.stop();
                _verifyBurst(observed, expectedChecksum, expectedWrites);
                results.add({
                  'size': size,
                  'unreadOnly': unread,
                  'event': event,
                  'side': entry.key,
                  'kind': 'timing',
                  'round': round,
                  'events': _burst,
                  'elapsedUs': watch.elapsedMicroseconds,
                  'checksum': observed.checksum,
                  'callbacks': observed.callbacks,
                  'previewChanges': observed.writes,
                });
              }
            }
            fixture.chat.removeListener(projectNotification);
          }
        }
        for (final entry in {
          'baseline': _baseline,
          'candidate': chatInboxConversations,
        }.entries) {
          final start = developer.Timeline.now;
          var checksum = 0;
          while (developer.Timeline.now - start < 500000) {
            checksum += _consume(
              entry.value(fixture.chat, _site, const ChatInboxFilter()),
            );
          }
          final end = developer.Timeline.now;
          try {
            final samples = await service.getCpuSamples(
              isolate,
              start,
              end - start,
            );
            results.add({
              'size': size,
              'side': entry.key,
              'kind': 'cpu',
              'checksum': checksum,
              'profile': samples.toJson(),
            });
          } on vm.RPCError catch (error) {
            results.add({
              'size': size,
              'side': entry.key,
              'kind': 'cpu',
              'error': error.code,
            });
          }
        }
      }
      final classes = await service.getClassList(isolate);
      final iteratorClass = classes.classes!
          .where((type) => type.name == '_CompactIterator')
          .single;
      await service.setTraceClassAllocation(isolate, iteratorClass.id!, true);
      try {
        for (final size in [50, 250, 1000]) {
          final fixture = await _fixture(size);
          addTearDown(fixture.chat.dispose);
          var callbacks = 0;
          var checksum = 0;
          _Project currentProjection = _baseline;
          void observe() {
            checksum += _consume(
              currentProjection(fixture.chat, _site, const ChatInboxFilter()),
            );
            callbacks++;
          }

          fixture.chat.addListener(observe);
          final expectedChecksum = _consume(
            _baseline(fixture.chat, _site, const ChatInboxFilter()),
          );
          for (var round = 0; round < 6; round++) {
            final entries = round.isEven
                ? {
                    'baseline': _baseline,
                    'candidate': chatInboxConversations,
                  }.entries
                : {
                    'candidate': chatInboxConversations,
                    'baseline': _baseline,
                  }.entries;
            for (final entry in entries) {
              currentProjection = entry.value;
              final expectedAllocations =
                  (results.singleWhere(
                        (row) =>
                            row['kind'] == 'work' &&
                            row['size'] == size &&
                            row['side'] == entry.key &&
                            row['unreadOnly'] == false,
                      )['threadVisits']
                      as int) ~/
                  _threads;
              await service.clearCpuSamples(isolate);
              final beforeCallbacks = callbacks;
              final beforeChecksum = checksum;
              final start = developer.Timeline.now;
              fixture.chat.emit();
              final end = developer.Timeline.now;
              expect(callbacks - beforeCallbacks, 1);
              expect(checksum - beforeChecksum, expectedChecksum);
              final traces = await service.getAllocationTraces(
                isolate,
                classId: iteratorClass.id!,
                timeOriginMicros: start,
                timeExtentMicros: end - start,
              );
              final activityFrames = <int>{
                for (final (index, function) in traces.functions!.indexed)
                  if (function.function case vm.FuncRef(
                    name: 'chatInboxActivityAt',
                  ))
                    index,
              };
              final allocations = traces.samples!
                  .where((sample) => sample.stack!.any(activityFrames.contains))
                  .length;
              results.add({
                'kind': 'allocationTrace',
                'size': size,
                'side': entry.key,
                'round': round,
                'class': iteratorClass.name,
                'events': 1,
                'allocationsInActivity': allocations,
                'expectedFromThreadVisits': expectedAllocations,
                'complete': allocations == expectedAllocations,
              });
            }
          }
          fixture.chat.removeListener(observe);
        }
      } finally {
        await service.setTraceClassAllocation(
          isolate,
          iteratorClass.id!,
          false,
        );
      }
      File(output).writeAsStringSync(
        jsonEncode({
          'mode':
              'warmed Flutter tester debug JIT notification projection; no rendering or device FPS',
          'threadsPerChannel': _threads,
          'sdkVersion': Platform.version,
          'logicalProcessors': Platform.numberOfProcessors,
          'allocationStatus':
              'activity map-iterator traces only; total allocation bytes not measured',
          'results': results,
        }),
      );
      stdout.writeln('Inbox benchmark saved to $output');
    },
    skip: !const bool.fromEnvironment('CHAT_INBOX_SORT_BENCH'),
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
