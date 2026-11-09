import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Catch blocks that interpolate the caught value without reporting it, and
/// why each is not user-facing state.
const _exceptions = {
  'lib/src/data/authenticator.dart': (
    hits: 2,
    reason:
        'wraps a platform failure into a UserApiAuthException that names its '
        'own failure category; the text is the exception cause, not a '
        'sentence a screen shows',
  ),
};

const _owner = 'lib/src/data/discourse_api_contracts.dart';

final _catch = RegExp(r'catch\s*\(\s*(\w+)');

/// A line that hands the value on instead of drawing it.
final _reported = RegExp(
  r'debugPrint|log\(|[Dd]iagnostic|recordError|throw |StateError|developer',
);

/// The two hand-written shapes failureText replaced.
final _handCopy = RegExp(
  r'(WriteException|SiteLookupException)\(\s*:final message\s*\)|'
  r'is (WriteException|SiteLookupException)\s*\?\s*\w+\.message|'
  r'if \(\w+ is (WriteException|SiteLookupException)\) return \w+\.message',
);

String _withoutComments(String source) =>
    source.replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');

String _block(String source, int open) {
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    final char = source[i];
    if (char == '{') depth++;
    if (char == '}' && --depth == 0) return source.substring(open, i + 1);
  }
  return source.substring(open);
}

/// Lines in a `catch (name)` body that interpolate or print `name`.
List<String> _leakedErrors(String source) {
  final leaks = <String>[];
  for (final match in _catch.allMatches(source)) {
    final name = RegExp.escape(match.group(1)!);
    if (name == '_') continue;
    final open = source.indexOf('{', match.end);
    if (open < 0) continue;
    final use = RegExp('$name\\.toString\\(\\)|\\\$$name\\b|\\\$\\{$name\\b');
    for (final line in _block(source, open).split('\n')) {
      if (use.hasMatch(line) && !_reported.hasMatch(line)) {
        leaks.add(line.trim());
      }
    }
  }
  return leaks;
}

void main() {
  final sources = {
    for (final file in Directory('lib/src').listSync(recursive: true))
      if (file is File &&
          file.path.endsWith('.dart') &&
          !file.path.contains('/styleguide/'))
        file.path.replaceAll(r'\', '/'): _withoutComments(
          file.readAsStringSync(),
        ),
  };
  final plugins = {
    for (final entry in sources.entries)
      if (entry.key.startsWith('lib/src/plugins/')) entry.key: entry.value,
  };

  test('a caught failure is never drawn through its toString', () {
    final leaks = {
      for (final entry in sources.entries)
        if (_leakedErrors(entry.value).isNotEmpty)
          entry.key: _leakedErrors(entry.value),
    };
    expect(
      {
        for (final entry in leaks.entries)
          if (!_exceptions.containsKey(entry.key)) entry.key: entry.value,
      },
      isEmpty,
      reason: 'draw it through failureText in $_owner',
    );
    expect(
      {
        for (final entry in _exceptions.entries)
          entry.key: leaks[entry.key]?.length ?? 0,
      },
      {for (final entry in _exceptions.entries) entry.key: entry.value.hits},
      reason: 'a named exception that no longer leaks must be removed',
    );
  });

  test('the scan reaches the catch blocks it guards', () {
    final blocks = plugins.values.fold<int>(
      0,
      (total, source) => total + _catch.allMatches(source).length,
    );
    expect(blocks, greaterThan(100));
    expect(
      _leakedErrors('void f() { try {} catch (e) { show(e.toString()); } }'),
      hasLength(1),
    );
    expect(
      _leakedErrors("void f() { try {} catch (e) { show('\$e'); } }"),
      hasLength(1),
    );
  });

  test('plugins draw a failure through failureText, not a copy of it', () {
    final copies = [
      for (final entry in plugins.entries)
        if (_handCopy.hasMatch(entry.value)) entry.key,
    ];
    expect(copies, isEmpty, reason: 'call failureText in $_owner');
  });
}
