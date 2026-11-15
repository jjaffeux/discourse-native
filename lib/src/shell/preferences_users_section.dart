import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../models/found_user.dart';
import '../models/user_preferences.dart';
import 'avatar_image.dart';
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

/// The people this account has chosen not to hear from.
class PreferencesUsersSection extends StatefulWidget {
  const PreferencesUsersSection({
    super.key,
    required this.preferences,
    required this.enabled,
    required this.searchUsers,
    required this.muted,
  });

  final UserPreferences preferences;
  final bool enabled;
  final PreferenceUserSearch searchUsers;
  final MutedUsersEditing muted;

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
      ],
    );
  }
}

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
