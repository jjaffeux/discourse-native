import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../models/found_group.dart';
import '../theme/d_icons.dart';
import 'composer_controller.dart';
import 'platform.dart';
import 'shell_scope.dart';
import 'topic_taxonomy_button.dart';

class ComposerRecipients extends StatefulWidget {
  const ComposerRecipients({super.key, required this.composer});

  final ComposerController composer;

  @override
  State<ComposerRecipients> createState() => _ComposerRecipientsState();
}

class _ComposerRecipientsState extends State<ComposerRecipients> {
  String _query = '';
  Timer? _debounce;
  int _searchGeneration = 0;
  FoundUsersAndGroups _results = const FoundUsersAndGroups();
  bool _rejectedSelection = false;

  List<String> get _recipients => widget.composer.target.targetRecipients!
      .split(',')
      .where((name) => name.isNotEmpty)
      .toList();

  void _search(String query) {
    _debounce?.cancel();
    final generation = ++_searchGeneration;
    setState(() {
      _query = query;
      _results = const FoundUsersAndGroups();
    });
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      if (!mounted) return;
      final results = await ShellScope.read(context).searchMessageRecipients(
        siteUrl: widget.composer.target.siteUrl,
        term: query.trim(),
      );
      if (!mounted || generation != _searchGeneration) return;
      setState(() => _results = results);
    });
  }

  void _selectionChanged(List<String> values) {
    final current = _recipients;
    // An old row can still dispatch before the query edit rebuilds the popup.
    final accepted = values
        .where(
          (name) =>
              current.contains(name) ||
              _results.users.any((user) => user.username == name) ||
              _results.groups.any((group) => group.name == name),
        )
        .toList();
    _rejectedSelection = accepted.length != values.length;
    widget.composer.setRecipients(accepted);
  }

  void _queryChanged(String query, DComboboxChangeReason reason) {
    final rejectedReset =
        _rejectedSelection &&
        query.isEmpty &&
        (reason == DComboboxChangeReason.keyboard ||
            reason == DComboboxChangeReason.itemPress);
    _rejectedSelection = false;
    // Keep the replacement query and its lookup after rejecting an old row.
    if (!rejectedReset) _search(query);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchGeneration++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mobile = context.isTouch;
    final recipients = _recipients;
    final query = _query.trim().toLowerCase();
    final picker = DCombobox<String>.multipleControlled(
      key: const ValueKey('composer-private-message-recipients'),
      value: recipients,
      enabled: widget.composer.isEditing,
      options: const [],
      groups: [
        if (mobile)
          DComboboxOptionGroup(
            label: context.l10n.selectedComposerrecipients,
            options: [
              for (final name in recipients)
                if (name.toLowerCase().contains(query))
                  DComboboxOption(value: name, label: name),
            ],
          ),
        DComboboxOptionGroup(
          label: context.l10n.users,
          options: [
            for (final user in _results.users)
              if (!mobile || !recipients.contains(user.username))
                DComboboxOption(
                  value: user.username,
                  label: user.name == null
                      ? user.username
                      : '${user.username} · ${user.name}',
                ),
          ],
        ),
        DComboboxOptionGroup(
          label: context.l10n.groups,
          options: [
            for (final group in _results.groups)
              if (!mobile || !recipients.contains(group.name))
                DComboboxOption(value: group.name, label: group.name),
          ],
        ),
      ],
      query: _query,
      filterLocally: false,
      closeOnSelect: false,
      itemToStringLabel: (name) => name,
      onQueryChanged: _queryChanged,
      onOpenChanged: (open, reason) {
        if (mobile) {
          _debounce?.cancel();
          _searchGeneration++;
          if (open) {
            _search('');
          }
        } else if (open && _results.users.isEmpty && _results.groups.isEmpty) {
          _search(_query);
        }
      },
      onValuesChanged: (values, reason) => _selectionChanged(values),
      anchor: mobile
          ? DComboboxTrigger<String>(
              builder: (context, trigger) => TopicTaxonomyButton(
                buttonKey: const ValueKey('composer-recipients'),
                size: DButtonSize.toolbar,
                showChevron: true,
                label: recipients.length > 1
                    ? context.l10n.recipientsComposerrecipientsValue(
                        (recipients.length).toString(),
                      )
                    : recipients.firstOrNull ?? context.l10n.recipients,
                icon: recipients.isEmpty ? const DIcon(DIcons.users) : null,
                semanticLabel: recipients.isEmpty
                    ? context.l10n.chooseRecipients
                    : context.l10n.recipientsComposerrecipients(
                        (recipients.join(', ')).toString(),
                      ),
                onPressed: widget.composer.isEditing ? trigger.toggle : null,
                focusNode: trigger.focusNode,
                expanded: trigger.open,
                maximumWidth: 210,
              ),
            )
          : DComboboxChips<String>(
              input: DComboboxChipsInput<String>(
                key: const ValueKey('composer-recipients-input'),
                placeholder: context.l10n.addUsersOrGroups,
                autofocus: true,
              ),
            ),
      content: DComboboxContent(
        semanticLabel: context.l10n.recipients,
        sheetOnMobile: true,
        fullScreenOnMobile: mobile,
        children: [
          if (mobile)
            Padding(
              padding: const EdgeInsets.all(4),
              child: DComboboxInput<String>(
                key: const ValueKey('composer-recipients-input'),
                placeholder: context.l10n.searchUsersOrGroups,
                semanticLabel: context.l10n.searchRecipients,
                registerAsAnchor: false,
                autofocus: true,
                showTrigger: false,
              ),
            ),
          DComboboxEmpty<String>(
            child: Text(context.l10n.noUsersOrGroupsFound),
          ),
          const DComboboxList<String>(),
        ],
      ),
    );
    return Padding(
      padding: mobile
          ? const EdgeInsets.fromLTRB(
              DSpacing.lg,
              DSpacing.md,
              DSpacing.lg,
              DSpacing.controlGap,
            )
          : const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: mobile
          ? Align(alignment: AlignmentDirectional.centerStart, child: picker)
          : DField(
              children: [
                DFieldLabel(child: Text(context.l10n.to)),
                picker,
              ],
            ),
    );
  }
}
