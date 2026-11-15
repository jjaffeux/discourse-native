import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../models/found_user.dart';
import '../models/user_preferences.dart';
import 'account_writes.dart';
import 'avatar_image.dart';
import 'ignored_users_transactions.dart';
import 'preference_fields.dart';
import 'skeleton_fill.dart';
import 'user_lookup_controller.dart';

typedef PreferenceUserSearch = Future<List<FoundUser>> Function(String term);

/// What the Users tab needs to edit the muted list, whose draft lives with
/// the other preference sections and waits for its own save.
final class MutedUsersEditing {
  const MutedUsersEditing({
    required this.saving,
    required this.onChanged,
    required this.onSave,
  });

  final bool saving;
  final ValueChanged<List<String>> onChanged;

  /// Null while there is nothing to save or a write is already pending.
  final VoidCallback? onSave;
}

/// What the Users tab needs to start and stop ignoring a person, which the
/// site is told at once.
final class IgnoredUsersEditing {
  const IgnoredUsersEditing({
    required this.siteUrl,
    required this.transactions,
    required this.onIgnore,
    required this.onStopIgnoring,
  });

  final String siteUrl;
  final IgnoredUsersTransactions transactions;

  /// Answers whether the site took the ignore.
  final Future<bool> Function(String username, IgnoreDuration duration)
  onIgnore;
  final ValueChanged<String> onStopIgnoring;
}

/// The people this account has chosen not to hear from.
class PreferencesUsersSection extends StatefulWidget {
  const PreferencesUsersSection({
    super.key,
    required this.preferences,
    required this.enabled,
    required this.searchUsers,
    required this.muted,
    required this.ignored,
  });

  final UserPreferences preferences;
  final bool enabled;
  final PreferenceUserSearch searchUsers;
  final MutedUsersEditing muted;
  final IgnoredUsersEditing ignored;

  @override
  State<PreferencesUsersSection> createState() =>
      _PreferencesUsersSectionState();
}

class _PreferencesUsersSectionState extends State<PreferencesUsersSection> {
  late final UserLookupController _mutedLookup = UserLookupController(
    searchUsers: (term) => widget.searchUsers(term),
  );

  @override
  void dispose() {
    _mutedLookup.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preferences = widget.preferences;
    return PreferenceCard(
      children: [
        _MutedUsers(
          usernames: preferences.mutedUsernames,
          ownUsername: preferences.username,
          enabled: widget.enabled && preferences.canMuteUsers,
          allowed: preferences.canMuteUsers,
          lookup: _mutedLookup,
          editing: widget.muted,
        ),
        if (preferences.canIgnoreUsers) ...[
          const SizedBox(height: 18),
          _IgnoredUsers(
            usernames: preferences.ignoredUsernames,
            ownUsername: preferences.username,
            enabled: widget.enabled,
            searchUsers: widget.searchUsers,
            editing: widget.ignored,
          ),
        ],
      ],
    );
  }
}

class _IgnoredUsers extends StatefulWidget {
  const _IgnoredUsers({
    required this.usernames,
    required this.ownUsername,
    required this.enabled,
    required this.searchUsers,
    required this.editing,
  });

  final List<String> usernames;
  final String ownUsername;
  final bool enabled;
  final PreferenceUserSearch searchUsers;
  final IgnoredUsersEditing editing;

  @override
  State<_IgnoredUsers> createState() => _IgnoredUsersState();
}

class _IgnoredUsersState extends State<_IgnoredUsers> {
  late final UserLookupController _lookup = UserLookupController(
    searchUsers: (term) => widget.searchUsers(term),
  );
  String? _chosen;
  IgnoreDuration _duration = IgnoreDuration.oneMonth;

  /// Bumped when an ignore is accepted, so the picker starts empty again.
  int _pickerGeneration = 0;

  @override
  void dispose() {
    _lookup.dispose();
    super.dispose();
  }

