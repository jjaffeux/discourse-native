import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/plugin_api/global_search_filters.dart';
import 'package:discourse_native/src/plugin_api/global_search_models.dart';
import 'package:discourse_native/src/shell/site_presentation_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

const _site = 'https://forum.example';
const _capabilities = GlobalSearchCapabilities(
  authenticated: true,
  username: 'reader',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final emoji = await _emojiFixture();
  try {
    const queries = <(String, String, String?, List<(String, String, String)>)>[
      ('flutter layout constraints', 'flutter layout constraints', null, []),
      (
        'login error status:open category:=support tags:mobile+bug order:latest',
        'login error',
        'latest',
        [
          ('status', 'is', 'open'),
          ('category', 'exactCategory', 'support'),
          ('tags', 'all', 'mobile,bug'),
        ],
      ),
      (
        'macOS after:2026-01-01 filetype:png @reader min_posts:3',
        'macOS',
        null,
        [
          ('postDate', 'after', '2026-01-01'),
          ('files', 'any', 'png'),
          ('author', 'is', 'reader'),
          ('postCount', 'gte', '3'),
        ],
      ),
    ];
    GlobalSearchExpression parse(String text) => parseGlobalSearchExpression(
      text,
      GlobalSearchScope.forum,
      _capabilities,
    );
    for (final (text, words, order, conditions) in queries) {
      final expression = parse(text);
      final actual = [
        for (final condition in expression.conditions)
          (condition.filterId, condition.operator, condition.text),
      ];
      if (expression.query != words ||
          expression.order != order ||
          !listEquals(actual, conditions)) {
        throw StateError('Incorrect expression for $text: $actual');
      }
    }
    final benchmark = {
      'globalSearchExpression': _measure(
        iterations: 2400,
        run: (index) => parse(queries[index % queries.length].$1),
        check: (index, result) {
          final query = queries[index % queries.length];
          final expression = result as GlobalSearchExpression;
          return expression.query == query.$2 &&
              expression.order == query.$3 &&
              listEquals([
                for (final condition in expression.conditions)
                  (condition.filterId, condition.operator, condition.text),
              ], query.$4);
        },
      ),
      'emojiAutocomplete': _measureEmoji(emoji, [
        ('s', 7),
        ('sm', 7),
        ('smi', 7),
        ('smile', 7),
        ('h', 7),
        ('he', 7),
        ('heart', 7),
        ('flag', 7),
        ('ocean', 7),
        ('cheer', 7),
        ('zzzz', 7),
      ]),
      'emojiAutocompleteSparse': _measureEmoji(emoji, [
        ('ocean', 7),
        ('cheer', 7),
        ('zzzz', 7),
      ]),
    };
    stdout.writeln(jsonEncode(benchmark));
  } finally {
    emoji.controller.dispose();
  }
  exit(0);
}

double _measure({
  required int iterations,
  required Object Function(int) run,
  required bool Function(int, Object) check,
}) {
  final samples = <double>[];
  for (var batch = 0; batch < 10; batch++) {
    final output = List<Object?>.filled(iterations, null);
    final stopwatch = Stopwatch()..start();
    for (var index = 0; index < iterations; index++) {
      output[index] = run(index);
    }
    stopwatch.stop();
    for (var index = 0; index < iterations; index++) {
      if (!check(index, output[index]!)) {
        throw StateError('Incorrect result at operation $index');
      }
    }
    if (batch >= 3) {
      samples.add(stopwatch.elapsedMicroseconds / iterations);
    }
  }
  samples.sort();
  return samples[samples.length ~/ 2];
}

typedef _EmojiFixture = ({
  SitePresentationController controller,
  SiteEmojiCatalog catalog,
  Map<String, List<String>> aliases,
});

