import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../foundation/count_label.dart';
import '../foundation/icons/d_icons.dart';
import '../theme/discourse_typography.dart';
import 'avatar_image.dart';
import 'platform.dart';
import 'sheet_search.dart';
import 'shell_sheet.dart';

/// Someone a thing can be given to: a person by username, or a group by
/// name. Two picks are the same one when their kind and name match, whatever
/// else a lookup said about them.
@immutable
final class PersonPick {
  const PersonPick.user(this.name, {this.fullName, this.avatarUrl})
    : isGroup = false,
      memberCount = null;

  const PersonPick.group(this.name, {this.fullName, this.memberCount})
    : isGroup = true,
      avatarUrl = null;

  /// The username, or the group's name.
  final String name;
  final String? fullName;
  final String? avatarUrl;
  final bool isGroup;
  final int? memberCount;

  @override
  bool operator ==(Object other) =>
      other is PersonPick &&
      other.isGroup == isGroup &&
      other.name.toLowerCase() == name.toLowerCase();

  @override
  int get hashCode => Object.hash(isGroup, name.toLowerCase());
}

/// Who matches [term]; an empty term asks for who to suggest before anything
/// is typed, which may be no one.
typedef PersonPickSearch = Future<List<PersonPick>> Function(String term);

/// Who something is given to, picked as who a message goes to is: people
/// and, unless only a person will do, groups. The one pressed is the choice,
/// with nothing more to confirm, and the sheet closes on it; [chosen], whom
/// it is already with, is shown as chosen.
///
/// On a phone the sheet opens on its field, whose placeholder is [ask]; on a
/// desktop [note] stands above the field, whose placeholder names what can be
/// searched for. [title] names the sheet either way.
Future<PersonPick?> showPersonPicker({
  required BuildContext context,
  required String title,
  required String ask,
  required PersonPickSearch search,
  String? note,
  bool groups = true,
  PersonPick? chosen,
  Duration debounce = const Duration(milliseconds: 300),
}) => showShellSheet<PersonPick>(
  context: context,
  title: title,
  search: true,
  dialogOnDesktop: true,
  scrollBody: false,
  builder: (context) => PersonPicker(
    hintText: context.isTouch
        ? ask
        : groups
        ? context.l10n.searchUsersOrGroups
        : context.l10n.searchUsers,
    note: context.isTouch ? null : note,
    groups: groups,
    chosen: chosen,
    search: search,
    debounce: debounce,
    onPick: (pick) => DDialogClose.close<PersonPick>(context, pick),
  ),
);

/// The body of [showPersonPicker]: its field, and who it finds under it.
class PersonPicker extends StatefulWidget {
  const PersonPicker({
    super.key,
    required this.hintText,
    required this.search,
    required this.onPick,
    this.note,
    this.groups = true,
    this.chosen,
    this.debounce = const Duration(milliseconds: 300),
  });

  final String hintText;
  final PersonPickSearch search;
  final ValueChanged<PersonPick> onPick;
  final String? note;
  final bool groups;
  final PersonPick? chosen;
  final Duration debounce;

  @override
  State<PersonPicker> createState() => _PersonPickerState();
}

class _PersonPickerState extends State<PersonPicker> {
  final _query = TextEditingController();
  final _field = FocusNode();
  Timer? _timer;

  /// Only the newest lookup may answer; one overtaken by typing is dropped.
  int _generation = 0;
  List<PersonPick> _found = const [];
  bool _looking = true;
  bool _failed = false;
  bool _picked = false;

  @override
  void initState() {
    super.initState();
    unawaited(_look(++_generation, ''));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _query.dispose();
    _field.dispose();
    super.dispose();
  }

  void _changed(String text) {
    _timer?.cancel();
    final generation = ++_generation;
    setState(() => _looking = true);
    final term = text.trim();
    if (term.isEmpty || widget.debounce == Duration.zero) {
      unawaited(_look(generation, term));
      return;
    }
    _timer = Timer(widget.debounce, () => unawaited(_look(generation, term)));
  }

  Future<void> _look(int generation, String term) async {
    List<PersonPick> found;
    var failed = false;
    try {
      found = await widget.search(term);
    } catch (_) {
      found = const [];
      failed = true;
    }
    if (!mounted || generation != _generation) return;
    final chosen = widget.chosen;
    setState(() {
      _looking = false;
      _failed = failed;
      _found = [
        if (term.isEmpty && chosen != null && !found.contains(chosen)) chosen,
        for (final pick in found)
          if (widget.groups || !pick.isGroup) pick,
      ];
    });
  }

  void _pick(PersonPick pick) {
    if (_picked) return;
    _picked = true;
    widget.onPick(pick);
  }

