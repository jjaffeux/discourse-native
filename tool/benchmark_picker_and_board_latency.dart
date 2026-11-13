import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/emoji_picker_store.dart';
import 'package:discourse_native/src/models/emoji_usage.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/plugins/boards/boards_data.dart';
import 'package:discourse_native/src/shell/emoji_picker_controller.dart';

import '../test/support/boards_fixture.dart';

const _remote = Duration(milliseconds: 30);
const _site = 'https://forum.example';

Future<void> main() async {
  stdout.writeln(
    jsonEncode({
      'open_emoji_picker': await _median(() => _picker(search: false)),
      'resolve_emoji_alias_query': await _median(() => _picker(search: true)),
      'clear_board_column': await _median(_board),
    }),
  );
  exit(0);
}

Future<int> _median(Future<int> Function() action) async {
  final times = <int>[];
  for (var i = 0; i < 7; i++) {
    final time = await action();
    if (i >= 2) times.add(time);
  }
  times.sort();
  return times[2];
}

Future<int> _picker({required bool search}) async {
  final persistence = _Preferences(
    search ? Duration.zero : const Duration(milliseconds: 12),
  );
  final store = EmojiPickerStore(persistence: persistence);
  if (search) await store.ensureLoaded(siteUrl: _site);
  final catalog = SiteEmojiCatalog(
    groups: [
      SiteEmojiGroup(
        id: 'standard',
        emojis: const [
          SiteEmoji(name: 'wave', url: '/wave.png', tonable: true),
        ],
      ),
    ],
  );
  var catalogReads = 0;
  var aliasReads = 0;
  final picker = EmojiPickerController(
    siteUrl: _site,
    context: CoreEmojiUsageContexts.topic,
    store: store,
    initialQuery: search ? 'hello' : '',
    loadCatalog: ({bool refresh = false}) async {
      catalogReads++;
      await Future<void>.delayed(_remote);
      return catalog;
    },
    loadSearchAliases: ({bool refresh = false}) async {
      aliasReads++;
      await Future<void>.delayed(_remote);
      return {
        'wave': ['hello'],
      };
    },
  );
  final found = Completer<void>();
  picker.addListener(() {
    if (!found.isCompleted &&
        picker.searchResults.any((row) => row.name == 'wave')) {
      found.complete();
    }
  });
  try {
    final watch = Stopwatch()..start();
    await picker.load();
    if (search) await found.future.timeout(const Duration(seconds: 2));
    watch.stop();
    if (picker.loading ||
        picker.error != null ||
        picker.favorites.single.code != 'wave:t4' ||
        picker.tone != EmojiSkinTone.t4 ||
        catalogReads != 1 ||
        aliasReads != (search ? 1 : 0) ||
        persistence.reads != 1) {
      throw StateError('Unexpected picker output');
    }
    return watch.elapsedMicroseconds;
  } finally {
    picker.dispose();
  }
}

Future<int> _board() async {
  final fixture = BoardsFixture(
    beforeTopicReload: (_) => Future<void>.delayed(_remote),
  );
  final handle = fixture.controller.acquire(boardsSite, 1);
  try {
    await handle.refresh();
    fixture.transport.responders['GET /boards/api/boards/1.json'] = (_) async {
      await Future<void>.delayed(_remote);
      return fixture.data;
    };
    final clear = fixture
        .transport
        .responders['DELETE /boards/api/boards/1/columns/10/cards']!;
    fixture
            .transport
            .responders['DELETE /boards/api/boards/1/columns/10/cards'] =
        (request) async {
          await Future<void>.delayed(_remote);
          return clear(request);
        };
    final watch = Stopwatch()..start();
    final result = await handle.clearColumn(10);
    watch.stop();
    if (result.state != BoardWriteState.saved ||
        handle.snapshot!.column(10)!.cards.isNotEmpty ||
        fixture.refreshedTopics.single != 500 ||
        fixture.transport.writes.length != 1) {
      throw StateError('Column and topic did not reconcile');
    }
    return watch.elapsedMicroseconds;
  } finally {
    handle.release();
    fixture.dispose();
  }
}

final class _Preferences implements EmojiPickerPersistence {
  _Preferences(this.delay);
  final Duration delay;
  int reads = 0;

  @override
  Future<String?> readPreferences({required String siteUrl}) async {
    reads++;
    if (delay != Duration.zero) await Future<void>.delayed(delay);
    return '{"version":2,"tone":"t4","history":{"core/topic":["wave"]}}';
  }

  @override
  Future<bool> writePreferences({
    required String siteUrl,
    required String encoded,
  }) async => throw StateError('Unexpected emoji preference write');
}
