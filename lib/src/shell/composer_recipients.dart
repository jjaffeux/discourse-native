import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/found_group.dart';
import 'composer_controller.dart';
import 'shell_scope.dart';

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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
    child: DField(
      children: [
        const DFieldLabel(child: Text('To')),
        DCombobox<String>.multipleControlled(
          key: const ValueKey('composer-private-message-recipients'),
          value: _recipients,
          options: const [],
          groups: [
            DComboboxOptionGroup(
              label: 'Users',
              options: [
                for (final user in _results.users)
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
            if (open && _results.users.isEmpty && _results.groups.isEmpty) {
              _search(_query.text);
            }
          },
          onValuesChanged: (values, reason) =>
              widget.composer.setRecipients(values),
          anchor: const DComboboxChips<String>(
            input: DComboboxChipsInput<String>(
              key: ValueKey('composer-recipients-input'),
              placeholder: 'Add users or groups',
              autofocus: true,
            ),
          ),
          content: const DComboboxContent(
            semanticLabel: 'Recipients',
            sheetOnMobile: true,
            children: [
              DComboboxEmpty<String>(child: Text('No users or groups found.')),
              DComboboxList<String>(),
            ],
          ),
        ),
      ],
    ),
  );
}
