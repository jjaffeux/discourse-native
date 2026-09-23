import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../theme/d_icons.dart';
import 'composer_controller.dart';
import 'composer_inline_formatting.dart';
import 'composer_marks.dart';
import 'composer_selection_colors.dart';
import 'shell_scope.dart';

/// Selection actions composed from Native menus and formatting toggles.
class ComposerSelectionMenu extends StatelessWidget {
  const ComposerSelectionMenu({
    super.key,
    required this.composer,
    required this.onFocusChange,
    required this.onDismiss,
    required this.onLink,
  });

  final ComposerController composer;
  final ValueChanged<bool> onFocusChange;
  final VoidCallback onDismiss;
  final VoidCallback onLink;

  void _format(TextEditingValue Function(TextEditingValue) format) {
    composer.formatSelection(format);
    composer.focus.requestFocus();
  }

  Widget _toggle(String label, Widget icon, String kind, VoidCallback action) =>
      DTooltip(
        message: label,
        excludeFromSemantics: true,
        child: DToggle.iconOnly(
          semanticLabel: label,
          icon: icon,
          pressed: composerSelectionHasFormat(composer.value, kind),
          enabled: composer.isEditing,
          onPressedChanged: (_) {
            action();
            composer.focus.requestFocus();
          },
        ),
      );

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: onFocusChange,
    child: TextFieldTapRegion(
      child: ListenableBuilder(
        listenable: composer.text,
        builder: (context, _) => DDropdownMenu(
          open: true,
          restoreFocus: false,
          onOpenChange: (open, reason) {
            if (!open) {
              onDismiss();
              if (reason == DPopoverChangeReason.escape) {
                composer.focus.requestFocus();
              }
            }
          },
          content: DDropdownMenuContent(
            key: const ValueKey('composer-selection-toolbar'),
            semanticLabel: 'Text formatting',
            autofocus: false,
            side: DPopoverSide.top,
            align: DPopoverAlign.center,
            width: DControlStyle.isTouch(context) ? 292 : 240,
            children: [
              // The popup paints in its own overlay. Its controls must join the
              // editor's tap region so mouse presses retain the selection.
              TextFieldTapRegion(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: DSpacing.controlGap,
                      runSpacing: DSpacing.controlGap,
                      children: [
                        if (ShellScope.maybeOf(
                              context,
                            )?.supportsComposerColors(composer.siteUrl) ??
                            false)
                          ComposerSelectionColors(composer: composer),
                        _toggle(
                          'Bold',
                          const DIcon(DIcons.bold),
                          '**',
                          () => _format(
                            (value) => toggleComposerInlineMark(
                              value,
                              ComposerMark.bold,
                            ),
                          ),
                        ),
                        _toggle(
                          'Italic',
                          const DIcon(DIcons.italic),
                          '*',
                          () => _format(
                            (value) => toggleComposerInlineMark(
                              value,
                              ComposerMark.italic,
                            ),
                          ),
                        ),
                        _toggle(
                          'Underline',
                          const Icon(Icons.format_underlined),
                          'ins',
                          () => _format(
                            (value) => toggleComposerTag(value, 'ins'),
                          ),
                        ),
                        DButton.iconOnly(
                          tooltip: 'Clear formatting',
                          icon: const Icon(Icons.format_clear),
                          variant: DButtonVariant.ghost,
                          onPressed: () =>
                              _format(clearComposerInlineFormatting),
                        ),
                      ],
                    ),
                    const DDropdownMenuSeparator(),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: DSpacing.controlGap,
                      runSpacing: DSpacing.controlGap,
                      children: [
                        DButton.iconOnly(
                          tooltip: 'Link',
                          icon: const DIcon(DIcons.link),
                          variant: DButtonVariant.ghost,
                          onPressed: onLink,
                        ),
                        _toggle(
                          'Strikethrough',
                          const Icon(Icons.format_strikethrough),
                          '~~',
                          () => _format(
                            (value) => composerSelectionHasFormat(value, '~~')
                                ? clearComposerInlineFormatting(
                                    value,
                                    kind: '~~',
                                  )
                                : toggleMarkdownMark(value, '~~'),
                          ),
                        ),
                        _toggle(
                          'Inline code',
                          const DIcon(DIcons.code),
                          'code',
                          () => _format(
                            (value) => toggleComposerInlineMark(
                              value,
                              ComposerMark.inlineCode,
                            ),
                          ),
                        ),
                        DDropdownMenu(
                          content: DDropdownMenuContent(
                            semanticLabel: 'More formatting',
                            width: 180,
                            children: [
                              for (final (label, tag) in const [
                                ('Superscript', 'sup'),
                                ('Subscript', 'sub'),
                                ('Keyboard key', 'kbd'),
                              ])
                                DPopoverClose(
                                  builder: (context, close) =>
                                      TextFieldTapRegion(
                                        child: DDropdownMenuItem(
                                          closeOnSelect: false,
                                          onPressed: () {
                                            close();
                                            _format(
                                              (value) =>
                                                  toggleComposerTag(value, tag),
                                            );
                                          },
                                          child: Text(label),
                                        ),
                                      ),
                                ),
                            ],
                          ),
                          child: DDropdownMenuTrigger(
                            builder: (context, state) => DButton.iconOnly(
                              tooltip: 'More formatting',
                              icon: const DIcon(DIcons.ellipsis),
                              variant: DButtonVariant.ghost,
                              focusNode: state.focusNode,
                              expanded: state.open,
                              hasPopup: true,
                              onPressed: state.toggle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          child: DPopoverAnchor(
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    ),
  );
}