  Future<void> _ignore() async {
    final username = _chosen;
    if (username == null) return;
    if (!await widget.editing.onIgnore(username, _duration) || !mounted) return;
    setState(() {
      _chosen = null;
      _pickerGeneration++;
    });
    _lookup.search('');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.editing.transactions, _lookup]),
    builder: (context, _) {
      final state = widget.editing.transactions.stateFor(
        widget.editing.siteUrl,
      );
      final ready = widget.enabled && !state.busy;
      final busyWith = switch (state) {
        AccountWriteBusy(:final subject) => subject,
        _ => null,
      };
      final chosen = _chosen;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DFieldTitle(child: Text(context.l10n.ignoredUsers)),
          DFieldDescription(child: Text(context.l10n.ignoredUsersDescription)),
          const SizedBox(height: 8),
          if (widget.usernames.isEmpty)
            DFieldDescription(
              key: const ValueKey('preferences-ignored-users-empty'),
              child: Text(context.l10n.youAreNotIgnoringAnyone),
            ),
          for (final username in widget.usernames)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              // A row would give the button its natural width, which at a
              // large text size leaves the name none.
              child: Wrap(
                key: ValueKey('preferences-ignored-user-$username'),
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text('@$username', overflow: TextOverflow.ellipsis),
                  DButton(
                    key: ValueKey('preferences-stop-ignoring-$username'),
                    label: Text(context.l10n.stopIgnoring),
                    semanticLabel: context.l10n.stopIgnoringUser(username),
                    onPressed: ready
                        ? () => widget.editing.onStopIgnoring(username)
                        : null,
                    loading:
                        busyWith != null && _sameUsername(busyWith, username),
                    loadingLabel: Text(context.l10n.saving),
                    variant: DButtonVariant.outline,
                    size: DButtonSize.small,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 250),
                child: KeyedSubtree(
                  key: const ValueKey('preferences-ignore-user'),
                  child: DCombobox<String>.controlled(
                    key: ValueKey(_pickerGeneration),
                    value: chosen,
                    options: _userOptions(
                      _lookup,
                      exclude: {widget.ownUsername, ...widget.usernames},
                      keyPrefix: 'ignore-user',
                    ),
                    equals: _sameUsername,
                    itemToStringLabel: (username) => username,
                    filterLocally: false,
                    enabled: ready,
                    onQueryChanged: (query, _) => _lookup.search(query),
                    onChanged: (username, _) =>
                        setState(() => _chosen = username),
                    anchor: DComboboxInput<String>(
                      placeholder: context.l10n.ignoreAUser,
                      semanticLabel: context.l10n.ignoreAUser,
                      showTrigger: false,
                    ),
                    content: _userResults(context, _lookup),
                  ),
                ),
              ),
              DSelect<IgnoreDuration>.controlled(
                key: const ValueKey('preferences-ignore-duration'),
                value: _duration,
                initialValue: _duration,
                size: DControlSize.preference,
                semanticLabel: context.l10n.ignoreFor,
                enabled: ready,
                entries: [
                  for (final duration in IgnoreDuration.values)
                    DSelectOption(
                      value: duration,
                      label: _durationLabel(context, duration),
                      child: Text(_durationLabel(context, duration)),
                    ),
                ],
                onChanged: (duration) {
                  if (duration != null) setState(() => _duration = duration);
                },
              ),
              DButton(
                key: const ValueKey('preferences-ignore-submit'),
                label: Text(context.l10n.ignoreUser),
                onPressed: ready && chosen != null ? _ignore : null,
                loading:
                    busyWith != null &&
                    chosen != null &&
                    _sameUsername(busyWith, chosen),
                loadingLabel: Text(context.l10n.saving),
                variant: DButtonVariant.primary,
                size: DButtonSize.small,
              ),
            ],
          ),
          if (state case AccountWriteFailed(:final message)) ...[
            const SizedBox(height: 8),
            DFieldError(
              key: const ValueKey('preferences-ignored-users-error'),
              errors: [message],
            ),
          ],
        ],
      );
    },
  );
}

String _durationLabel(BuildContext context, IgnoreDuration duration) =>
    switch (duration) {
      IgnoreDuration.oneDay => context.l10n.forOneDay,
      IgnoreDuration.oneWeek => context.l10n.forOneWeek,
      IgnoreDuration.twoWeeks => context.l10n.forTwoWeeks,
      IgnoreDuration.oneMonth => context.l10n.ignoreForOneMonth,
      IgnoreDuration.threeMonths => context.l10n.ignoreForThreeMonths,
      IgnoreDuration.sixMonths => context.l10n.ignoreForSixMonths,
      IgnoreDuration.oneYear => context.l10n.ignoreForOneYear,
      IgnoreDuration.forever => context.l10n.forever,
    };

