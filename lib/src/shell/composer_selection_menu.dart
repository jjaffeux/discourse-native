import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: onFocusChange,
    child: TextFieldTapRegion(
      child: DDropdownMenu(
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
          width: 240,
          children: [
            ComposerFormattingControls(composer: composer, onLink: onLink),
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
  );
}

/// Shared formatting actions for the selection menu and mobile keyboard toolbar.
class ComposerFormattingControls extends StatefulWidget {
  const ComposerFormattingControls({
    super.key,
    required this.composer,
    required this.onLink,
    this.inline = false,
  });

  final ComposerController composer;
  final VoidCallback onLink;
  final bool inline;

  @override
  State<ComposerFormattingControls> createState() =>
      _ComposerFormattingControlsState();
}

class _ComposerFormattingControlsState
    extends State<ComposerFormattingControls> {
  late TextEditingValue _value;
  bool _rebuildScheduled = false;

  ComposerController get composer => widget.composer;
  bool get inline => widget.inline;

  @override
  void initState() {
    super.initState();
    _value = composer.value;
    composer.text.addListener(_textChanged);
  }

  @override
  void didUpdateWidget(ComposerFormattingControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.composer, composer)) return;
    oldWidget.composer.text.removeListener(_textChanged);
    _value = composer.value;
    composer.text.addListener(_textChanged);
  }

  void _textChanged() {
    // The editor also notifies when artwork arrives or mounts during layout.
    if (_value == composer.value) return;
    _value = composer.value;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_rebuildScheduled) return;
      _rebuildScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _rebuildScheduled = false;
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    composer.text.removeListener(_textChanged);
    super.dispose();
  }

  DControlSize get _size => inline ? DControlSize.large : DControlSize.regular;

  bool get _enabled => composer.isEditing && !composer.loadingBody;

  bool get _hasSelection =>
      _enabled &&
      composer.text.selection.isValid &&
      !composer.text.selection.isCollapsed;

  void _format(TextEditingValue Function(TextEditingValue) format) {
    composer.formatSelection(format);
    composer.focus.requestFocus();
  }

  void _mark(ComposerMark mark) {
    if (inline) {
      composer.toggleMark(mark);
      composer.focus.requestFocus();
    } else {
      _format((value) => toggleComposerInlineMark(value, mark));
    }
  }

  Widget _toggle(
    String label,
    Widget icon,
    bool active,
    VoidCallback action, {
    Key? key,
    bool selectionOnly = true,
  }) => DTooltip(
    message: label,
    excludeFromSemantics: true,
    child: DToggle.iconOnly(
      key: key,
      semanticLabel: label,
      icon: icon,
      size: _size,
      pressed: active,
      enabled: selectionOnly ? _hasSelection : _enabled,
      onPressedChanged: (_) {
        action();
        composer.focus.requestFocus();
      },
    ),
  );

  @override
  Widget build(BuildContext context) => TextFieldTapRegion(
    // Popup content must also join the editor's tap region to retain selection.
    child: ListenableBuilder(
      listenable: composer,
      builder: (context, _) {
        final selection = composer.text.selection;
        if (inline && (!selection.isValid || selection.isCollapsed)) {
          return const SizedBox.shrink();
        }
        final pressed = composerSelectionFormats(composer.value);
        final bold = _toggle(
          'Bold',
          const DIcon(DIcons.bold),
          pressed('**'),
          () => _mark(ComposerMark.bold),
          key: inline ? const ValueKey('composer-format-bold') : null,
          selectionOnly: !inline,
        );
        final italic = _toggle(
          'Italic',
          const DIcon(DIcons.italic),
          pressed('*'),
          () => _mark(ComposerMark.italic),
          key: inline ? const ValueKey('composer-format-italic') : null,
          selectionOnly: !inline,
        );
        final underline = _toggle(
          'Underline',
          const Icon(Icons.format_underlined),
          pressed('ins'),
          () => _format((value) => toggleComposerTag(value, 'ins')),
        );
        final clear = DButton.iconOnly(
          tooltip: 'Clear formatting',
          icon: const Icon(Icons.format_clear),
          variant: DButtonVariant.ghost,
          size: _size,
          onPressed: _hasSelection
              ? () => _format(clearComposerInlineFormatting)
              : null,
        );
        final link = DButton.iconOnly(
          key: inline ? const ValueKey('composer-format-link') : null,
          tooltip: 'Link',
          icon: const DIcon(DIcons.link),
          variant: DButtonVariant.ghost,
          size: _size,
          onPressed: _enabled ? widget.onLink : null,
        );
        final strike = _toggle(
          'Strikethrough',
          const Icon(Icons.format_strikethrough),
          pressed('~~'),
          () => _format(
            (value) => composerSelectionHasFormat(value, '~~')
                ? clearComposerInlineFormatting(value, kind: '~~')
                : toggleMarkdownMark(value, '~~'),
          ),
        );
        final code = _toggle(
          'Inline code',
          const DIcon(DIcons.code),
          pressed('code'),
          () => _mark(ComposerMark.inlineCode),
          key: inline ? const ValueKey('composer-format-inlineCode') : null,
          selectionOnly: !inline,
        );
        final more = DDropdownMenu(
          restoreFocus: false,
          content: DDropdownMenuContent(
            semanticLabel: 'More formatting',
            autofocus: !inline,
            side: DPopoverSide.top,
            width: 180,
            children: [
              for (final (label, tag) in const [
                ('Superscript', 'sup'),
                ('Subscript', 'sub'),
                ('Keyboard key', 'kbd'),
              ])
                DPopoverClose(
                  builder: (context, close) => TextFieldTapRegion(
                    child: DDropdownMenuItem(
                      closeOnSelect: false,
                      onPressed: _hasSelection
                          ? () {
                              close();
                              _format((value) => toggleComposerTag(value, tag));
                            }
                          : null,
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
              size: _size,
              focusNode: state.focusNode,
              expanded: state.open,
              hasPopup: true,
              onPressed: _hasSelection ? state.toggle : null,
            ),
          ),
        );
        final colors =
            ShellScope.maybeOf(
                  context,
                )?.supportsComposerColors(composer.siteUrl) ??
                false
            ? ComposerSelectionColors(
                composer: composer,
                size: _size,
                enabled: _hasSelection,
              )
            : null;
        if (inline) {
          return Semantics(
            key: const ValueKey('composer-formatting'),
            container: true,
            label: 'Formatting',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: DSpacing.controlGap,
              children: [
                bold,
                italic,
                code,
                link,
                underline,
                strike,
                clear,
                ?colors,
                more,
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: DSeparator(orientation: Axis.vertical, length: 20),
                ),
              ],
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              spacing: DSpacing.controlGap,
              runSpacing: DSpacing.controlGap,
              children: [?colors, bold, italic, underline, clear],
            ),
            const DDropdownMenuSeparator(),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: DSpacing.controlGap,
              runSpacing: DSpacing.controlGap,
              children: [link, strike, code, more],
            ),
          ],
        );
      },
    ),
  );
}