  @override
  Widget build(BuildContext context) {
    final touch = context.isTouch;
    final people = [
      for (final pick in _found)
        if (!pick.isGroup) pick,
    ];
    final groups = [
      for (final pick in _found)
        if (pick.isGroup) pick,
    ];
    final term = _query.text.trim();
    final tokens = DTokens.of(context);
    final quiet = TextStyle(
      fontSize: DiscourseTypography.preview,
      color: tokens.mutedForeground,
    );
    final groupLine = groups.isEmpty
        ? null
        : DScrollArea(
            key: const ValueKey('person-picker-groups'),
            axes: DScrollAxes.horizontal,
            showScrollbar: false,
            child: Row(
              spacing: DSpacing.controlGap,
              children: [
                for (final group in groups)
                  _GroupChip(
                    group: group,
                    chosen: group == widget.chosen,
                    onPressed: () => _pick(group),
                  ),
              ],
            ),
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.note case final note?)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(note, style: quiet),
          ),
        SheetSearch(
          focusNode: _field,
          inputKey: const ValueKey('person-picker-search'),
          controller: _query,
          hintText: widget.hintText,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _changed,
          onSubmitted: (_) {
            final best = _found.firstOrNull;
            if (term.isNotEmpty && best != null) _pick(best);
          },
        ),
        Flexible(
          child: SheetSearchHold(
            focusNode: _field,
            child: ListView(
              key: const ValueKey('person-picker-results'),
              shrinkWrap: true,
              padding: const EdgeInsets.only(top: 6),
              children: [
                if (!touch && groupLine != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: groupLine,
                  ),
                for (final person in people)
                  _PersonRow(
                    person: person,
                    chosen: person == widget.chosen,
                    onPressed: () => _pick(person),
                  ),
                if (_failed)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 8,
                    ),
                    child: Text(
                      context.l10n.couldnTReachTheSite,
                      key: const ValueKey('person-picker-failed'),
                      style: quiet,
                    ),
                  )
                else if (!_looking && _found.isEmpty && term.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 8,
                    ),
                    child: Text(
                      context.l10n.nothingMatchesTerm(term),
                      key: const ValueKey('person-picker-empty'),
                      style: quiet,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (touch && groupLine != null)
          SheetSearchHold(
            focusNode: _field,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: groupLine,
            ),
          ),
      ],
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.person,
    required this.chosen,
    required this.onPressed,
  });

  final PersonPick person;
  final bool chosen;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final fullName = person.fullName;
    final named = fullName != null && fullName.isNotEmpty;
    return DItem(
      key: ValueKey('person-picker-user-${person.name}'),
      size: DItemSize.sm,
      shape: DItemShape.menu,
      selected: chosen,
      selectionStyle: DItemSelectionStyle.strongNeutral,
      onPressed: onPressed,
      semanticLabel: named ? '${person.name}, $fullName' : person.name,
      children: [
        DItemMedia(
          variant: DItemMediaVariant.avatar,
          child: PersonFace(person: person, size: 22),
        ),
        DItemContent(
          children: [
            DItemTitle(
              child: ExcludeSemantics(
                child: Text.rich(
                  TextSpan(
                    text: person.name,
                    children: [
                      if (named)
                        TextSpan(
                          text: ' · $fullName',
                          style: TextStyle(color: tokens.mutedForeground),
                        ),
                    ],
                  ),
                  style: TextStyle(
                    fontSize: DiscourseTypography.control,
                    color: tokens.foreground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GroupChip extends StatelessWidget {
  const _GroupChip({
    required this.group,
    required this.chosen,
    required this.onPressed,
  });

  final PersonPick group;
  final bool chosen;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final count = group.memberCount;
    return DButton(
      key: ValueKey('person-picker-group-${group.name}'),
      icon: DIcon(chosen ? DIcons.check : DIcons.userGroup),
      semanticLabel: count == null
          ? group.name
          : '${group.name}, ${countLabel(count, CountNoun.member)}',
      label: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: DSpacing.sm,
        children: [
          Text(group.name),
          if (count != null)
            Text(
              '$count',
              style: TextStyle(
                color: DTokens.of(context).mutedForeground,
                fontSize: DiscourseTypography.metadata,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
      shape: DButtonShape.pill,
      size: DButtonSize.filter,
      variant: chosen ? DButtonVariant.quietSelected : DButtonVariant.quiet,
      onPressed: onPressed,
    );
  }
}

/// Someone's face, or a group's mark where a group stands in for people.
class PersonFace extends StatelessWidget {
  const PersonFace({super.key, required this.person, required this.size});

  final PersonPick person;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (person.isGroup) return GroupFace(size: size);
    return DAvatar(
      dimension: size,
      decorative: true,
      child: AvatarImage(
        url: person.avatarUrl,
        size: size,
        fallback: DAvatarFallback(
          child: Text(person.name.characters.firstOrNull?.toUpperCase() ?? '?'),
        ),
      ),
    );
  }
}

/// A group's mark in a face's place: the group icon at half the size on the
/// raised surface, in the muted colour.
class GroupFace extends StatelessWidget {
  const GroupFace({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return DAvatar(
      dimension: size,
      decorative: true,
      border: false,
      child: ColoredBox(
        color: tokens.raisedBackground,
        child: Center(
          child: DIcon(
            DIcons.userGroup,
            size: size * .5,
            color: tokens.mutedForeground,
          ),
        ),
      ),
    );
  }
}
