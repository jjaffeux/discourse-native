import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _other = 'https://other.discourse.org';
const _channel = ChatChannel(
  id: 9,
  title: 'Support',
  kind: ChatChannelKind.category,
  membership: ChatMembership(following: true, lastReadMessageId: 10),
);
ChatChannels _snapshot(String title) => ChatChannels(
  public: [
    _channel.withRemoteMetadata(title: title, slug: null, description: null),
  ],
  direct: const [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('forgotten list cleanup cannot finish its successor request', () async {
    final fixture = _Fixture();
    final old = fixture.chat.loadChannels(_site);
    await fixture.tick();
    fixture.chat.forget(_site);
    final current = fixture.chat.loadChannels(_site);
    await fixture.tick();
    expect(fixture.api.lists, hasLength(2));
    expect(fixture.chat.loadChannels(_site), same(current));

    fixture.api.lists.first.complete(_snapshot('Old'));
    await old;
    expect(fixture.chat.channelsLoading(_site), isTrue);
    expect(fixture.chat.channelsLoaded(_site), isFalse);
    expect(fixture.chat.channel(_site, 9), isNull);
    expect(fixture.chat.loadChannels(_site), same(current));

    fixture.api.lists.last.complete(_snapshot('Current'));
    await current;
    expect(fixture.chat.publicChannels(_site).single.title, 'Current');
    expect(fixture.chat.channelsLoading(_site), isFalse);
  });

  test(
    'lease replacement replaces directory work and keeps conversation identity',
    () async {
      final fixture = _Fixture();
      final stream = fixture.chat.streamListenable(_site, 9);
      final old = fixture.chat.loadChannels(_site);
      await fixture.tick();
      fixture.lifecycle.invalidate(_site);
      final current = fixture.chat.loadChannels(_site);
      await fixture.tick();
      fixture.api.lists.first.complete(_snapshot('Old'));
      await old;
      expect(fixture.chat.streamListenable(_site, 9), same(stream));
      expect(fixture.chat.channelsLoading(_site), isTrue);
      expect(fixture.chat.publicChannels(_site), isEmpty);

      fixture.api.lists.last.complete(_snapshot('Current'));
      await current;
      expect(fixture.chat.publicChannels(_site).single.title, 'Current');
      expect(fixture.chat.streamListenable(_site, 9), same(stream));
    },
  );

  test('old star failure cannot roll back a successor account write', () async {
    final fixture = _Fixture();
    fixture.store.put(_site, _channel);
    final old = fixture.chat.updateChannelStarred(_site, 9, true);
    await fixture.tick();
    fixture.lifecycle.invalidate(_site);
    fixture.store.put(
      _site,
      _channel.withTrackingState(tracking: const ChatTracking(unreadCount: 7)),
    );
    final current = fixture.chat.updateChannelStarred(_site, 9, true);
    await fixture.tick();
    expect(fixture.api.stars, hasLength(2));

    fixture.api.stars.first.completeError(
      const WriteException(WriteFailure.forbidden),
    );
    expect(await old, isNotNull);
    expect(fixture.chat.channel(_site, 9)!.membership.starred, isTrue);
    expect(fixture.chat.channel(_site, 9)!.tracking.unreadCount, 7);
    expect(fixture.chat.channelStarWriteInFlight(_site, 9), isTrue);

    fixture.api.stars.last.complete();
    expect(await current, isNull);
    expect(fixture.chat.channelStarWriteInFlight(_site, 9), isFalse);
  });

  test(
    'forget disowns a credential wait without requiring host invalidation',
    () async {
      final credentials = _GatedCredentials();
      final fixture = _Fixture(credentials: credentials);
      final gate = Completer<void>();
      credentials.gate = gate;
      final old = fixture.chat.loadChannels(_site);
      await fixture.tick();
      fixture.chat.forget(_site);
      credentials.gate = null;
      final current = fixture.chat.loadChannels(_site);
      await fixture.tick();
      expect(fixture.api.lists, hasLength(1));
      gate.complete();
      await old;
      expect(fixture.api.lists, hasLength(1));
      expect(fixture.chat.channelsLoading(_site), isTrue);
      fixture.api.lists.single.complete(_snapshot('Current'));
      await current;
      expect(fixture.chat.publicChannels(_site).single.title, 'Current');
    },
  );

  test(
    'forget preserves another site directory and observed conversation',
    () async {
      final fixture = _Fixture();
      final first = fixture.chat.loadChannels(_site);
      await fixture.tick();
      fixture.api.lists.last.complete(_snapshot('First'));
      await first;
      final other = fixture.chat.loadChannels(_other);
      await fixture.tick();
      fixture.api.lists.last.complete(_snapshot('Other'));
      await other;
      final stream = fixture.chat.streamListenable(_other, 9);
      fixture.chat.forget(_site);
      expect(fixture.chat.publicChannels(_site), isEmpty);
      expect(fixture.chat.publicChannels(_other).single.title, 'Other');
      expect(fixture.chat.streamListenable(_other, 9), same(stream));
    },
  );

  test(
    'controller disposal retires pending directory replies and later calls',
    () async {
      final fixture = _Fixture();
      final reading = fixture.chat.loadChannels(_site);
      await fixture.tick();
      fixture.dispose();
      fixture.api.lists.single.complete(_snapshot('Late'));
      await reading;
      await fixture.chat.loadChannels(_site, force: true);
      expect(await fixture.chat.ensureChannel(_site, 9), isNull);
      expect(fixture.chat.channelsLoading(_site), isFalse);
      expect(fixture.chat.publicChannels(_site), isEmpty);
      expect(fixture.store.read<ChatChannel>(_site, 9), isNull);
      expect(fixture.api.lists, hasLength(1));
    },
  );
}

final class _Fixture {
  _Fixture({_GatedCredentials? credentials}) {
    final reader = credentials ?? _GatedCredentials();
    reader.keys[_site] = 'key';
    reader.keys[_other] = 'key';
    chat = ChatController(
      api: api,
      requests: FakePluginRequestHost(
        credentials: reader,
        lifecycle: lifecycle,
      ),
      store: store,
    );
    addTearDown(dispose);
  }

  final api = _DirectoryApi();
  final store = Store();
  final lifecycle = SiteLifecycle();
  late final ChatController chat;
  bool _disposed = false;

  Future<void> tick() => Future<void>.delayed(Duration.zero);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    chat.dispose();
  }
}

final class _GatedCredentials extends FakeApiCredentialReader {
  Completer<void>? gate;

  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    final held = gate;
    if (held != null) await held.future;
    return keys[siteUrl];
  }
}

final class _DirectoryApi extends FakeDiscourseApi {
  final lists = <Completer<ChatChannels>>[];
  final stars = <Completer<void>>[];

  @override
  Future<ChatChannels> chatChannels({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) {
    final result = Completer<ChatChannels>();
    lists.add(result);
    return result.future;
  }

  @override
  Future<void> updateChatChannelStarred({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required bool starred,
    String? clientId,
  }) {
    final result = Completer<void>();
    stars.add(result);
    return result.future;
  }
}
