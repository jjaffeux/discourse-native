import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../theme/d_icons.dart';
import 'forum_appearance_settings.dart';
import 'platform.dart';

Future<void> showForumSettingsDialog(
  BuildContext context, {
  required String siteUrl,
  required String name,
}) => context.isTouch
    ? showDSheet<void>(
        context: context,
        side: DSheetSide.bottom,
        builder: (_, _) => DSheetContent(
          key: const ValueKey('forum-settings-dialog'),
          side: DSheetSide.bottom,
          semanticLabel: 'Forum settings',
          closeButton: const _SettingsClose(),
          scrollWholeSheet: false,
          children: [
            ForumSettingsDialog(siteUrl: siteUrl, name: name, embedded: true),
          ],
        ),
      )
    : showDDialog<void>(
        context: context,
        builder: (_, _) => ForumSettingsDialog(siteUrl: siteUrl, name: name),
      );

enum _SettingsSection { appearance }

class ForumSettingsDialog extends StatefulWidget {
  const ForumSettingsDialog({
    super.key,
    required this.siteUrl,
    required this.name,
    this.embedded = false,
  });

  final String siteUrl;
  final String name;
  final bool embedded;

  @override
  State<ForumSettingsDialog> createState() => _ForumSettingsDialogState();
}

class _ForumSettingsDialogState extends State<ForumSettingsDialog> {
  _SettingsSection _section = _SettingsSection.appearance;
  final _appearanceKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final content = _content(context);
    if (widget.embedded) return content;
    return DDialogContent(
      key: const ValueKey('forum-settings-dialog'),
      maxWidth: 1160,
      semanticLabel: 'Forum settings',
      contentPadding: EdgeInsets.zero,
      verticalPadding: 0,
      spacing: 0,
      closeButton: const _SettingsClose(),
      children: [content],
    );
  }

  Widget _content(BuildContext context) => SizedBox(
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
                    padding: const EdgeInsets.symmetric(vertical: DSpacing.md),
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
                                key: ValueKey('forum-settings-${section.name}'),
                                icon: const DIcon(DIcons.display),
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
  );

  String _label(_SettingsSection section) => switch (section) {
    _SettingsSection.appearance => 'Appearance',
  };
}

class _SettingsClose extends StatelessWidget {
  const _SettingsClose();

  @override
  Widget build(BuildContext context) => DDialogClose<void>(
    builder: (_, close) => DButton.iconOnly(
      key: const ValueKey('forum-settings-close'),
      onPressed: close,
      icon: const DIcon(DIcons.xmark),
      tooltip: 'Close',
      semanticLabel: 'Close settings',
      size: DButtonSize.small,
      variant: DButtonVariant.ghost,
    ),
  );
}
