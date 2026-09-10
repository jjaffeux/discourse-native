import 'package:flutter/material.dart';

import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_dropdown_menu.dart';

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

/// An inbox switcher composed of a button and descriptive radio-menu choices.
///
/// [value] must match exactly one option. The caller owns selection, navigation,
/// and the available inboxes. A null [onChanged] disables the control. The
/// trigger truncates long names; its tooltip and semantics retain the full name.
/// Menu labels and descriptions wrap, and long lists scroll.
///
/// Dropdown Menu owns keyboard navigation, dismissal, and focus restoration.
/// Change this widget's key when its page or account changes to retire an open
/// menu that belongs to the previous owner.
class DMessageInboxMenu<T> extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final selected = options.singleWhere((option) => option.value == value);
    final label = '$semanticLabel: ${selected.label}';
    return DDropdownMenu(
      content: DDropdownMenuContent(
        semanticLabel: semanticLabel,
        width: 336,
        children: [
          DDropdownMenuRadioGroup<T>(
            value: value,
            onChanged: onChanged,
            children: [
              for (final option in options)
                DDropdownMenuRadioItem<T>(
                  value: option.value,
                  leading: option.icon,
                  closeOnSelect: true,
                  semanticLabel: '${option.label}. ${option.description}',
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(option.label),
                      Text(
                        option.description,
                        style: TextStyle(
                          color: DTokens.of(context).mutedForeground,
                          fontSize: DiscourseTypography.xs,
                          height: DiscourseTypography.lineHeightCaption,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      child: DDropdownMenuTrigger(
        builder: (context, state) => DButton(
          key: buttonKey,
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
          onPressed: onChanged == null ? null : state.toggle,
          focusNode: state.focusNode,
          hasPopup: true,
          expanded: state.open,
          variant: DButtonVariant.flat,
          size: size,
        ),
      ),
    );
  }
}
