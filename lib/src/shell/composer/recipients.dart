import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../../foundation/icons/d_icons.dart';
import '../platform.dart';
import '../shell_controller.dart';
import '../shell_scope.dart';
import '../topic_taxonomy_button.dart';
import 'controller.dart';
import 'recipient_lookup.dart';

class ComposerRecipients extends StatefulWidget {
  const ComposerRecipients({super.key, required this.composer});

  final ComposerController composer;

  @override
  State<ComposerRecipients> createState() => _ComposerRecipientsState();
}

class _ComposerRecipientsState extends State<ComposerRecipients> {
  late ShellController _shell;
  ComposerRecipientLookup? _lookup;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _shell = ShellScope.identityOf(context);
    _bindLookup();
  }

  @override
  void didUpdateWidget(ComposerRecipients oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bindLookup();
  }

  void _bindLookup() {
    final search = _shell.composerIdentities.messageRecipientSearch(
      widget.composer.target.siteUrl,
    );
    if (_lookup?.matches(widget.composer, search) ?? false) return;
    _lookup?.removeListener(_lookupChanged);
    _lookup?.dispose();
    _lookup = ComposerRecipientLookup(composer: widget.composer, search: search)
      ..addListener(_lookupChanged);
  }

  void _lookupChanged() => setState(() {});

  @override
  void dispose() {
    _lookup?.removeListener(_lookupChanged);
    _lookup?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _bindLookup();
    final lookup = _lookup!;
    final mobile = context.isTouch;
    final recipients = lookup.recipients;
    final groups = [
      for (final group in lookup.results.groups)
        if (!mobile || !recipients.contains(group.name))
          DComboboxOption(
            value: group.name,
            label: group.name,
            itemKey: ValueKey(('recipient-group', group.name)),
          ),
    ];
    final results = [
      DComboboxEmpty<String>(child: Text(context.l10n.noUsersOrGroupsFound)),
      const DComboboxList<String>(),
    ];
    final picker = DCombobox<String>.multipleControlled(
      key: const ValueKey('composer-private-message-recipients'),
      value: recipients,
      enabled: widget.composer.isEditing,
      options: const [],
      groups: [
        DComboboxOptionGroup(
          label: mobile ? null : context.l10n.users,
          options: [
            for (final user in lookup.results.users)
              if (!mobile || !recipients.contains(user.username))
                DComboboxOption(
                  value: user.username,
                  label: user.name == null
                      ? user.username
                      : '${user.username} · ${user.name}',
                ),
          ],
        ),
        if (mobile)
          DComboboxOptionGroup.sheetFooter(options: groups)
        else
          DComboboxOptionGroup(label: context.l10n.groups, options: groups),
      ],
      query: lookup.query,
      filterLocally: false,
      closeOnSelect: false,
      itemToStringLabel: (name) => name,
      onQueryChanged: (query, reason) => lookup.search(
        query,
        selectionReset:
            reason == DComboboxChangeReason.keyboard ||
            reason == DComboboxChangeReason.itemPress,
      ),
      onOpenChanged: (open, reason) => lookup.setOpen(open, mobile: mobile),
      onValuesChanged: (values, reason) => lookup.select(values),
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
      content: mobile
          ? DComboboxContent.adaptiveSheet(
              semanticLabel: context.l10n.recipients,
              children: [
                const Padding(
                  padding: DInsets.menu,
                  child: _RecipientSearchField(),
                ),
                ...results,
              ],
            )
          : DComboboxContent(
              semanticLabel: context.l10n.recipients,
              children: results,
            ),
    );
    return KeyedSubtree(
      key: ObjectKey(lookup),
      child: Padding(
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
      ),
    );
  }
}

class _RecipientSearchField extends StatelessWidget {
  const _RecipientSearchField();

  @override
  Widget build(BuildContext context) => DPopoverClose(
    builder: (context, close) => DComboboxInput<String>(
      key: const ValueKey('composer-recipients-input'),
      placeholder: context.l10n.searchUsersOrGroups,
      semanticLabel: context.l10n.searchRecipients,
      registerAsAnchor: false,
      autofocus: true,
      showTrigger: false,
      addons: [
        DInputGroupAddon(
          alignment: DInputGroupAddonAlignment.inlineEnd,
          child: DInputGroupButton.icon(
            tooltip: context.l10n.close,
            icon: const DIcon(DIcons.xmark),
            onPressed: close,
          ),
        ),
      ],
    ),
  );
}
