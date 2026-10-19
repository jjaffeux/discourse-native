import 'package:discourse_native/src/shell/composer/markdown_highlight.dart';
import 'package:discourse_native/src/shell/syntax.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Snapshot = ({
  List<(int, int, int, String?, String?)> runs,
  List<({int offset, String text})> blocks,
  List<(int, int)> code,
  List<(int, int)> fences,
  List<(String, String?)> deferred,
});

var _evictions = 0;

void _evictScans() {
  for (var index = 0; index < 4; index += 1) {
    scanMarkdown('Unrelated cache entry ${_evictions++} / $index !');
  }
}

_Snapshot _snapshot(String source, {bool defer = false}) {
  final deferred = <(String, String?)>[];
  final scan = scanMarkdownBlocks(
    source,
    deferHighlight: defer
        ? (body, language) => deferred.add((body, language))
        : null,
  );
  return (
    runs: [
      for (final run in scan.runs)
        (run.start, run.end, run.mask, run.detail, run.token),
    ],
    blocks: scan.blocks,
    code: markdownCodeRanges(source).ranges.toList(),
    fences: markdownFenceRanges(source).ranges.toList(),
    deferred: deferred,
  );
}

void _expectSame(_Snapshot actual, _Snapshot expected) {
  expect(actual.runs, expected.runs);
  expect(actual.blocks, expected.blocks);
  expect(actual.code, expected.code);
  expect(actual.fences, expected.fences);
  expect(actual.deferred, expected.deferred);
}

_Snapshot _compareEdit(
  String before,
  String after, {
  required int scannedUnits,
}) {
  _evictScans();
  _snapshot(before);
  final units = markdownScannedCodeUnits;
  final scans = markdownScanCount;
  final incremental = _snapshot(after);
  expect(markdownScanCount, scans + 1);
  expect(markdownScannedCodeUnits - units, scannedUnits);
  _evictScans();
  final full = _snapshot(after);
  _expectSame(incremental, full);
  return incremental;
}

