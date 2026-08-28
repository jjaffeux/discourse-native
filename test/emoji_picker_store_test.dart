import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/emoji_picker_store.dart';
import 'package:discourse_native/src/diagnostics/diagnostic_event.dart';
import 'package:discourse_native/src/diagnostics/diagnostics_controller.dart';
import 'package:discourse_native/src/diagnostics/diagnostics_persistence.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/plugin_api/emoji_usage.dart';
import 'package:discourse_native/src/plugins/chat/chat_emoji_usage.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_emoji_usage.dart';
import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const meta = 'https://meta.discourse.org';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'SharedPreferences round-trips one preference document per forum',
    () async {
      final first = EmojiPickerStore();
      await first.writeSkinTone(siteUrl: '$meta/', tone: EmojiSkinTone.t5);
      await first.trackEmoji(
        siteUrl: meta,
        context: CoreEmojiUsageContexts.topic,
        emoji: ':wave:t3:',
      );

      final reloaded = EmojiPickerStore();
      expect(
        await reloaded.readSkinTone(siteUrl: 'HTTPS://META.DISCOURSE.ORG:443'),
        EmojiSkinTone.t5,
      );
      expect(
        await reloaded.favoriteEmojiCodes(
          siteUrl: meta,
          context: CoreEmojiUsageContexts.topic,
          catalog: _catalog(['wave']),
        ),
        ['wave:t3'],
      );
      expect(
        await EmojiPickerStore().readSkinTone(
          siteUrl: 'https://team.discourse.org',
        ),
        EmojiSkinTone.neutral,
      );
    },
  );

  test('a failed read never overwrites the stored document', () async {
    final persistence = _FailingReadPersistence();
    persistence.values[meta] = jsonEncode({
      'version': 1,
      'tone': 't5',
      'history': {
        'topic': ['wave', 'heart'],
      },
    });
    final stored = persistence.values[meta];

    final store = EmojiPickerStore(persistence: persistence);
    persistence.failReads = true;
    await store.ensureLoaded(siteUrl: meta);

    // The picker still opens on the safe default — but that default is a
    // stand-in for a document that is intact and simply was not read, so
    // building on it and saving would erase the reader's tone and history.
    expect(store.skinToneFor(siteUrl: meta), EmojiSkinTone.neutral);

    await store.trackEmoji(
      siteUrl: meta,
      context: CoreEmojiUsageContexts.topic,
      emoji: ':smile:',
    );

    expect(persistence.values[meta], stored);

    // Once the store can read again, writes resume against the real document.
    persistence.failReads = false;
    await store.trackEmoji(
      siteUrl: meta,
      context: CoreEmojiUsageContexts.topic,
      emoji: ':smile:',
    );

    final reloaded = EmojiPickerStore(persistence: persistence);
    await reloaded.ensureLoaded(siteUrl: meta);
    expect(reloaded.skinToneFor(siteUrl: meta), EmojiSkinTone.t5);
  });

  test('favorites rank by frequency and then most recent use', () async {
    final store = EmojiPickerStore(persistence: _MemoryPersistence());
    for (final emoji in [
      ':wave:',
      'heart:t3',
      'wave',
      ':heart:t3:',
      'laughing',
    ]) {
      await store.trackEmoji(
        siteUrl: meta,
        context: CoreEmojiUsageContexts.topic,
        emoji: emoji,
      );
    }

    expect(
      await store.favoriteEmojiCodes(
        siteUrl: meta,
        context: CoreEmojiUsageContexts.topic,
        catalog: _catalog(['wave', 'heart', 'laughing']),
      ),
      ['heart:t3', 'wave', 'laughing'],
    );
  });

  test('retains 40 events and returns at most 20 current emoji', () async {
    final persistence = _MemoryPersistence();
    final store = EmojiPickerStore(persistence: persistence);
    for (var index = 0; index < 45; index++) {
      await store.trackEmoji(
        siteUrl: meta,
        context: CoreEmojiUsageContexts.topic,
        emoji: 'emoji_$index',
      );
    }
    await store.trackEmoji(
      siteUrl: meta,
      context: CoreEmojiUsageContexts.topic,
      emoji: 'removed_from_site:t4',
    );

    final decoded =
        jsonDecode(persistence.values[meta]!) as Map<String, dynamic>;
    final history = decoded['history'] as Map<String, dynamic>;
    final topic = history[CoreEmojiUsageContexts.topic.id] as List<dynamic>;
    expect(topic, hasLength(EmojiPickerStore.maxTrackedEmoji));
    expect(topic.first, 'emoji_6');
    expect(topic.last, 'removed_from_site:t4');

    final favorites = await store.favoriteEmojiCodes(
      siteUrl: meta,
      context: CoreEmojiUsageContexts.topic,
      catalog: _catalog([
        for (var index = 0; index < 45; index++) 'emoji_$index',
      ]),
    );
    expect(favorites, hasLength(EmojiPickerStore.maxFavoriteEmoji));
    expect(favorites.first, 'emoji_44');
    expect(favorites.last, 'emoji_25');
    expect(favorites, isNot(contains('removed_from_site:t4')));
  });

  test('clear affects only one context and preserves the forum tone', () async {
    final store = EmojiPickerStore(persistence: _MemoryPersistence());
    await store.writeSkinTone(siteUrl: meta, tone: EmojiSkinTone.t4);
    await store.trackEmoji(
      siteUrl: meta,
      context: CoreEmojiUsageContexts.topic,
      emoji: 'wave',
    );
    await store.trackEmoji(
      siteUrl: meta,
      context: chatEmojiUsageContext,
      emoji: 'heart:t2',
    );
    await store.trackEmoji(
      siteUrl: meta,
      context: reactionsEmojiUsageContext,
      emoji: 'tada',
    );

    await store.clearHistory(
      siteUrl: meta,
      context: CoreEmojiUsageContexts.topic,
    );

    final catalog = _catalog(['wave', 'heart']);
    expect(
      store.favoriteEmojiCodesFor(
        siteUrl: meta,
        context: CoreEmojiUsageContexts.topic,
        catalog: catalog,
      ),
      isEmpty,
    );
    expect(
      store.favoriteEmojiCodesFor(
        siteUrl: meta,
        context: chatEmojiUsageContext,
        catalog: catalog,
      ),
      ['heart:t2'],
    );
    expect(
      store.favoriteEmojiCodesFor(
        siteUrl: meta,
        context: reactionsEmojiUsageContext,
        catalog: _catalog(['tada']),
      ),
      ['tada'],
    );
    expect(store.skinToneFor(siteUrl: meta), EmojiSkinTone.t4);
  });

  test(
    'reactions context adopts postReactions while upgrading a v1 document',
    () async {
      final persistence = _MemoryPersistence()
        ..values[meta] = jsonEncode({
          'version': 1,
          'tone': 't5',
          'history': {
            'topic': ['wave'],
            'chat': ['heart:t2'],
            'postReactions': ['clap'],
          },
        });
      final store = EmojiPickerStore(persistence: persistence);

      await store.trackEmoji(
        siteUrl: meta,
        context: reactionsEmojiUsageContext,
        emoji: 'tada',
      );

      final upgraded =
          jsonDecode(persistence.values[meta]!) as Map<String, dynamic>;
      final upgradedHistory = upgraded['history'] as Map<String, dynamic>;
      expect(upgraded['version'], EmojiPickerStore.formatVersion);
      expect(upgradedHistory['topic'], ['wave']);
      expect(upgradedHistory['chat'], ['heart:t2']);
      expect(upgradedHistory, isNot(contains('postReactions')));
      expect(upgradedHistory[reactionsEmojiUsageContext.id], ['clap', 'tada']);

      final reloaded = EmojiPickerStore(persistence: persistence);
      expect(await reloaded.readSkinTone(siteUrl: meta), EmojiSkinTone.t5);
      expect(
        await reloaded.favoriteEmojiCodes(
          siteUrl: meta,
          context: CoreEmojiUsageContexts.topic,
          catalog: _catalog(['wave']),
        ),
        ['wave'],
      );
      expect(
        await reloaded.favoriteEmojiCodes(
          siteUrl: meta,
          context: chatEmojiUsageContext,
          catalog: _catalog(['heart']),
        ),
        ['heart:t2'],
      );
      expect(
        await reloaded.favoriteEmojiCodes(
          siteUrl: meta,
          context: reactionsEmojiUsageContext,
          catalog: _catalog(['clap', 'tada']),
        ),
        ['tada', 'clap'],
      );
    },
  );

  test('a legacy key is adopted when its namespaced context changes', () async {
    final persistence = _MemoryPersistence()
      ..values[meta] = jsonEncode({
        'version': 1,
        'tone': 'neutral',
        'history': {
          'chat': ['heart'],
        },
      });
    final store = EmojiPickerStore(persistence: persistence);

    await store.trackEmoji(
      siteUrl: meta,
      context: chatEmojiUsageContext,
      emoji: 'wave',
    );

    final upgraded =
        jsonDecode(persistence.values[meta]!) as Map<String, dynamic>;
    final history = upgraded['history'] as Map<String, dynamic>;
    expect(upgraded['version'], EmojiPickerStore.formatVersion);
    expect(history, isNot(contains('chat')));
    expect(history[chatEmojiUsageContext.id], ['heart', 'wave']);
  });

  test(
    'plugin contexts are isolated and unknown histories are preserved',
    () async {
      const firstContext = EmojiUsageContext(
        owner: PluginId('first-plugin'),
        name: 'composer',
      );
      const secondContext = EmojiUsageContext(
        owner: PluginId('second-plugin'),
        name: 'composer',
      );
      const unknownContextId = 'removed-plugin/message';
      final persistence = _MemoryPersistence()
        ..values[meta] = jsonEncode({
          'version': EmojiPickerStore.formatVersion,
          'tone': 'neutral',
          'history': {
            unknownContextId: ['tada'],
          },
        });
      final store = EmojiPickerStore(persistence: persistence);

      await store.trackEmoji(
        siteUrl: meta,
        context: firstContext,
        emoji: 'wave',
      );
      await store.trackEmoji(
        siteUrl: meta,
        context: secondContext,
        emoji: 'heart',
      );

      final reloaded = EmojiPickerStore(persistence: persistence);
      expect(
        await reloaded.favoriteEmojiCodes(
          siteUrl: meta,
          context: firstContext,
          catalog: _catalog(['wave', 'heart']),
        ),
        ['wave'],
      );
      expect(
        await reloaded.favoriteEmojiCodes(
          siteUrl: meta,
          context: secondContext,
          catalog: _catalog(['wave', 'heart']),
        ),
        ['heart'],
      );

      final encoded =
          jsonDecode(persistence.values[meta]!) as Map<String, dynamic>;
      final history = encoded['history'] as Map<String, dynamic>;
      expect(history[unknownContextId], ['tada']);
      expect(history[firstContext.id], ['wave']);
      expect(history[secondContext.id], ['heart']);
    },
  );

  test('explicit t2 through t6 codes survive persistence', () async {
    final persistence = _MemoryPersistence();
    final store = EmojiPickerStore(persistence: persistence);
    for (final suffix in ['t2', 't3', 't4', 't5', 't6']) {
      await store.trackEmoji(
        siteUrl: meta,
        context: chatEmojiUsageContext,
        emoji: ':wave:$suffix:',
      );
    }

    final reloaded = EmojiPickerStore(persistence: persistence);
    expect(
      await reloaded.favoriteEmojiCodes(
        siteUrl: meta,
        context: chatEmojiUsageContext,
        catalog: _catalog(['wave']),
      ),
      ['wave:t6', 'wave:t5', 'wave:t4', 'wave:t3', 'wave:t2'],
    );
  });

  test('a corrupt read falls back safely and emits diagnostics', () async {
    final persistence = _MemoryPersistence()..values[meta] = '{not json';
    final diagnostics = await _installDiagnostics('emoji-picker-corrupt-read');
    final store = EmojiPickerStore(persistence: persistence);

    expect(await store.readSkinTone(siteUrl: meta), EmojiSkinTone.neutral);
    expect(
      await store.favoriteEmojiCodes(
        siteUrl: meta,
        context: CoreEmojiUsageContexts.topic,
        catalog: _catalog(['wave']),
      ),
      isEmpty,
    );
    expect(
      diagnostics.events.whereType<ErrorDiagnosticEvent>().single,
      _isStorageFailure('emojiPicker.read'),
    );
  });

  test('a rejected write is reported but remains usable in memory', () async {
    final persistence = _MemoryPersistence(acceptWrites: false);
    final diagnostics = await _installDiagnostics('emoji-picker-write');
    final store = EmojiPickerStore(persistence: persistence);

    await store.writeSkinTone(siteUrl: meta, tone: EmojiSkinTone.t6);

    expect(store.skinToneFor(siteUrl: meta), EmojiSkinTone.t6);
    expect(
      diagnostics.events.whereType<ErrorDiagnosticEvent>().single,
      _isStorageFailure('emojiPicker.write'),
    );
  });

  test('rapid writes are serialized and preserve every event', () async {
    final gate = Completer<void>();
    final persistence = _ControlledPersistence(firstWriteGate: gate);
    final store = EmojiPickerStore(persistence: persistence);

    final first = store.trackEmoji(
      siteUrl: meta,
      context: CoreEmojiUsageContexts.topic,
      emoji: 'wave',
    );
    await persistence.firstWriteStarted.future;
    final second = store.trackEmoji(
      siteUrl: meta,
      context: CoreEmojiUsageContexts.topic,
      emoji: 'heart',
    );
    await Future<void>.delayed(Duration.zero);

    expect(persistence.writeCount, 1);
    gate.complete();
    await Future.wait([first, second]);

    expect(persistence.writeCount, 2);
    expect(_topicHistory(persistence.values[meta]!), ['wave', 'heart']);
  });

  test(
    'replacement stores serialize writes through shared persistence',
    () async {
      final gate = Completer<void>();
      final persistence = _ControlledPersistence(firstWriteGate: gate);
      final oldStore = EmojiPickerStore(persistence: persistence);
      final replacementStore = EmojiPickerStore(persistence: persistence);

      final first = oldStore.trackEmoji(
        siteUrl: meta,
        context: chatEmojiUsageContext,
        emoji: 'wave',
      );
      await persistence.firstWriteStarted.future;
      final second = replacementStore.trackEmoji(
        siteUrl: meta,
        context: chatEmojiUsageContext,
        emoji: 'heart',
      );
      await Future<void>.delayed(Duration.zero);

      expect(persistence.writeCount, 1);
      gate.complete();
      await Future.wait([first, second]);

      final reloaded = EmojiPickerStore(persistence: persistence);
      expect(
        await reloaded.favoriteEmojiCodes(
          siteUrl: meta,
          context: chatEmojiUsageContext,
          catalog: _catalog(['wave', 'heart']),
        ),
        ['heart', 'wave'],
      );
    },
  );
}

