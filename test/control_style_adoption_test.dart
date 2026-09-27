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
          'Choose primary, outline, secondary, ghost, destructive, link, inline or transparentBackground. Legacy enum names are SDK aliases only.',
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
        // Mobile navigation uses the requested independent circular buttons
        // and pill contextual actions, through Native's existing shape API.
        'lib/src/shell/mobile_shell.dart': {'shape': 4},
        'lib/src/shell/message_create_button.dart': {'shape': 2},
        // Composer gutter actions retain the documented transparent surface.
        'lib/src/shell/composer_block_surface.dart': {'backgroundColor': 1},
        // The mobile topic reader has a floating pill progress trigger; the
        // inline trigger sits on the header without a resting or hover fill.
        'lib/src/shell/topic_progress.dart': {
          'shape': 1,
          'backgroundColor': 1,
          'interactiveBackgroundColor': 1,
        },
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
          'backgroundColor': 2,
          'borderColor': 2,
          'interactiveBackgroundColor': 2,
        },
        // Category dropdowns reuse the topic header's category identity tint.
        'lib/src/shell/topic_taxonomy_button.dart': {
          'backgroundColor': 1,
          'borderColor': 1,
          'interactiveBackgroundColor': 1,
        },
        // Start page links are borderless chips on the footer surface, with
        // the neutral accent hover; no kit variant fills without a border.
        'lib/src/shell/new_tab_page.dart': {
          'backgroundColor': 1,
          'interactiveBackgroundColor': 1,
          'borderColor': 1,
          'foregroundColor': 1,
        },
        // A saved bookmark combines the kit's selected fill with its outline
        // variant so the joined group keeps a continuous perimeter and divider.
        'lib/src/shell/topic_actions.dart': {
          'backgroundColor': 2,
          'foregroundColor': 2,
          'interactiveBackgroundColor': 2,
        },
        // User-approved header capsules use each core notification color.
        'lib/src/shell/header_notification_button.dart': {
          'backgroundColor': 1,
          'foregroundColor': 1,
          'interactiveBackgroundColor': 1,
          'borderRadius': 1,
        },
        // The avatar trigger is an outlined circle around the avatar, with no
        // fill of its own at rest or on hover.
        'lib/src/shell/user_menu_button.dart': {
          'shape': 1,
          'backgroundColor': 1,
          'interactiveBackgroundColor': 1,
          'borderColor': 1,
        },
        // Composer tools use the mockup's muted tool foreground; discarding a
        // draft uses a destructive tint rather than the solid kit fill.
        'lib/src/shell/composer_panel.dart': {
          'foregroundColor': 8,
          'shape': 1,
          'backgroundColor': 1,
          'interactiveBackgroundColor': 1,
        },
        // Tab strip scroll affordances are the mockup's circular buttons.
        'lib/src/shell/forum_tabs_bar.dart': {'shape': 1},
        // A day separator is a pill on the stream's own surface and border.
        'lib/src/shell/stream_day_separator.dart': {
          'shape': 1,
          'backgroundColor': 1,
          'interactiveBackgroundColor': 1,
          'foregroundColor': 1,
          'borderColor': 1,
        },
        // Chat's primary sidebar action is the mockup's pill.
        'lib/src/plugins/chat/chat_inbox.dart': {'shape': 1},
        // Message hover actions sit on the row's own hover fill.
        'lib/src/plugins/chat/chat_message_tile.dart': {
          'interactiveBackgroundColor': 2,
        },
        // These are container/rail/navigation geometry, not alternative palettes.
        // Rail actions use the rail foreground on the rail's own surface;
        // collapsed sidebar is muted.
        'lib/src/shell/instance_rail.dart': {
          'borderRadius': 1,
          'foregroundColor': 2,
          'backgroundColor': 2,
          'interactiveBackgroundColor': 2,
        },
        // A minimized panel's rail stands in for its tab strip: the selected
        // tab keeps the selected document tab's raised fill and outline, on
        // the reference's circular slots, in the rail and in its read-out.
        'lib/src/shell/panel_rail.dart': {
          'shape': 1,
          'backgroundColor': 2,
          'borderColor': 2,
          'foregroundColor': 2,
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
