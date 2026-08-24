import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../tool/flutter_webrtc_contract.dart';

void main() {
  group('compareVendorFiles', () {
    test('accepts exactly the documented changed-file inventory', () {
      final comparison = compareVendorFiles(
        baseline: {
          'modified.txt': _bytes('upstream'),
          'unchanged.txt': _bytes('same'),
        },
        vendor: {
          'added.txt': _bytes('local'),
          'modified.txt': _bytes('patched'),
          'unchanged.txt': _bytes('same'),
        },
        documentedPatches: {'added.txt', 'modified.txt'},
      );

      expect(comparison.matchesDocumentedInventory, isTrue);
      expect(comparison.differences, {
        'added.txt': VendorDifferenceKind.added,
        'modified.txt': VendorDifferenceKind.modified,
      });
    });

    test('reports every undocumented added, modified, and removed file', () {
      final comparison = compareVendorFiles(
        baseline: {
          'modified.txt': _bytes('upstream'),
          'removed.txt': _bytes('upstream'),
        },
        vendor: {
          'added.txt': _bytes('local'),
          'modified.txt': _bytes('patched'),
        },
        documentedPatches: const {},
      );

      expect(comparison.matchesDocumentedInventory, isFalse);
      expect(comparison.undocumentedDifferences, [
        'added.txt',
        'modified.txt',
        'removed.txt',
      ]);
      expect(comparison.differences['added.txt'], VendorDifferenceKind.added);
      expect(
        comparison.differences['modified.txt'],
        VendorDifferenceKind.modified,
      );
      expect(
        comparison.differences['removed.txt'],
        VendorDifferenceKind.removed,
      );
    });

    test('rejects a documented file that no longer differs', () {
      final comparison = compareVendorFiles(
        baseline: {'restored.txt': _bytes('same')},
        vendor: {'restored.txt': _bytes('same')},
        documentedPatches: {'restored.txt'},
      );

      expect(comparison.matchesDocumentedInventory, isFalse);
      expect(comparison.undocumentedDifferences, isEmpty);
      expect(comparison.documentedFilesWithoutDifference, ['restored.txt']);
    });
  });

  test('reads only exact backticked file bullets as the patch inventory', () {
    const markdown = '''
- Archive SHA-256: `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa`

Files:

- `lib/one.dart`
- `native/two.cc`

Run `dart run tool/flutter_webrtc_contract.dart`.
''';

    expect(parseDocumentedPatchInventory(markdown), {
      'lib/one.dart',
      'native/two.cc',
    });
    expect(
      parseDocumentedArchiveSha256(markdown),
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
  });

  test('rejects duplicate documented patch files', () {
    const markdown = '''
- `lib/repeated.dart`
- `lib/repeated.dart`
''';

    expect(
      () => parseDocumentedPatchInventory(markdown),
      throwsFormatException,
    );
  });

  test('computes a lowercase SHA-256', () {
    expect(
      sha256Hex(utf8.encode('abc')),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });
}

List<int> _bytes(String value) => utf8.encode(value);
