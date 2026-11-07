import 'package:discourse_native/discourse_plugin_sdk.dart' show DIcons;
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The shared quiet field for narrowing chat lists in place.
class ChatFindField extends StatelessWidget {
  const ChatFindField({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.placeholder,
    this.focusNode,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String placeholder;
  final FocusNode? focusNode;

  void _clear() {
    controller.clear();
    onChanged('');
    focusNode?.requestFocus();
  }

  @override
  Widget build(BuildContext context) => DReferenceTextScale(
    child: Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _clear();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => DInputGroup(
          variant: DInputGroupVariant.quiet,
          size: DControlSize.filter,
          children: [
            DInputGroupInput(
              controller: controller,
              focusNode: focusNode,
              semanticLabel: placeholder,
              hintText: placeholder,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: onChanged,
            ),
            const DInputGroupAddon(child: DIcon(DIcons.magnifyingGlass)),
            if (controller.text.isNotEmpty)
              DInputGroupAddon(
                alignment: DInputGroupAddonAlignment.inlineEnd,
                child: DInputGroupButton.icon(
                  icon: const DIcon(DIcons.xmark),
                  tooltip: context.l10n.clearSearch,
                  onPressed: _clear,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