SiteEmojiCatalog _catalog(Iterable<String> names) => SiteEmojiCatalog(
  groups: [
    SiteEmojiGroup(
      id: 'people',
      emojis: [
        for (final name in names)
          SiteEmoji(name: name, url: 'https://cdn.example/$name.png'),
      ],
    ),
  ],
);

List<dynamic> _topicHistory(String encoded) {
  final decoded = jsonDecode(encoded) as Map<String, dynamic>;
  final history = decoded['history'] as Map<String, dynamic>;
  return history[CoreEmojiUsageContexts.topic.id] as List<dynamic>;
}

Future<DiagnosticsController> _installDiagnostics(String sessionId) async {
  final diagnostics = await DiagnosticsController.create(
    persistence: MemoryDiagnosticsPersistence(),
    sessionId: sessionId,
  );
  final binding = DiagnosticsSink.install(diagnostics);
  addTearDown(() async {
    binding.close();
    await diagnostics.close();
  });
  return diagnostics;
}

Matcher _isStorageFailure(String operation) => isA<ErrorDiagnosticEvent>()
    .having((event) => event.operation, 'operation', operation)
    .having((event) => event.source, 'source', 'storage')
    .having((event) => event.severity, 'severity', DiagnosticSeverity.warning)
    .having((event) => event.handled, 'handled', isTrue)
    .having((event) => event.degraded, 'degraded', isTrue);

