import 'dart:async';

import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'gamification_controller.dart';
import 'gamification_models.dart';

class GamificationCategories extends StatefulWidget {
  const GamificationCategories({
    super.key,
    required this.handle,
    required this.value,
    required this.onChanged,
    this.single = false,
    this.enabled = true,
  });
  final GamificationAdminHandle handle;
  final Set<int> value;
  final ValueChanged<Set<int>> onChanged;
  final bool single, enabled;
  @override
  State<GamificationCategories> createState() => _GamificationCategoriesState();
}

class _GamificationCategoriesState extends State<GamificationCategories> {
  final _names = <int, String>{};
  List<({int id, String name})> _matches = const [];
  Timer? _timer;
  int _generation = 0;
  Object? _error;
  @override
  void initState() {
    super.initState();
    unawaited(_search(''));
  }

  Future<void> _search(String term) async {
    final h = widget.handle, generation = ++_generation;
    final lease = h.owner.requests.capture(h.site),
        revision = h.owner.revision(h.site);
    bool current() =>
        mounted &&
        generation == _generation &&
        h.owner.current(h.site, lease, revision, admin: true);
    try {
      final auth = await h.owner.requests.credentialsFor(h.site);
      if (!current()) return;
      final found = await auth.run(
        () => h.owner.api.searchCategories(h.site, auth, term),
      );
      if (!current()) return;
      setState(() {
        _matches = found;
        _error = null;
        for (final c in found) {
          _names[c.id] = c.name;
        }
      });
    } catch (error) {
      if (current()) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ids = {...widget.value, ..._matches.map((c) => c.id)};
    final options = [
      for (final id in ids)
        DComboboxOption<int>(
          value: id,
          label:
              _names[id] ??
              widget.handle.owner.siteState.categoryFor
                  ?.call(widget.handle.site, id)
                  ?.name ??
              '$id',
        ),
    ];
    final content = DComboboxContent(
      children: [
        if (_error != null) Text(gameError(_error!)),
        DComboboxEmpty<int>(child: Text(context.l10n.noMatchingCategories)),
        const DComboboxList<int>(),
      ],
    );
    void search(String query, DComboboxChangeReason _) {
      _timer?.cancel();
      _timer = Timer(
        const Duration(milliseconds: 250),
        () => unawaited(_search(query)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DSpacing.sm,
      children: [
        Text(
          widget.single
              ? context.l10n.gamificationCategory
              : context.l10n.gamificationCategories,
        ),
        if (widget.single)
          DCombobox<int>.controlled(
            value: widget.value.firstOrNull,
            options: options,
            enabled: widget.enabled,
            filterLocally: false,
            anchor: DComboboxInput<int>(
              placeholder: context.l10n.gamificationCategory,
            ),
            content: content,
            onQueryChanged: search,
            onChanged: (value, _) =>
                widget.onChanged(value == null ? {} : {value}),
          )
        else
          DCombobox<int>.multipleControlled(
            value: widget.value.toList(),
            options: options,
            enabled: widget.enabled,
            filterLocally: false,
            anchor: DComboboxChips<int>(
              input: DComboboxChipsInput<int>(
                placeholder: context.l10n.gamificationCategories,
              ),
            ),
            content: content,
            onQueryChanged: search,
            onValuesChanged: (values, _) => widget.onChanged(values.toSet()),
          ),
        if (widget.single && widget.value.isNotEmpty)
          DButton(
            label: Text(context.l10n.gamificationClearCategory),
            onPressed: widget.enabled ? () => widget.onChanged({}) : null,
          ),
        if (!widget.single) Text(context.l10n.gamificationCategoryHint),
      ],
    );
  }
}

Widget gameNotice(String message) =>
    DAlert(description: DAlertDescription(child: Text(message)));

String gameError(Object error) => switch (error) {
  GamificationAmbiguousWrite() => appL10n.gamificationUnknownWrite,
  GamificationUnsupportedResponse() ||
  FormatException() ||
  TypeError() => appL10n.gamificationUnsupported,
  WriteException(:final message) ||
  SiteLookupException(:final message) => message,
  _ => appL10n.gamificationRequestFailed,
};
