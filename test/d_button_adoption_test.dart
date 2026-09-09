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
  'lib/src/ui/components/d_button.dart': 1, // DButton's rendering primitive.
  // Rich-text focus examples, including their usage snippets.
  'lib/src/styleguide/examples/typography_examples.dart': 2,
  'lib/src/plugins/chat/chat_channel_view.dart': 2, // Dense selection strips.
  // Kalender's zero-padding day headers and compact overflow rows.
  'lib/src/plugins/discourse_events/topic_calendar.dart': 2,
  'lib/src/plugins/discourse_events/event_calendar.dart': 1,
  'lib/src/shell/composer_panel.dart': 2, // Submit and taxonomy controls.
  'lib/src/shell/do_not_disturb_dialog.dart': 1, // Fixed 44px option grid.
  'lib/src/shell/reaction_presentation.dart': 1, // Fixed 44px picker action.
  'lib/src/shell/topic_list_navigation.dart': 1, // Inset period selector.
  'lib/src/shell/topic_list_view.dart': 1, // Full-width incoming-topics notice.
  'lib/src/shell/topic_view.dart': 8, // Dense selection and inline link tools.
  'lib/src/shell/user_menu_button.dart': 2, // Fixed shell account control.
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
