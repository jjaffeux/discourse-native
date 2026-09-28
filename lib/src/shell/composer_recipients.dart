import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
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
            label: 'Selected',
            options: [
              for (final name in recipients)
                if (name.toLowerCase().contains(query))
                  DComboboxOption(value: name, label: name),
            ],
          ),
        DComboboxOptionGroup(
          label: 'Users',
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
          label: 'Groups',
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
                    ? '${recipients.length} recipients'
                    : recipients.firstOrNull ?? 'Recipients',
                icon: recipients.isEmpty ? const DIcon(DIcons.users) : null,
                semanticLabel: recipients.isEmpty
                    ? 'Choose recipients'
                    : 'Recipients: ${recipients.join(', ')}',
                onPressed: widget.composer.isEditing ? trigger.toggle : null,
                focusNode: trigger.focusNode,
                expanded: trigger.open,
                maximumWidth: 210,
              ),
            )
          : const DComboboxChips<String>(
              input: DComboboxChipsInput<String>(
                key: ValueKey('composer-recipients-input'),
                placeholder: 'Add users or groups',
                autofocus: true,
              ),
            ),
      content: DComboboxContent(
        semanticLabel: 'Recipients',
        sheetOnMobile: true,
        fullScreenOnMobile: mobile,
        children: [
          if (mobile)
            const Padding(
              padding: EdgeInsets.all(4),
              child: DComboboxInput<String>(
                key: ValueKey('composer-recipients-input'),
                placeholder: 'Search users or groups',
                semanticLabel: 'Search recipients',
                registerAsAnchor: false,
                autofocus: true,
                showTrigger: false,
              ),
            ),
          const DComboboxEmpty<String>(
            child: Text('No users or groups found.'),
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
                const DFieldLabel(child: Text('To')),
                picker,
              ],
            ),
    );
  }
}
