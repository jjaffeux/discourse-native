import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _materialButtonConstructor = RegExp(
  r'\b(?:FilledButton|OutlinedButton|TextButton)'
  r'(?:\.(?:icon|tonal|tonalIcon))?\s*\(',
);

// These controls depend on Material-specific geometry or composition rather
// than representing ordinary Discourse actions. Keep the counts explicit so
// adding another raw Material button requires reviewing this boundary.
const _intentionalMaterialButtons = <String, int>{
  'lib/src/theme/d_button.dart': 1, // DButton's rendering primitive.
  'lib/src/plugins/poll/poll_card.dart': 3, // Vote/result control group.
  'lib/src/plugins/chat/chat_channel_view.dart': 2, // Dense selection strips.
  'lib/src/shell/composer_panel.dart': 1, // Bespoke composer submit control.
  'lib/src/shell/composer_image_gallery.dart': 1, // Fixed gallery edit strip.
  'lib/src/shell/do_not_disturb_dialog.dart': 1, // Fixed 44px option grid.
  'lib/src/shell/reaction_presentation.dart': 1, // Fixed 44px picker action.
  'lib/src/shell/topic_create_button.dart': 3, // Split primary/menu control.
  'lib/src/shell/topic_view.dart': 8, // Dense selection and inline link tools.
  'lib/src/shell/user_menu_button.dart': 2, // Fixed shell account control.
  'lib/src/shell/user_summary.dart': 1, // Compact numeric count link.
};

void main() {
  test('ordinary app actions use DButton', () {
    final actual = <String, int>{};

    for (final entity in Directory('lib/src').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final count = _materialButtonConstructor
          .allMatches(entity.readAsStringSync())
          .length;
      if (count > 0) {
        actual[entity.path] = count;
      }
    }

    expect(
      actual,
      _intentionalMaterialButtons,
      reason:
          'Ordinary actions use DButton so size, variants, loading, focus, and '
          'disabled behavior stay consistent. Add an exception only for a '
          'reviewed control that needs Material-specific composition.',
    );
  });
}
