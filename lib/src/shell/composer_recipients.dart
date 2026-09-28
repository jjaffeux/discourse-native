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
  final _query = TextEditingController();
  Timer? _debounce;
  int _searchGeneration = 0;
  FoundUsersAndGroups _results = const FoundUsersAndGroups();

  List<String> get _recipients => widget.composer.target.targetRecipients!
      .split(',')
      .where((name) => name.isNotEmpty)
      .toList();

  void _search(String query) {
    _debounce?.cancel();
    final generation = ++_searchGeneration;
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

  @override
  void dispose() {
    _debounce?.cancel();
    _searchGeneration++;
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mobile = context.isTouch;
    final recipients = _recipients;
    final query = _query.text.trim().toLowerCase();
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
      textController: _query,
      filterLocally: false,
      closeOnSelect: false,
      itemToStringLabel: (name) => name,
      onQueryChanged: (query, reason) {
        if (reason == DComboboxChangeReason.input) _search(query);
      },
      onOpenChanged: (open, reason) {
        if (mobile) {
          _debounce?.cancel();
          _searchGeneration++;
          if (open) {
            _query.clear();
            setState(() => _results = const FoundUsersAndGroups());
            _search('');
          }
        } else if (open && _results.users.isEmpty && _results.groups.isEmpty) {
          _search(_query.text);
        }
      },
      onValuesChanged: (values, reason) =>
          widget.composer.setRecipients(values),
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
