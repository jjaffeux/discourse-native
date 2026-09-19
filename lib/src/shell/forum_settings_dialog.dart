import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../theme/d_icons.dart';
import 'forum_appearance_settings.dart';

Future<void> showForumSettingsDialog(
  BuildContext context, {
  required String siteUrl,
  required String name,
}) => showDDialog<void>(
  context: context,
  builder: (_, _) => ForumSettingsDialog(siteUrl: siteUrl, name: name),
);

enum _SettingsSection { general, appearance }

class ForumSettingsDialog extends StatefulWidget {
  const ForumSettingsDialog({
    super.key,
    required this.siteUrl,
    required this.name,
  });

  final String siteUrl;
  final String name;

  @override
  State<ForumSettingsDialog> createState() => _ForumSettingsDialogState();
}

class _ForumSettingsDialogState extends State<ForumSettingsDialog> {
  _SettingsSection _section = _SettingsSection.appearance;
  final _appearanceKey = GlobalKey();

  @override
  Widget build(BuildContext context) => DDialogContent(
    key: const ValueKey('forum-settings-dialog'),
    maxWidth: 1160,
    semanticLabel: 'Forum settings',
    contentPadding: EdgeInsets.zero,
    verticalPadding: 0,
    spacing: 0,
    closeButton: DDialogClose<void>(
      builder: (_, close) => DButton.iconOnly(
        key: const ValueKey('forum-settings-close'),
        onPressed: close,
        icon: const DIcon(DIcons.xmark),
        tooltip: 'Close',
        semanticLabel: 'Close settings',
        size: DButtonSize.small,
        variant: DButtonVariant.ghost,
      ),
    ),
    children: [
      SizedBox(
        height: math.min(
          720,
          math.max(200, MediaQuery.sizeOf(context).height - 96),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide =
                constraints.maxWidth >= 780 &&
                MediaQuery.textScalerOf(context).scale(14) < 24;
            final content = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(24, 24, 48, 20),
                  child: wide
                      ? DDialogTitle(child: Text(_label(_section)))
                      : DSelect<_SettingsSection>.controlled(
                          semanticLabel: 'Settings section',
                          value: _section,
                          isExpanded: true,
                          entries: [
                            for (final section in _SettingsSection.values)
                              DSelectOption(
                                value: section,
                                label: _label(section),
                                child: Text(_label(section)),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _section = value);
                          },
                        ),
                ),
                Expanded(
                  child: IndexedStack(
                    index: _section.index,
                    children: [
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(DSpacing.xl),
                        child: DFieldGroup(
                          children: [
                            DInput(
                              labelText: 'Forum',
                              value: widget.name,
                              readOnly: true,
                            ),
                            DInput(
                              labelText: 'Address',
                              value: widget.siteUrl,
                              readOnly: true,
                            ),
                          ],
                        ),
                      ),
                      ForumAppearanceSettings(
                        key: _appearanceKey,
                        siteUrl: widget.siteUrl,
                      ),
                    ],
                  ),
                ),
              ],
            );
            if (!wide) return content;
            return DSidebarProvider(
              mobileBreakpoint: 0,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DSidebar(
                    width: 184,
                    collapsible: DSidebarCollapsible.none,
                    semanticLabel: 'Forum settings sections',
                    header: DSidebarHeader(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: DSpacing.md,
                        ),
                        child: Text(
                          widget.name,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    ),
                    child: DSidebarContent(
                      children: [
                        DSidebarGroup(
                          child: DSidebarMenu(
                            children: [
                              for (final section in _SettingsSection.values)
                                DSidebarMenuItem(
                                  child: DSidebarMenuButton(
                                    key: ValueKey(
                                      'forum-settings-${section.name}',
                                    ),
                                    icon: DIcon(
                                      section == _SettingsSection.general
                                          ? DIcons.gear
                                          : DIcons.display,
                                    ),
                                    isActive: _section == section,
                                    onPressed: () =>
                                        setState(() => _section = section),
                                    child: Text(_label(section)),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: content),
                ],
              ),
            );
          },
        ),
      ),
    ],
  );

  String _label(_SettingsSection section) => switch (section) {
    _SettingsSection.general => 'General',
    _SettingsSection.appearance => 'Appearance',
  };
}