class _MemoryPersistence implements EmojiPickerPersistence {
  _MemoryPersistence({this.acceptWrites = true});

  final bool acceptWrites;
  final Map<String, String> values = {};

  @override
  Future<String?> readPreferences({required String siteUrl}) async =>
      values[siteUrl];

  @override
  Future<bool> writePreferences({
    required String siteUrl,
    required String encoded,
  }) async {
    if (acceptWrites) values[siteUrl] = encoded;
    return acceptWrites;
  }
}

final class _ControlledPersistence extends _MemoryPersistence {
  _ControlledPersistence({required this.firstWriteGate});

  final Completer<void> firstWriteGate;
  final Completer<void> firstWriteStarted = Completer<void>();
  int writeCount = 0;

  @override
  Future<bool> writePreferences({
    required String siteUrl,
    required String encoded,
  }) async {
    writeCount++;
    if (writeCount == 1) {
      firstWriteStarted.complete();
      await firstWriteGate.future;
    }
    return super.writePreferences(siteUrl: siteUrl, encoded: encoded);
  }
}

final class _FailingReadPersistence extends _MemoryPersistence {
  bool failReads = false;

  @override
  Future<String?> readPreferences({required String siteUrl}) async {
    if (failReads) throw StateError('preferences unavailable');
    return super.readPreferences(siteUrl: siteUrl);
  }
}
