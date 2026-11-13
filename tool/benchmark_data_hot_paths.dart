import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/json_decode.dart';
import 'package:discourse_native/src/data/site_appearance_parser.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final response = http.Response.bytes(
    utf8.encode('{"success":"OK","username":"café","unread_notifications":3}'),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  final unquotedResponse = http.Response.bytes(
    response.bodyBytes,
    200,
    headers: {'content-type': 'application/json'},
  );
  final wantedResponse = {
    'success': 'OK',
    'username': 'café',
    'unread_notifications': 3,
  };

  const paletteCss = '''
    :root {
      --scheme-type: dark;
      --primary: #123456;
      --secondary: #234567;
      --tertiary: #345678;
      --theme-radius: 6px;
    }
    img.avatar { border-radius: var(--theme-radius); }
  ''';
  final expectedPalette = parseSiteAppearanceStylesheet(paletteCss)!;
  if (expectedPalette.primary.toARGB32() != 0xff123456 ||
      expectedPalette.tertiary.toARGB32() != 0xff345678 ||
      expectedPalette.avatarBorderRadius !=
          const AvatarBorderRadius.pixels(6)) {
    throw StateError('Unexpected control palette');
  }
  final theme =
      '''
    $paletteCss
    ${List.generate(400, (index) => '''
      .custom-theme-section-$index .caption {
        color: var(--primary);
        background: var(--secondary);
        margin: 0.5rem;
        border: 1px solid var(--tertiary);
      }
    ''').join()}
    @media (prefers-color-scheme: light) {
      :root { --primary: #abcdef; }
    }
  ''';

  final ids = List.generate(3000, (index) => index + 100);
  final held = TopicDetail(id: 8, title: 'Discussion', stream: ids);
  final refetched = TopicDetail(
    id: 8,
    title: 'Discussion',
    stream: ids.toList(),
  );
  final stale = TopicDetail(
    id: 8,
    title: 'Discussion',
    stream: ids.sublist(0, ids.length - 1),
    postsCount: ids.length - 1,
  );

  final results = {
    'small_json_response_us': await _measureAsync(
      6000,
      (index) =>
          decodeJsonHttpResponse(index.isEven ? response : unquotedResponse),
      (value) {
        if (value case {
          'success': final success,
          'username': final name,
          'unread_notifications': final unread,
        }) {
          if (success == wantedResponse['success'] &&
              name == wantedResponse['username'] &&
              unread == wantedResponse['unread_notifications']) {
            return;
          }
        }
        throw StateError('Unexpected decoded response: $value');
      },
    ),
    'theme_palette_400_rules_us': _measure(
      60,
      (_) => parseSiteAppearanceStylesheet(theme),
      (value) {
        if (value != expectedPalette) {
          throw StateError('Unexpected theme palette');
        }
      },
    ),
    'topic_refetch_3000_unchanged_us': _measure(
      1500,
      (_) => held.merge(refetched),
      (value) {
        if (!identical(value, held)) {
          throw StateError('Refetched topic lost identity');
        }
      },
    ),
    'topic_refetch_3000_stale_control_us': _measure(
      1500,
      (_) => held.merge(stale),
      (value) {
        if (value.stream.length != ids.length ||
            value.stream.last != ids.last ||
            value.postsCount != ids.length) {
          throw StateError('Refetch lost the appended post');
        }
      },
    ),
  };
  stdout.writeln(jsonEncode(results));
  exit(0);
}

double _measure<T>(
  int iterations,
  T Function(int) run,
  void Function(T) check,
) {
  final samples = <double>[];
  final outputs = List<T?>.filled(iterations, null);
  for (var batch = 0; batch < 12; batch++) {
    final watch = Stopwatch()..start();
    for (var index = 0; index < iterations; index++) {
      outputs[index] = run(index);
    }
    watch.stop();
    for (final value in outputs) {
      check(value as T);
    }
    if (batch >= 5) samples.add(watch.elapsedMicroseconds / iterations);
  }
  return _median(samples);
}

Future<double> _measureAsync<T>(
  int iterations,
  Future<T> Function(int) run,
  void Function(T) check,
) async {
  final samples = <double>[];
  final outputs = List<T?>.filled(iterations, null);
  for (var batch = 0; batch < 12; batch++) {
    final watch = Stopwatch()..start();
    for (var index = 0; index < iterations; index++) {
      outputs[index] = await run(index);
    }
    watch.stop();
    for (final value in outputs) {
      check(value as T);
    }
    if (batch >= 5) samples.add(watch.elapsedMicroseconds / iterations);
  }
  return _median(samples);
}

double _median(List<double> samples) {
  samples.sort();
  return samples[samples.length ~/ 2];
}
