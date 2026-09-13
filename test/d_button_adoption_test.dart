import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/control_adoption.dart';

final _frameworkControlConstructor = RegExp(
  r'\b(?:IconButton|FilledButton|OutlinedButton|TextButton|ElevatedButton|'
  r'CupertinoButton|PopupMenuButton|PopupMenuItem|CheckedPopupMenuItem|'
  r'PopupMenuDivider|MenuItemButton|SubmenuButton|MenuAnchor|MenuBar|'
  r'SegmentedButton|ButtonSegment|ToggleButtons|DropdownButton|'
  r'DropdownButtonFormField|DropdownMenu)'
  r'(?:\s*<[^;(){}]*>)?(?:\.[a-zA-Z]+)?\s*\(',
);

void main() {
  test('application actions, menus, and selectors use the UI kit', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File ||
          !entity.path.endsWith('.dart') ||
          entity.path.startsWith('lib/src/ui/')) {
        continue;
      }
      final code = controlCode(entity.readAsStringSync());
      for (final match in _frameworkControlConstructor.allMatches(code)) {
        final line = '\n'.allMatches(code.substring(0, match.start)).length + 1;
        offenders.add('${entity.path}:$line: ${match[0]}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Use DButton, DToggleGroup, DSelect, DDropdownMenu, or DContextMenu '
          'through discourse_ui.dart. Framework controls belong only inside '
          'the UI kit; application code and examples have no exceptions.',
    );
  });
}
