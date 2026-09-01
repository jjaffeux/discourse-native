import 'package:discourse_native/src/plugins/chat/chat_drawer_preferences_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  test('uses the web drawer size defaults when no preference exists', () async {
    final store = ChatDrawerPreferencesStore(
      persistence: _MemoryChatDrawerPreferencesPersistence(),
    );

    expect(await store.readPreferredDisplayMode(), isNull);
    expect(await store.readDrawerSize(), (
      width: ChatDrawerPreferencesStore.defaultWidth,
      height: ChatDrawerPreferencesStore.defaultHeight,
    ));
  });

  test('round-trips each preferred display mode', () async {
    final persistence = _MemoryChatDrawerPreferencesPersistence();
    final store = ChatDrawerPreferencesStore(persistence: persistence);

    for (final mode in ChatPreferredDisplayMode.values) {
      await store.writePreferredDisplayMode(mode);

      expect(persistence.displayMode, switch (mode) {
        ChatPreferredDisplayMode.drawer => 'DRAWER_CHAT',
        ChatPreferredDisplayMode.fullPage => 'FULL_PAGE_CHAT',
      });
      expect(await store.readPreferredDisplayMode(), mode);
    }
  });

  test('ignores an unknown persisted display mode', () async {
    final persistence = _MemoryChatDrawerPreferencesPersistence()
      ..displayMode = 'detached';
    final store = ChatDrawerPreferencesStore(persistence: persistence);

    expect(await store.readPreferredDisplayMode(), isNull);
  });

  test(
    'restores and independently clamps persisted drawer dimensions',
    () async {
      final persistence = _MemoryChatDrawerPreferencesPersistence()
        ..width = 249
        ..height = 620;
      final store = ChatDrawerPreferencesStore(persistence: persistence);

      expect(await store.readDrawerSize(), (
        width: ChatDrawerPreferencesStore.minimumWidth,
        height: 620.0,
      ));

      persistence
        ..width = 512
        ..height = 299;
      expect(await store.readDrawerSize(), (
        width: 512.0,
        height: ChatDrawerPreferencesStore.minimumHeight,
      ));
    },
  );

  test('defaults malformed drawer dimensions independently', () async {
    final persistence = _MemoryChatDrawerPreferencesPersistence()
      ..width = double.nan
      ..height = 620;
    final store = ChatDrawerPreferencesStore(persistence: persistence);

    expect(await store.readDrawerSize(), (
      width: ChatDrawerPreferencesStore.defaultWidth,
      height: 620.0,
    ));

    persistence
      ..width = 512
      ..height = double.infinity;
    expect(await store.readDrawerSize(), (
      width: 512.0,
      height: ChatDrawerPreferencesStore.defaultHeight,
    ));
  });

  test('clamps persisted writes and ignores non-finite drawer sizes', () async {
    final persistence = _MemoryChatDrawerPreferencesPersistence();
    final store = ChatDrawerPreferencesStore(persistence: persistence);

    await store.writeDrawerSize(width: 100, height: -20);

    expect(persistence.sizeWrites, <ChatDrawerSize>[
      (
        width: ChatDrawerPreferencesStore.minimumWidth,
        height: ChatDrawerPreferencesStore.minimumHeight,
      ),
    ]);

    await store.writeDrawerSize(width: double.nan, height: 540);
    await store.writeDrawerSize(width: 410, height: double.infinity);

    expect(persistence.sizeWrites, hasLength(1));
  });

  test('SharedPreferences persistence round-trips all preferences', () async {
    const store = ChatDrawerPreferencesStore();

    await store.writePreferredDisplayMode(ChatPreferredDisplayMode.fullPage);
    await store.writeDrawerSize(width: 480, height: 610);

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString('discourse_chat_preferred_mode'),
      'FULL_PAGE_CHAT',
    );
    expect(preferences.getDouble('discourse_chat_drawer_size_width'), 480);
    expect(preferences.getDouble('discourse_chat_drawer_size_height'), 610);
    expect(
      await const ChatDrawerPreferencesStore().readPreferredDisplayMode(),
      ChatPreferredDisplayMode.fullPage,
    );
    expect(await const ChatDrawerPreferencesStore().readDrawerSize(), (
      width: 480.0,
      height: 610.0,
    ));
  });
}

final class _MemoryChatDrawerPreferencesPersistence
    implements ChatDrawerPreferencesPersistence {
  String? displayMode;
  double? width;
  double? height;
  final List<ChatDrawerSize> sizeWrites = [];

  @override
  Future<String?> readPreferredDisplayMode() async => displayMode;

  @override
  Future<({double? width, double? height})> readDrawerSize() async =>
      (width: width, height: height);

  @override
  Future<bool> writePreferredDisplayMode(String value) async {
    displayMode = value;
    return true;
  }

  @override
  Future<bool> writeDrawerSize({
    required double width,
    required double height,
  }) async {
    this.width = width;
    this.height = height;
    sizeWrites.add((width: width, height: height));
    return true;
  }
}
