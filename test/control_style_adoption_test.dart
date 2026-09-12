import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/control_adoption.dart';

void main() {
  test('application and kit compositions use only reference button variants', () {
    final legacy = RegExp(
      r'\bDButtonVariant\.(standard|danger|success|flat|flatClose|transparent|transparentPrimary|transparentDanger|transparentSuccess)\b',
    );
    final offenders = <String>[];
    for (final file in Directory(
      'lib/src',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') ||
          file.path.endsWith('/d_button.dart')) {
        continue;
      }
      if (legacy.hasMatch(controlCode(file.readAsStringSync()))) {
        offenders.add(file.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Choose primary, outline, secondary, ghost, destructive or link. Legacy enum names are SDK aliases only.',
    );
  });

  test('application button styling exceptions stay explicit', () {
    final actual = <String, Map<String, int>>{};
    for (final file in Directory(
      'lib/src',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') ||
          file.path.contains('/ui/') ||
          file.path.contains('/styleguide/')) {
        continue;
      }
      final overrides = buttonStyleOverrides(file.readAsStringSync());
      if (overrides.isNotEmpty) actual[file.path] = overrides;
    }
    expect(
      actual,
      {
        // Category identity uses the same tint on both halves of the control.
        'lib/src/shell/topic_inbox_header.dart': {
          'backgroundColor': 2,
          'borderColor': 2,
          'interactiveBackgroundColor': 2,
        },
        // A saved bookmark combines the kit's selected fill with its outline
        // variant so the joined group keeps a continuous perimeter and divider.
        'lib/src/shell/topic_actions.dart': {
          'backgroundColor': 2,
          'foregroundColor': 2,
          'interactiveBackgroundColor': 2,
        },
        // These are container/rail/navigation geometry, not alternative palettes.
        'lib/src/shell/instance_rail.dart': {'borderRadius': 1},
      },
      reason:
          'Use the kit variant and size first. Document a concrete semantic or layout reason before adding an exception.',
    );
  });

  test('override guard ignores examples and nested widget arguments', () {
    expect(
      buttonStyleOverrides('''
      // DButton(backgroundColor: ignored)
      final example = "DButton(padding: ignored)";
      DButton(label: Padding(padding: nested, child: label), onPressed: save,
        borderColor: colors.border, foregroundColor: colors.foreground);
      DButton.iconOnly(icon: Icon(icon), padding: edge);
    '''),
      {'borderColor': 1, 'foregroundColor': 1, 'padding': 1},
    );
  });
}