void main() {
  setUp(() {
    _evictScans();
    clearSyntaxHighlightCacheForTesting();
  });

  const prefix =
      '# Draft heading\n\n'
      '> nested **quote** with `code`\n> another line\n\n'
      '```dart\nfinal sample = 1;\n```\n\n';
  const suffix =
      '\n\n'
      ':smile::smile: @sam and @sam #support\n\n'
      '| Column | Value |\n| --- | --- |\n| one | two |\n\n'
      '<kbd>**unchanged**</kbd> [tail](https://example.test/end)';

  test(
    'ordinary edits scan one paragraph and preserve full-source offsets',
    () {
      const paragraph = 'Editing destination alpha content';
      for (final updated in [
        'Editing destination alphax content',
        'Editing destination alha content',
        'Editing destination alXYZ content',
        '${paragraph}x',
        'Editing destination alpha conten',
      ]) {
        _compareEdit(
          '$prefix$paragraph$suffix',
          '$prefix$updated$suffix',
          scannedUnits: updated.length,
        );
      }
    },
  );

  test('alphabetic typing at EOF reuses the final paragraph', () {
    const paragraph = 'The final paragraph ends with letters';
    _compareEdit(
      '$prefix$paragraph',
      '$prefix${paragraph}x',
      scannedUnits: paragraph.length + 1,
    );
    _compareEdit('word', 'words', scannedUnits: 5);
    _compareEdit('words', 'word', scannedUnits: 4);
  });

  test('fragment scans retain inline context and intentional token cuts', () {
    const paragraphs = [
      'Anchor **bold alpha** and ***both*** plus _italic_',
      'Anchor <kbd>alpha <sup>beta</sup></kbd> tail',
      'Anchor [color=red]alpha [bgcolor=#abc]beta[/bgcolor][/color]',
      'Anchor [alpha](https://example.test/a_b) and https://example.test/c#top',
      'Anchor `alpha **literal**` and ``a ` beta`` tail',
      r'Anchor alpha \*escaped\* and \\`code` tail',
      'Anchor :smile::smile: alpha :smile::smile:',
      'Anchor @alpha and @alpha #support #support alpha',
      'Anchor **open alpha\ncontinued** and <kbd>beta\nnext</kbd>',
      'Anchor 😀 alpha café Ελληνικά and @Jürgen tail',
      '> Quote alpha\n>> nested beta\n* list gamma\n1. ordered delta',
      'Anchor <del>unclosed alpha and [open and _unpaired',
      'Anchor alpha\r\nsecond line beta',
    ];
    for (final paragraph in paragraphs) {
      final at = paragraph.indexOf('alpha') + 3;
      final updated = paragraph.replaceRange(at, at, 'X');
      _compareEdit(
        '$prefix$paragraph$suffix',
        '$prefix$updated$suffix',
        scannedUnits: updated.length,
      );
    }
  });

  test('repeated identical emoji stay separate after a paragraph splice', () {
    const paragraph = 'Anchor alpha :smile::smile:';
    const updated = 'Anchor alphax :smile::smile:';
    final result = _compareEdit(
      '$prefix$paragraph$suffix',
      '$prefix$updated$suffix',
      scannedUnits: updated.length,
    );
    final emoji = result.runs.where((run) => run.$3 & Md.emoji != 0).toList();
    expect(emoji.length, 4);
    expect(emoji[0].$2, emoji[1].$1);
    expect(emoji[2].$2, emoji[3].$1);
    expect(emoji.every((run) => run.$2 - run.$1 == ':smile:'.length), isTrue);
  });

  test('run coalescing crosses unchanged paragraph separators exactly', () {
    _compareEdit(
      'First plain paragraph\n\nMiddle alpha paragraph\n\nLast plain paragraph',
      'First plain paragraph\n\nMiddle alphax paragraph\n\nLast plain paragraph',
      scannedUnits: 'Middle alphax paragraph'.length,
    );
    _compareEdit(
      '```\ncode\n```\nParagraph alpha',
      '```\ncode\n```\nParagraph alphax',
      scannedUnits: '\nParagraph alphax'.length,
    );
  });

  test('consecutive edits and readers reuse only complete immutable scans', () {
    var paragraph = 'Anchor alpha :smile::smile:';
    var source = '$prefix$paragraph$suffix';
    var incremental = _snapshot(source);
    for (var edit = 0; edit < 12; edit += 1) {
      paragraph = paragraph.replaceFirst('alpha', 'alphax');
      source = '$prefix$paragraph$suffix';
      final units = markdownScannedCodeUnits;
      final scan = scanMarkdownBlocks(source);
      expect(markdownScannedCodeUnits - units, paragraph.length);
      final scans = markdownScanCount;
      expect(sharedMarkdownScan(source).runs, same(scan.runs));
      expect(sharedMarkdownScan(source).blocks, same(scan.blocks));
      markdownCodeRanges(source);
      markdownFenceRanges(source);
      expect(markdownScanCount, scans);
      expect(() => scan.runs.clear(), throwsUnsupportedError);
      expect(() => scan.blocks.clear(), throwsUnsupportedError);
      incremental = (
        runs: [
          for (final run in scan.runs)
            (run.start, run.end, run.mask, run.detail, run.token),
        ],
        blocks: scan.blocks,
        code: markdownCodeRanges(source).ranges.toList(),
        fences: markdownFenceRanges(source).ranges.toList(),
        deferred: [],
      );
    }
    _evictScans();
    _expectSame(incremental, _snapshot(source));
  });

  test(
    'syntax, whitespace, Unicode and boundary edits use the full scanner',
    () {
      const paragraph = 'Anchor alpha beta';
      final changes = <String>[
        'Anchor alpha! beta',
        'Anchor alpha beta ',
        'Anchor alpha\n beta',
        'Anchor alpha\r\n beta',
        'Anchor alpha` beta',
        'Anchor alpha~ beta',
        'Anchor alpha_ beta',
        'Anchor alpha😀 beta',
        'Anchor alphaé beta',
        'X$paragraph',
        'Anchor alpha ${'b' * 258}',
        'Anchor alpha\n\nbeta',
      ];
      for (final updated in changes) {
        const before = '$prefix$paragraph$suffix';
        final after = '$prefix$updated$suffix';
        _compareEdit(before, after, scannedUnits: after.length);
      }
      const blankLineEdit = 'First\n\n\n\nLast';
      _compareEdit(
        'First\n\na\n\nLast',
        blankLineEdit,
        scannedUnits: blankLineEdit.length,
      );
      _compareEdit('Anchor\n\nword', 'Anchor\nword', scannedUnits: 11);
    },
  );

  test('fence and unterminated fence edits use the full scanner', () {
    for (final fence in [
      '```dart\nfinal alpha = 1;\n```',
      '~~~dart\nfinal alpha = 1;\n~~~',
      '```dart\nfinal alpha = 1;',
    ]) {
      final before = 'Anchor paragraph\n\n$fence';
      final after = before.replaceFirst('alpha', 'alphax');
      _compareEdit(before, after, scannedUnits: after.length);
    }
  });

  for (final length in [512, 513]) {
    test('fence body of $length units keeps highlighting callback semantics', () {
      final body =
          '${'final value = 1; // ${'x' * length}'.substring(0, length - 1)}\n';
      final before = '```dart\n$body```\n\nAnchor alpha';
      final after = before.replaceFirst('alpha', 'alphax');
      _snapshot(before);
      clearSyntaxHighlightCacheForTesting();
      final units = markdownScannedCodeUnits;
      final actual = _snapshot(after, defer: true);
      expect(
        markdownScannedCodeUnits - units,
        length == 512 ? 'Anchor alphax'.length : after.length,
      );
      expect(actual.deferred, length == 512 ? isEmpty : [(body, 'dart')]);
      _evictScans();
      clearSyntaxHighlightCacheForTesting();
      _expectSame(actual, _snapshot(after, defer: true));
    });
  }

  test('a deferred base never supplies an incremental result', () {
    final body = 'final value = 1;\n' * 40;
    final before = '```dart\n$body```\n\nAnchor alpha';
    final after = before.replaceFirst('alpha', 'alphax');
    final initial = _snapshot(before, defer: true);
    expect(initial.deferred, [(body, 'dart')]);
    final units = markdownScannedCodeUnits;
    final actual = _snapshot(after, defer: true);
    expect(markdownScannedCodeUnits - units, after.length);
    _evictScans();
    clearSyntaxHighlightCacheForTesting();
    _expectSame(actual, _snapshot(after, defer: true));
  });

  test('a same-source scan still rechecks deferred highlighting', () {
    final body = 'final value = 1;\n' * 40;
    final source = '```dart\n$body```\n\nAnchor alpha';
    _snapshot(source);
    clearSyntaxHighlightCacheForTesting();
    final units = markdownScannedCodeUnits;
    final actual = _snapshot(source, defer: true);
    expect(markdownScannedCodeUnits - units, source.length);
    expect(actual.deferred, [(body, 'dart')]);
  });
}
