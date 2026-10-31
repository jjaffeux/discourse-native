import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_stream.dart';
import 'package:discourse_native/src/plugins/chat/chat_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ChatMessage _message(int id, String createdAt) => ChatMessage(
  id: id,
  channelId: 9,
  cooked: '<p>Message $id</p>',
  author: const ChatMessageAuthor(id: 2, username: 'sam'),
  createdAt: DateTime.parse(createdAt),
);

void main() {
  late TimezoneEnvironment environment;
  late PluginTimezoneHost host;
  setUp(() async {
    environment = TimezoneEnvironment.forTesting(
      detectDeviceTimezone: () async => 'Europe/Paris',
    );
    await environment.initialize();
    host = PluginTimezoneHost(
      readerTimezone: environment.readerTimezone,
      location: environment.location,
      timezoneNames: () => environment.timezoneNames,
      changes: environment,
    );
  });
  tearDown(() => environment.dispose());

  test('account clock and stream dates agree across midnight', () {
    final time = ChatTime.forReader(
      zones: host,
      accountTimezone: 'America/Los_Angeles',
    );
    final messages = [
      _message(1, '2026-10-31T06:59:00Z'),
      _message(2, '2026-10-31T07:01:00Z'),
    ];
    final items = buildChatStream(messages, time: time);

    expect(time.local(messages.first.createdAt!).hour, 23);
    expect(time.local(messages.first.createdAt!).day, 30);
    expect(time.local(messages.last.createdAt!).hour, 0);
    expect(items.whereType<ChatStreamDay>().map((item) => item.day), [
      DateTime(2026, 10, 30),
      DateTime(2026, 10, 31),
    ]);
    final incremental = appendChatStream(
      existingItems: buildChatStream([messages.first], time: time),
      existingTrailing: [messages.first],
      appended: [messages.last],
      time: time,
    );
    expect(incremental, items);
  });

  test('repeated DST hour stays on one day and retains instant order', () {
    final time = ChatTime.forReader(
      zones: host,
      accountTimezone: 'America/New_York',
    );
    final messages = [
      _message(1, '2026-11-01T05:30:00Z'),
      _message(2, '2026-11-01T06:30:00Z'),
    ];

    expect(time.local(messages.first.createdAt!).hour, 1);
    expect(time.local(messages.last.createdAt!).hour, 1);
    expect(
      time.local(messages.first.createdAt!).timeZoneOffset,
      const Duration(hours: -4),
    );
    expect(
      time.local(messages.last.createdAt!).timeZoneOffset,
      const Duration(hours: -5),
    );
    final stream = buildChatStream(messages, time: time);
    expect(stream.whereType<ChatStreamDay>(), hasLength(1));
    expect(stream.whereType<ChatStreamMessage>().map((row) => row.id), [1, 2]);
  });

  test('missing or invalid account preference uses the device zone', () {
    for (final configured in [null, 'Invalid/Timezone']) {
      final time = ChatTime.forReader(zones: host, accountTimezone: configured);
      final local = time.local(DateTime.utc(2026, 7, 1, 22, 30));
      expect(local.day, 2);
      expect(local.hour, 0);
    }
  });

  test('without a timezone host the clock uses only the device wall time', () {
    final instant = DateTime.utc(2026, 7, 1, 22, 30);
    final time = ChatTime.forReader(accountTimezone: 'America/Los_Angeles');

    expect(time.name, 'device');
    expect(time.local(instant), instant.toLocal());
  });

  testWidgets('day separator names today using the reader calendar', (
    tester,
  ) async {
    final time = ChatTime.forReader(
      zones: host,
      accountTimezone: 'America/Los_Angeles',
    );
    final now = time.local(DateTime.utc(2026, 10, 31, 6, 59));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: StreamDaySeparator(day: DateTime(2026, 10, 30), now: now),
        ),
      ),
    );

    expect(find.text('Today'), findsOneWidget);
  });
}
