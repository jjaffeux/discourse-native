import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/control_adoption.dart';

void main() {
  test('application and kit compositions use approved button variants', () {
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
          'Choose primary, outline, secondary, ghost, destructive, link, inline.',
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
        // Contextual actions use Native's existing pill shape API.
        'lib/src/shell/message_create_button.dart': {'shape': 3},
        // Composer gutter actions retain the documented transparent surface.
        'lib/src/shell/composer/block_surface.dart': {'backgroundColor': 1},
        // Topic progress uses Native timeline artwork and the existing pill shape.
        'lib/src/shell/topic_progress.dart': {'shape': 1},
        // X embeds retain provider identity and the reference's pill reply link,
        // using Native buttons for sizing, focus, hover and activation.
        'lib/src/shell/oneboxes/twitter.dart': {
          'foregroundColor': 4,
          'backgroundColor': 1,
          'borderColor': 1,
          'shape': 1,
        },
        // Category identity uses the same tint on both halves of the control.
        'lib/src/shell/topic_inbox_header.dart': {
          'foregroundColor': 2,
          'backgroundColor': 2,
          'borderColor': 2,
          'interactiveBackgroundColor': 2,
        },
        // Category dropdowns reuse the topic header's category identity tint.
        'lib/src/shell/topic_taxonomy_button.dart': {
          'foregroundColor': 1,
          'backgroundColor': 1,
          'borderColor': 1,
          'interactiveBackgroundColor': 1,
        },
        // A saved bookmark keeps the neutral outline and accents its artwork.
        'lib/src/shell/topic_actions.dart': {
          'backgroundColor': 1,
          'foregroundColor': 1,
          'interactiveBackgroundColor': 1,
        },
        // Header notification capsules use a circular/pill shape and core color.
        'lib/src/shell/header_notification_button.dart': {
          'shape': 2,
          'foregroundColor': 1,
        },
        // The avatar trigger uses the mockup's 22% outline around the avatar,
        // with no fill of its own at rest or on hover.
        'lib/src/shell/user_menu_button.dart': {
          'shape': 2,
          'backgroundColor': 1,
          'interactiveBackgroundColor': 1,
          'borderColor': 1,
        },
        // Composer tools use the mockup's muted tool foreground; discarding a
        // draft uses a destructive tint rather than the solid kit fill. Image
        // and gallery actions use the same pill shape as the discard control.
        'lib/src/shell/composer/panel.dart': {
          'foregroundColor': 12,
          'shape': 3,
          'backgroundColor': 1,
          'interactiveBackgroundColor': 1,
        },
        'lib/src/shell/composer/components/image.dart': {'foregroundColor': 1},
        // The chat composer's add and emoji tools use the same muted tool
        // foreground; its Send action pins the primary palette so the dock's
        // style scope cannot restyle its one solid control.
        'lib/src/plugins/chat/chat_composer.dart': {
          'foregroundColor': 4,
          'backgroundColor': 2,
          'interactiveBackgroundColor': 2,
        },
        // A day separator is a pill on the stream's own surface and border.
        'lib/src/shell/stream_day_separator.dart': {
          'shape': 1,
          'backgroundColor': 1,
          'interactiveBackgroundColor': 1,
          'foregroundColor': 1,
          'borderColor': 1,
        },
        // Browse's Join/Joined row action is the mockup's pill.
        'lib/src/plugins/chat/chat_browse_channels_view.dart': {'shape': 1},
        // The chat jump-to-latest control shares the topic progress capsule.
        'lib/src/plugins/chat/chat_channel_view.dart': {'shape': 1},
        // Mobile user-card actions match the documented borderless pill row.
        // Chat uses the mockup's muted fill beside the primary Message action.
        'lib/src/shell/user_card.dart': {'shape': 2, 'borderColor': 2},
        'lib/src/plugins/chat/chat_user_card.dart': {
          'shape': 1,
          'backgroundColor': 1,
          'borderColor': 1,
          'foregroundColor': 1,
        },
        'lib/src/plugins/voice/voice_user_card.dart': {
          'shape': 1,
          'borderColor': 1,
        },
        // Composer and sheet close actions share the existing pill shape.
        'lib/src/shell/composer/header.dart': {'shape': 1},
        'lib/src/plugin_api/composer_sheet_header.dart': {'shape': 1},
        // Message hover actions sit on the row's own hover fill.
        'lib/src/plugins/chat/chat_message_tile.dart': {
          'interactiveBackgroundColor': 2,
        },
        // These are container/rail/navigation geometry, not alternative palettes.
        // Rail actions use the rail foreground on the rail's own surface;
        // collapsed sidebar is muted, and a failed load retries in the error tint.
        'lib/src/shell/instance_rail.dart': {
          'shape': 1,
          'foregroundColor': 5,
          'backgroundColor': 5,
          'interactiveBackgroundColor': 3,
        },
        // Window/sidebar destinations and their search/close actions are pills.
        'lib/src/shell/title_bar.dart': {'shape': 2},
        'lib/src/shell/global_search_panel.dart': {'shape': 1},
        'lib/src/shell/main_content.dart': {'shape': 1},
        'lib/src/shell/user_menu.dart': {'shape': 2, 'foregroundColor': 1},
        // Creation and drafting actions use the established pill artwork.
        'lib/src/shell/topic_create_button.dart': {'shape': 1},
        // Inline taxonomy edit actions are the same pill as the tag chips.
        'lib/src/shell/topic_taxonomy_fields.dart': {'shape': 1},
        'lib/src/shell/composer/draft_tabs.dart': {'shape': 1},
        // Shared category paths and list filters supply their quiet selection fill.
        // The incoming-topics pill stays quiet yet keeps the primary fill.
        'lib/src/shell/topic_list_view.dart': {
          'backgroundColor': 1,
          'foregroundColor': 1,
        },
        // Topic metadata actions retain the metadata row's text foreground.
        'lib/src/shell/topic_card_metadata.dart': {'foregroundColor': 2},
        // Chat search/navigation and the local-date sheet use pill controls.
        'lib/src/plugins/chat/chat_header_button.dart': {'shape': 1},
        'lib/src/plugins/local_dates/local_date_preview_sheet.dart': {
          'shape': 1,
        },
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
      DButton.iconOnly(icon: Icon(icon), shape: DButtonShape.pill, padding: edge);
    '''),
      {'borderColor': 1, 'foregroundColor': 1, 'shape': 1, 'padding': 1},
    );
  });
}
