import 'package:flutter/material.dart';

import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_combobox.dart';

/// One inbox's value, name, explanation, and personal or group artwork.
@immutable
class DMessageInboxOption<T> {
  const DMessageInboxOption({
    required this.value,
    required this.label,
    required this.description,
    required this.icon,
  });

  final T value;
  final String label;
  final String description;

  /// Inherits the trigger or menu row's icon size and color.
  final Widget icon;
}

/// An inbox switcher with a button and searchable, descriptive choices.
///
/// [value] must match exactly one option. The caller owns selection, navigation,
/// and the available inboxes. A null [onChanged] disables the control. The
/// trigger truncates long names; its tooltip and semantics retain the full name.
/// Menu labels and descriptions wrap, and long lists scroll. Each opening starts
/// with an empty search. Filtering matches inbox names without changing selection.
///
/// Combobox owns keyboard navigation, dismissal, and focus restoration.
/// Change this widget's key when its page or account changes to retire an open
/// menu that belongs to the previous owner.
class DMessageInboxMenu<T> extends StatefulWidget {
  const DMessageInboxMenu({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.semanticLabel = 'Choose inbox',
    this.size = DButtonSize.small,
    this.buttonKey,
  }) : assert(options.length > 0);

  final T value;
  final List<DMessageInboxOption<T>> options;
  final ValueChanged<T>? onChanged;
  final String semanticLabel;
  final DButtonSize size;
  final Key? buttonKey;

  @override
  State<DMessageInboxMenu<T>> createState() => _DMessageInboxMenuState<T>();
}

class _DMessageInboxMenuState<T> extends State<DMessageInboxMenu<T>> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.options.singleWhere(
      (option) => option.value == widget.value,
    );
    final label = '${widget.semanticLabel}: ${selected.label}';
    final tokens = DTokens.of(context);
    return DCombobox<DMessageInboxOption<T>>.controlled(
      value: selected,
      equals: (left, right) => left.value == right.value,
      options: [
        for (final option in widget.options)
          DComboboxOption(value: option, label: option.label),
      ],
      enabled: widget.onChanged != null,
      autoHighlight: true,
      textController: _search,
      onOpenChanged: (open, _) {
        if (open) _search.clear();
      },
      onChanged: (option, _) {
        if (option != null) widget.onChanged?.call(option.value);
      },
      content: DComboboxContent(
        semanticLabel: widget.semanticLabel,
        width: 336,
        children: [
          Padding(
            padding: const EdgeInsets.all(4),
            child: DComboboxInput<DMessageInboxOption<T>>(
              placeholder: 'Search inboxes…',
              semanticLabel: 'Search inboxes',
              registerAsAnchor: false,
              showTrigger: false,
            ),
          ),
          DComboboxEmpty<DMessageInboxOption<T>>(
            child: const Text('No inboxes found.'),
          ),
          DComboboxList<DMessageInboxOption<T>>(
            itemBuilder: (context, item) => Semantics(
              label: item.value.description,
              excludeSemantics: true,
              child: Row(
                children: [
                  IconTheme.merge(
                    data: IconThemeData(size: 16, color: tokens.foreground),
                    child: item.value.icon,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label,
                          style: const TextStyle(
                            fontSize: DiscourseTypography.sm,
                            height: 20 / DiscourseTypography.sm,
                          ),
                        ),
                        Text(
                          item.value.description,
                          style: TextStyle(
                            color: tokens.mutedForeground,
                            fontSize: DiscourseTypography.xs,
                            height: DiscourseTypography.lineHeightCaption,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      anchor: DComboboxTrigger<DMessageInboxOption<T>>(
        builder: (context, state) => DButton(
          key: widget.buttonKey,
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  selected.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              const DIcon(DIcons.chevronDown, size: 10),
            ],
          ),
          icon: selected.icon,
          tooltip: label,
          semanticLabel: label,
          onPressed: widget.onChanged == null ? null : state.toggle,
          focusNode: state.focusNode,
          hasPopup: true,
          expanded: state.open,
          variant: DButtonVariant.ghost,
          size: widget.size,
        ),
      ),
    );
  }
}
