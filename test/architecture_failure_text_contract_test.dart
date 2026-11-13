import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Error handlers that interpolate the caught value without reporting it, and
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

const _owner = 'lib/src/data/failure_text.dart';

/// Where a failure is caught and named: a `catch` clause, an `onError:`
/// argument, or a `catchError`, `onError` or `handleError` callback. The
/// first parameter, after an optional type, is the failure.
final _handler = RegExp(
  r'(?:\bcatch|\bonError:|\.(?:catchError|onError|handleError)(?:<[^>(]*>)?\()'
  r'\s*\(\s*(?:[\w<>?]+\s+)?(\w+)',
);

/// Where a handler's parameter list ends and its body begins.
final _opening = RegExp(r'\)\s*(?:async\s*)?(\{|=>)');

/// A line that hands the value on instead of drawing it. Each logging call is
/// matched as a whole word, so a widget such as `showErrorDialog(` does not
/// pass as `log(`.
final _reported = RegExp(
  r'debugPrint|\blog\(|[Dd]iagnostic|recordError|throw |StateError|developer',
);

/// The hand-written shapes failureText replaced: a pattern, a switch arm, a
/// type test or an early return that reads the failure's own message.
final _handCopy = RegExp(
  r'(WriteException|SiteLookupException)\(\s*:final message\s*\)|'
  r'(WriteException|SiteLookupException)\(\)\s*=>\s*\w+\.message|'
  r'(WriteException|SiteLookupException)\s+\w+\s*=>\s*\w+\.message|'
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

int _stringEnd(String source, int open) {
  final quote = source[open];
  for (var i = open + 1; i < source.length; i++) {
    if (source[i] == r'\') {
      i++;
    } else if (source[i] == quote) {
      return i;
    }
  }
  return source.length;
}

/// An arrow body: everything before the comma, semicolon or closing bracket
/// that ends the expression. String literals are skipped, so a comma in a
/// message does not end it early.
String _expression(String source, int start) {
  var depth = 0;
  for (var i = start; i < source.length; i++) {
    final char = source[i];
    if (char == "'" || char == '"') {
      i = _stringEnd(source, i);
    } else if ('([{'.contains(char)) {
      depth++;
    } else if (')]}'.contains(char) && --depth < 0 ||
        (char == ',' || char == ';') && depth == 0) {
      return source.substring(start, i);
    }
  }
  return source.substring(start);
}

String _body(String source, int parameters) {
  final close = source.indexOf(')', parameters);
  final opening = close < 0 ? null : _opening.matchAsPrefix(source, close);
  if (opening == null) return '';
  return opening.group(1) == '{'
      ? _block(source, opening.end - 1)
      : _expression(source, opening.end);
}

/// Lines in an error handler's body that interpolate or print the failure.
List<String> _leakedErrors(String source) {
  final leaks = <String>[];
  for (final match in _handler.allMatches(source)) {
    final name = RegExp.escape(match.group(1)!);
    if (name == '_') continue;
    final use = RegExp('$name\\.toString\\(\\)|\\\$$name\\b|\\\$\\{$name\\b');
    for (final line in _body(source, match.end).split('\n')) {
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

  test('the scan reaches the error handlers it guards', () {
    final handlers = plugins.values.fold<int>(
      0,
      (total, source) => total + _handler.allMatches(source).length,
    );
    expect(handlers, greaterThan(100));
    for (final handler in [
      'try {} catch (e) { show(e.toString()); }',
      "try {} catch (e) { show('\$e'); }",
      'try {} catch (e) { showErrorDialog(context, e.toString()); }',
      "g().then((_) {}, onError: (e) => show('failed, \$e'));",
      's.listen(print, onError: (Object e, StackTrace s) { show(e.toString()); });',
      "g().catchError((Object e) { show('\${e}'); });",
      "g().onError<void>((e, _) async => show('\$e'));",
      "s.handleError((e) => show(e.toString()));",
    ]) {
      expect(
        _leakedErrors('void f() { $handler }'),
        hasLength(1),
        reason: handler,
      );
    }
    for (final handler in [
      "try {} catch (e) { log('\$e'); }",
      'try {} catch (e) { debugPrint(e.toString()); }',
      "g().catchError((e) => report(e)); show('\$e');",
    ]) {
      expect(
        _leakedErrors('void f(Object e) { $handler }'),
        isEmpty,
        reason: handler,
      );
    }
  });

  test('the copy scan matches every shape failureText replaced', () {
    for (final copy in [
      'WriteException(:final message) => message',
      'SiteLookupException(:final message) => message',
      'WriteException() => error.message',
      'final WriteException error => error.message',
      'SiteLookupException error => error.message',
      'error is WriteException ? error.message : fallback',
      'if (error is SiteLookupException) return error.message;',
    ]) {
      expect(_handCopy.hasMatch(copy), isTrue, reason: copy);
    }
    expect(_handCopy.hasMatch('failureText(error, fallback: f)'), isFalse);
    for (final scan in [_handler, _reported, _handCopy]) {
      expect(
        scan.hasMatch('showErrorDialog(context, error.message)'),
        isFalse,
        reason: scan.pattern,
      );
    }
  });

  test('plugins draw a failure through failureText, not a copy of it', () {
    final copies = [
      for (final entry in plugins.entries)
        if (_handCopy.hasMatch(entry.value)) entry.key,
    ];
    expect(copies, isEmpty, reason: 'call failureText in $_owner');
  });
}
