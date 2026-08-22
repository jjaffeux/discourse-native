import 'dart:async';

import 'package:discourse_native/src/data/emoji_picker_store.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/shell/emoji_picker_controller.dart';
import 'package:flutter_test/flutter_test.dart';

const _siteUrl = 'https://meta.discourse.org';

void main() {
  test(
    'search shows name matches before lazy localized aliases arrive',
    () async {
      final aliases = Completer<Map<String, List<String>>?>();
      final controller = _controller(
        catalog: _catalog([
          const SiteEmoji(name: 'unhappy', url: 'unhappy.png'),
          const SiteEmoji(name: 'smile', url: 'smile.png'),
          const SiteEmoji(name: 'happy_face', url: 'happy.png'),
        ]),
        aliases: ({refresh = false}) => aliases.future,
      );
      addTearDown(controller.dispose);
      await controller.load();

      controller.updateQuery('HAP');
      expect(controller.searchResults.map((emoji) => emoji.name), [
        'happy_face',
        'unhappy',
      ]);
      expect(controller.aliasesLoading, isTrue);

      aliases.complete({
        'smile': ['happy'],
      });
      await pumpEventQueue();

      expect(controller.searchResults.map((emoji) => emoji.name), [
        'happy_face',
        'smile',
        'unhappy',
      ]);
      expect(controller.aliasesLoading, isFalse);
    },
  );

  test('alias failure keeps canonical search and caps it at fifty', () async {
    final controller = _controller(
      catalog: _catalog([
        for (var index = 0; index < 70; index++)
          SiteEmoji(
            name: 'smile_${index.toString().padLeft(2, '0')}',
            url: '$index.png',
          ),
      ]),
      aliases: ({refresh = false}) => Future.error(StateError('offline')),
    );
    addTearDown(controller.dispose);
    await controller.load();

    controller.updateQuery('smile');
    await pumpEventQueue();

    expect(controller.searchResults, hasLength(50));
    expect(controller.searchResults.first.name, 'smile_00');
    expect(controller.searchResults.last.name, 'smile_49');
    expect(controller.error, isNull);
  });

  testWidgets('free-text search waits for the 250 millisecond debounce', (
    tester,
  ) async {
    var aliasLoads = 0;
    final controller = EmojiPickerController(
      siteUrl: _siteUrl,
      context: EmojiPickerContext.topic,
      store: EmojiPickerStore(persistence: _MemoryPersistence()),
      loadCatalog: ({refresh = false}) async =>
          _catalog(const [SiteEmoji(name: 'smile', url: 'smile.png')]),
      loadSearchAliases: ({refresh = false}) async {
        aliasLoads++;
        return const {};
      },
    );
    addTearDown(controller.dispose);
    await controller.load();

    controller.updateQuery('sm');
    expect(controller.searchPending, isTrue);
    expect(controller.searchResults, isEmpty);

    await tester.pump(const Duration(milliseconds: 249));
    expect(controller.searchResults, isEmpty);
    expect(aliasLoads, 0);

    await tester.pump(const Duration(milliseconds: 1));
    expect(controller.searchResults.single.name, 'smile');
    expect(aliasLoads, 1);
  });

  test('favorites follow the current tone but retain explicit tones', () async {
    final store = EmojiPickerStore(persistence: _MemoryPersistence());
    await store.trackEmoji(
      siteUrl: _siteUrl,
      context: EmojiPickerContext.topic,
      emoji: 'wave',
    );
    await store.trackEmoji(
      siteUrl: _siteUrl,
      context: EmojiPickerContext.topic,
      emoji: 'wave',
    );
    await store.trackEmoji(
      siteUrl: _siteUrl,
      context: EmojiPickerContext.topic,
      emoji: 'clap:t3',
    );
    await store.writeSkinTone(siteUrl: _siteUrl, tone: EmojiSkinTone.t5);
    final controller = _controller(
      store: store,
      catalog: _catalog(const [
        SiteEmoji(name: 'wave', url: 'wave.png', tonable: true),
        SiteEmoji(name: 'clap', url: 'clap.png', tonable: true),
      ]),
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.favorites.map((favorite) => favorite.code), [
      'wave:t5',
      'clap:t3',
    ]);

    await controller.clearHistory();
    expect(controller.favorites, isEmpty);
    expect(controller.tone, EmojiSkinTone.t5);
  });

  test('a toned and untoned favorite draw as one cell', () async {
    final store = EmojiPickerStore(persistence: _MemoryPersistence());
    // What the picker records when the same emoji is chosen under two tones:
    // the composer tracks the untoned name, the picker the toned one.
    await store.trackEmoji(
      siteUrl: _siteUrl,
      context: EmojiPickerContext.topic,
      emoji: 'wave',
    );
    await store.trackEmoji(
      siteUrl: _siteUrl,
      context: EmojiPickerContext.topic,
      emoji: 'wave:t5',
    );
    await store.writeSkinTone(siteUrl: _siteUrl, tone: EmojiSkinTone.t5);
    final controller = _controller(
      store: store,
      catalog: _catalog(const [
        SiteEmoji(name: 'wave', url: 'wave.png', tonable: true),
      ]),
    );
    addTearDown(controller.dispose);

    await controller.load();

    // The untoned entry is drawn in the current tone, so both resolve to the
    // same artwork — two identical cells, each spending one of the row's
    // twenty slots.
    expect(controller.favorites.map((favorite) => favorite.code), ['wave:t5']);
  });

  test('retry refreshes a failed catalog', () async {
    var calls = 0;
    final catalog = _catalog(const [SiteEmoji(name: 'wave', url: 'wave.png')]);
    final controller = EmojiPickerController(
      siteUrl: _siteUrl,
      context: EmojiPickerContext.topic,
      store: EmojiPickerStore(persistence: _MemoryPersistence()),
      loadCatalog: ({refresh = false}) async {
        calls++;
        return refresh ? catalog : null;
      },
      loadSearchAliases: ({refresh = false}) async => const {},
    );
    addTearDown(controller.dispose);

    await controller.load();
    expect(controller.error, EmojiPickerController.loadError);

    await controller.retry();
    expect(controller.catalog, catalog);
    expect(controller.error, isNull);
    expect(calls, 2);
  });

  test('retry explicitly refreshes aliases after a degraded search', () async {
    var aliasLoads = 0;
    final catalog = _catalog(const [SiteEmoji(name: 'wave', url: 'wave.png')]);
    final controller = EmojiPickerController(
      siteUrl: 'https://meta.example',
      context: EmojiPickerContext.topic,
      store: EmojiPickerStore(persistence: _MemoryPersistence()),
      loadCatalog: ({refresh = false}) async => catalog,
      loadSearchAliases: ({refresh = false}) async {
        aliasLoads++;
        if (!refresh) return null;
        return const {
          'wave': ['hello'],
        };
      },
      searchDebounce: Duration.zero,
    );
    addTearDown(controller.dispose);

    await controller.load();
    controller.updateQuery('hello');
    await Future<void>.delayed(Duration.zero);
    expect(controller.searchResults, isEmpty);

    await controller.retry();
    await Future<void>.delayed(Duration.zero);
    expect(aliasLoads, 2);
    expect(controller.searchResults.single.name, 'wave');
  });
}

EmojiPickerController _controller({
  required SiteEmojiCatalog catalog,
  EmojiPickerStore? store,
  Future<Map<String, List<String>>?> Function({bool refresh})? aliases,
}) {
  return EmojiPickerController(
    siteUrl: _siteUrl,
    context: EmojiPickerContext.topic,
    store: store ?? EmojiPickerStore(persistence: _MemoryPersistence()),
    loadCatalog: ({refresh = false}) async => catalog,
    loadSearchAliases:
        aliases ?? ({refresh = false}) async => const <String, List<String>>{},
    searchDebounce: Duration.zero,
  );
}

SiteEmojiCatalog _catalog(List<SiteEmoji> emojis) => SiteEmojiCatalog(
  groups: [SiteEmojiGroup(id: 'smileys_&_emotion', emojis: emojis)],
);

final class _MemoryPersistence implements EmojiPickerPersistence {
  final Map<String, String> values = {};

  @override
  Future<String?> readPreferences({required String siteUrl}) async =>
      values[siteUrl];

  @override
  Future<bool> writePreferences({
    required String siteUrl,
    required String encoded,
  }) async {
    values[siteUrl] = encoded;
    return true;
  }
}