Future<_EmojiFixture> _emojiFixture() async {
  final data = File(
    'packages/discourse_cooking/js/vendor/frontend/pretty-text/addon/emoji/data.js',
  ).readAsStringSync();
  final quotedName = RegExp(r'"([^"]+)"');
  final names = data.split('export const tonableEmojis').first;
  final catalog = SiteEmojiCatalog(
    groups: [
      SiteEmojiGroup(
        id: 'standard',
        emojis: [
          for (final match in quotedName.allMatches(names))
            SiteEmoji(name: match[1]!, url: '/emoji/${match[1]}.png'),
        ],
      ),
      SiteEmojiGroup(
        id: 'custom',
        emojis: const [
          SiteEmoji(name: 'Heart_Logo', url: '/uploads/heart-logo.png'),
          SiteEmoji(name: 'Smile_Logo', url: '/uploads/smile-logo.png'),
        ],
      ),
    ],
  );
  final aliasData = data
      .split('export const aliases = {')[1]
      .split('export const translations')
      .first;
  final aliases = {
    for (final match in RegExp(
      r'^\s*"?([^"\s:]+)"?:\s*\[(.*?)\]',
      multiLine: true,
      dotAll: true,
    ).allMatches(aliasData))
      match[1]!: [
        for (final alias in quotedName.allMatches(match[2]!)) alias[1]!,
      ],
  };
  if (catalog.all.length < 1800 || aliases.length < 500) {
    throw StateError('Incomplete emoji fixture');
  }
  final controller = SitePresentationController(
    loadAppearance: ({required siteUrl, apiKey, clientId}) async => null,
    loadConfig: ({required siteUrl, apiKey, clientId}) async =>
        const SiteConfig.unknown(),
    loadCustomEmojis: ({required siteUrl, apiKey, clientId}) async => const {},
    loadEmojiCatalog: ({required siteUrl, apiKey, clientId}) async => catalog,
    loadEmojiSearchAliases: ({required siteUrl, apiKey, clientId}) async =>
        aliases,
    credentials: const _AnonymousCredentials(),
    lifecycle: SiteLifecycle(),
    readPersistedAppearance: (_) => null,
    readPersistedConfig: (_) => null,
    onAppearanceLoaded: (_, _) async {},
    onConfigLoaded: (_, _) async {},
  );
  await controller.ensureEmojiCatalog(_site);
  await controller.ensureEmojiSearchAliases(_site);
  return (controller: controller, catalog: catalog, aliases: aliases);
}

double _measureEmoji(_EmojiFixture fixture, List<(String, int)> cases) {
  final expected = [
    for (final (query, limit) in cases)
      _referenceEmojiSearch(fixture, query, limit),
  ];
  if (!expected.any((matches) => matches.isNotEmpty)) {
    throw StateError('Emoji workload needs a matching query');
  }
  return _measure(
    iterations: cases.length * 120,
    run: (index) {
      final (query, limit) = cases[index % cases.length];
      return fixture.controller.searchEmojis(_site, query, limit: limit);
    },
    check: (index, result) =>
        listEquals(result as List<SiteEmoji>, expected[index % cases.length]),
  );
}

List<SiteEmoji> _referenceEmojiSearch(
  _EmojiFixture fixture,
  String query,
  int limit,
) {
  final matches = <(int, SiteEmoji)>[];
  for (final emoji in fixture.catalog.byName.values) {
    final name = emoji.name.toLowerCase();
    if (name.startsWith(query)) {
      matches.add((0, emoji));
    } else if (fixture.aliases[emoji.name]?.any(
          (alias) => alias.toLowerCase().startsWith(query),
        ) ??
        false) {
      matches.add((1, emoji));
    } else if (name.contains(query)) {
      matches.add((2, emoji));
    }
  }
  matches.sort((a, b) {
    final rank = a.$1.compareTo(b.$1);
    return rank == 0 ? a.$2.name.compareTo(b.$2.name) : rank;
  });
  return [for (final match in matches.take(limit)) match.$2];
}

class _AnonymousCredentials implements ApiCredentialReader {
  const _AnonymousCredentials();

  @override
  Future<String?> apiKeyFor(String siteUrl) async => null;

  @override
  Future<String> clientId() async => '';
}
