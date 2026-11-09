import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;

/// Projects the marker through the Native checkbox without another text field.
class ComposerTodoMarker extends StatelessWidget {
  const ComposerTodoMarker({
    super.key,
    required this.checked,
    required this.label,
    required this.onChanged,
    required this.style,
  });

  final bool checked;
  final String label;
  final VoidCallback? onChanged;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => FocusScope(
    // Inline controls must not make EditableText think it still owns focus.
    // Otherwise tapping the text leaves Space routed to the last checkbox.
    parentNode: FocusScope.of(context),
    child: TextFieldTapRegion(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DCheckbox(
            inline: true,
            size: DControlStyle.isTouch(context)
                ? DCheckboxSize.large
                : DCheckboxSize.standard,
            value: checked,
            semanticLabel: label.isEmpty ? context.l10n.toDo : label,
            readOnly: onChanged == null,
            onChanged: (_) => onChanged?.call(),
          ),
          if (label.isEmpty)
            SizedBox(
              width: 0,
              child: OverflowBox(
                fit: OverflowBoxFit.deferToChild,
                alignment: AlignmentDirectional.centerStart,
                minWidth: 0,
                maxWidth: double.infinity,
                child: IgnorePointer(
                  child: Text(
                    context.l10n.toDo,
                    maxLines: 1,
                    style: style.copyWith(
                      color: DTokens.of(context).mutedForeground,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
