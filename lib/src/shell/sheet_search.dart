import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundation/icons/d_icons.dart';
import '../theme/discourse_typography.dart';
import 'platform.dart';

/// The field every sheet that looks something up has. On a phone, a filled
/// capsule led by a magnifier, a press anywhere in it typing in it; on a
/// desktop, the hairline line its sheet has. [trailing] stands at the field's
/// end, as a picker's own control.
///
/// Wrap what the sheet lists under it in [SheetSearchHold] with the same
/// [focusNode], so a press there leaves a phone's keyboard up. A sheet that
/// opens on its field passes `search: true` to `showShellSheet`.
class SheetSearch extends StatelessWidget {
  const SheetSearch({
    super.key,
    required this.focusNode,
    required this.hintText,
    this.inputKey,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.enabled = true,
    this.inputFormatters,
    this.textInputAction,
    this.trailing,
  });

  final FocusNode focusNode;

  /// What the field is for, shown in it while empty and read out as its name.
  final String hintText;
  final Key? inputKey;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final bool enabled;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final Widget? trailing;

  DInput _input({TextStyle? style, bool borderless = false, Widget? suffix}) =>
      DInput(
        key: inputKey,
        controller: controller,
        focusNode: focusNode,
        semanticLabel: hintText,
        hintText: hintText,
        autofocus: autofocus,
        enabled: enabled,
        autocorrect: false,
        enableSuggestions: false,
        inputFormatters: inputFormatters,
        textInputAction: textInputAction,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        borderless: borderless,
        style: style,
        suffix: suffix,
      );

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    if (context.isTouch) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: DReferenceTextScale(
          child: DInputGroup(
            size: DControlSize.floating,
            variant: DInputGroupVariant.quiet,
            enabled: enabled,
            children: [
              _input(),
              DInputGroupAddon(
                child: DIcon(
                  DIcons.magnifyingGlass,
                  size: 16,
                  color: tokens.mutedForeground,
                ),
              ),
              if (trailing case final trailing?)
                DInputGroupAddon(
                  alignment: DInputGroupAddonAlignment.inlineEnd,
                  child: trailing,
                ),
            ],
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: _input(
          borderless: true,
          style: const TextStyle(
            fontSize: DiscourseTypography.sheetSearch,
            height: 1.4,
          ),
          suffix: trailing,
        ),
      ),
    );
  }
}

/// What a sheet lists under its [SheetSearch]: on a phone, a press in it
/// leaves the field focused, so the keyboard stays up rather than going down
/// and straight back up as the sheet puts the focus back. Keyboard traversal
/// on a desktop is untouched.
class SheetSearchHold extends StatelessWidget {
  const SheetSearchHold({
    super.key,
    required this.focusNode,
    required this.child,
  });

  final FocusNode focusNode;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!context.isTouch) return child;
    return ListenableBuilder(
      listenable: focusNode,
      child: child,
      builder: (context, child) =>
          ExcludeFocus(excluding: focusNode.hasFocus, child: child!),
    );
  }
}