class _MutedUsers extends StatelessWidget {
  const _MutedUsers({
    required this.usernames,
    required this.ownUsername,
    required this.enabled,
    required this.allowed,
    required this.lookup,
    required this.editing,
  });

  final List<String> usernames;
  final String ownUsername;
  final bool enabled;
  final bool allowed;
  final UserLookupController lookup;
  final MutedUsersEditing editing;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DField(
        enabled: enabled,
        children: [
          DFieldContent(
            children: [
              DFieldLabel(child: Text(context.l10n.mutedUsers)),
              DFieldDescription(
                child: Text(
                  allowed
                      ? context.l10n.mutedUsersDescription
                      : context.l10n.thisSiteDoesNotLetThisAccountMuteYet,
                ),
              ),
            ],
          ),
          if (allowed)
            DFieldControl(
              label: context.l10n.mutedUsers,
              child: ListenableBuilder(
                listenable: lookup,
                builder: (context, _) => DCombobox<String>.multipleControlled(
                  key: const ValueKey('preferences-muted-users'),
                  value: usernames,
                  query: lookup.query,
                  options: _userOptions(
                    lookup,
                    exclude: {ownUsername},
                    keyPrefix: 'mute-user',
                  ),
                  equals: _sameUsername,
                  itemToStringLabel: (username) => username,
                  filterLocally: false,
                  closeOnSelect: false,
                  enabled: enabled,
                  onQueryChanged: (query, _) => lookup.search(query),
                  onValuesChanged: (values, _) => editing.onChanged(values),
                  anchor: DComboboxChips<String>(
                    input: DComboboxChipsInput<String>(
                      key: const ValueKey('preferences-muted-users-search'),
                      placeholder: context.l10n.addAUser,
                    ),
                  ),
                  content: _userResults(context, lookup),
                ),
              ),
            ),
        ],
      ),
      if (allowed) ...[
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: DButton(
            key: const ValueKey('preferences-muted-users-save'),
            label: Text(context.l10n.save),
            semanticLabel: context.l10n.saveMutedUsers,
            onPressed: enabled ? editing.onSave : null,
            loading: editing.saving,
            loadingLabel: Text(context.l10n.saving),
            variant: DButtonVariant.primary,
            size: DButtonSize.small,
          ),
        ),
      ],
    ],
  );
}

/// Discourse usernames are unique without regard to case.
bool _sameUsername(String left, String right) =>
    left.toLowerCase() == right.toLowerCase();

List<DComboboxOption<String>> _userOptions(
  UserLookupController lookup, {
  required Set<String> exclude,
  required String keyPrefix,
}) => [
  for (final user in lookup.results)
    if (!exclude.any((username) => _sameUsername(username, user.username)))
      DComboboxOption(
        value: user.username,
        label: user.username,
        searchText: '${user.name ?? ''} ${user.username}',
        itemKey: ValueKey('$keyPrefix-${user.username}'),
      ),
];

DComboboxContent _userResults(
  BuildContext context,
  UserLookupController lookup,
) => DComboboxContent(
  semanticLabel: context.l10n.matchingUsers,
  children: [
    DComboboxEmpty<String>(
      child: lookup.searching
          ? DSkeletonRegion(
              semanticsLabel: context.l10n.searching,
              color: skeletonFill(context, on: SkeletonSurface.floating),
              child: Column(
                children: [
                  for (var index = 0; index < 3; index++)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: DSpacing.sm),
                      child: Row(
                        spacing: DSpacing.sm,
                        children: [
                          DSkeleton.circle(diameter: 28),
                          Expanded(child: DSkeleton(height: 16)),
                        ],
                      ),
                    ),
                ],
              ),
            )
          : Text(
              lookup.queryIsTooShort
                  ? context.l10n.typeAtLeastTwoCharacters
                  : context.l10n.noMatchingUsers,
            ),
    ),
    DComboboxList<String>(
      itemBuilder: (context, option) {
        final user = lookup.results
            .where((user) => user.username == option.value)
            .firstOrNull;
        final name = user?.name;
        return Row(
          children: [
            DAvatar.frame(
              child: AvatarImage(
                url: user?.avatarUrl,
                size: 28,
                fallback: DAvatarFallback(
                  child: Text(
                    option.value.characters.firstOrNull?.toUpperCase() ?? '?',
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name == null || name.isEmpty ? option.value : name),
                  Text(
                    '@${option.value}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  ],
);
