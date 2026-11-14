import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../../foundation/count_label.dart';
import '../../foundation/icons/d_icons.dart';
import '../avatar_image.dart';
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
      groups: _shell.groups.api,
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
    final reach = mobile
        ? lookup.reach(_shell.currentUserFor(lookup.siteUrl)?.username)
        : null;
    final recipientSummary = countLabel(
      reach ?? recipients.length,
      CountNoun.recipient,
    );
    final users = {
      for (final user in lookup.results.users) user.username: user,
    };
    final groups = [
      for (final group in lookup.results.groups)
        if (!mobile || !recipients.contains(group.name))
          DComboboxOption(
            value: group.name,
            label: group.name,
            icon: mobile ? const DIcon(DIcons.userGroup) : null,
            detail: switch (lookup.groupMemberCount(group.name)) {
              final count? when mobile => countLabel(count, CountNoun.member),
              _ => null,
            },
            itemKey: ValueKey(('recipient-group', group.name)),
          ),
    ];
    final results = [
      DComboboxEmpty<String>(child: Text(context.l10n.noUsersOrGroupsFound)),
      DComboboxList<String>(
        itemBuilder: mobile
            ? (context, option) {
                final user = users[option.value];
                if (user == null) return Text(option.label);
                const avatarSize = 22.0;
                return Row(
                  spacing: DSpacing.sm,
                  children: [
                    DAvatar(
                      dimension: avatarSize,
                      decorative: true,
                      child: AvatarImage(
                        url: user.avatarUrl,
                        size: avatarSize,
                        fallback: DAvatarFallback(
                          child: Text(
                            user.username.characters.firstOrNull
                                    ?.toUpperCase() ??
                                '?',
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: user.username,
                          children: [
                            if (user.name case final name?)
                              TextSpan(
                                text: ' · $name',
                                style: TextStyle(
                                  color: DTokens.of(context).mutedForeground,
                                ),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                );
              }
            : null,
      ),
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
                    ? recipientSummary
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
