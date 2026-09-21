import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_card.dart';
import 'd_code_editor.dart';
import 'd_mermaid.dart';
import 'd_separator.dart';

/// Editable Mermaid source and debounced artwork in one Native card.
///
/// [onChanged] runs synchronously so draft saving never waits for rendering.
/// Equal [source] updates preserve selection and IME composition. The editor
/// owns its controller and focus node. Narrow layouts stack the two panes.
class DMermaidEditor extends StatefulWidget {
  const DMermaidEditor({
    super.key,
    required this.source,
    required this.onChanged,
    this.readOnly = false,
  });

  final String source;
  final ValueChanged<String> onChanged;
  final bool readOnly;

  @override
  State<DMermaidEditor> createState() => DMermaidEditorState();
}

/// State exposed only to let the enclosing composer focus its embedded editor.
class DMermaidEditorState extends State<DMermaidEditor> {
  late final _code = DCodeEditingController(
    text: widget.source,
    language: 'mermaid',
  );
  final _focus = FocusNode();
  late String _preview = widget.source;
  Timer? _debounce;
  bool _expanded = false;
  bool _synchronizing = false;
  String _copyLabel = 'Copy code';

  /// Moves keyboard focus into the source without changing its selection.
  void requestFocus() => _focus.requestFocus();

  @override
  void didUpdateWidget(DMermaidEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.source != _code.text) {
      _synchronizing = true;
      final wasReadOnly = _code.readOnly;
      _code.readOnly = false;
      _code.value = TextEditingValue(
        text: widget.source,
        selection: TextSelection.collapsed(offset: widget.source.length),
      );
      _code.readOnly = wasReadOnly;
      _synchronizing = false;
      _schedule(widget.source);
    }
  }

  void _schedule(String source) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _preview = source);
    });
  }

  void _changed(String source) {
    if (widget.readOnly || _synchronizing) return;
    if (_copyLabel != 'Copy code') setState(() => _copyLabel = 'Copy code');
    _schedule(source);
    widget.onChanged(source);
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: _code.text));
      if (mounted) setState(() => _copyLabel = 'Copied');
    } on Object {
      if (mounted) setState(() => _copyLabel = 'Copy failed');
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DCard(
    spacing: 0,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(DSpacing.sm),
          child: Row(
            children: [
              const Icon(Icons.account_tree_outlined, size: 16),
              const SizedBox(width: DSpacing.sm),
              const Expanded(child: Text('Mermaid chart')),
              DButton.iconOnly(
                icon: const Icon(Icons.copy_outlined),
                tooltip: _copyLabel,
                semanticLabel: _copyLabel,
                variant: DButtonVariant.ghost,
                size: DButtonSize.small,
                onPressed: _copy,
              ),
              const SizedBox(width: DSpacing.controlGap),
              DButton.iconOnly(
                icon: Icon(
                  _expanded ? Icons.fullscreen_exit : Icons.fullscreen,
                ),
                tooltip: _expanded
                    ? 'Collapse chart editor'
                    : 'Expand chart editor',
                variant: DButtonVariant.ghost,
                size: DButtonSize.small,
                onPressed: () => setState(() => _expanded = !_expanded),
              ),
            ],
          ),
        ),
        const DSeparator(),
        LayoutBuilder(
          builder: (context, constraints) {
            final height = _expanded ? 480.0 : 320.0;
            final source = DCodeEditor(
              controller: _code,
              focusNode: _focus,
              semanticLabel: 'Mermaid source code',
              readOnly: widget.readOnly,
              onChanged: _changed,
            );
            final preview = SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(DSpacing.md),
                child: DMermaid(
                  source: _preview,
                  height: height - 2 * DSpacing.md,
                  showControls: false,
                ),
              ),
            );
            if (constraints.maxWidth < 600) {
              return Column(
                children: [
                  SizedBox(height: height, child: source),
                  const DSeparator(),
                  SizedBox(height: height, child: preview),
                ],
              );
            }
            return SizedBox(
              height: height,
              child: Row(
                textDirection: TextDirection.ltr,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: source),
                  const DSeparator(orientation: Axis.vertical),
                  Expanded(child: preview),
                ],
              ),
            );
          },
        ),
      ],
    ),
  );
}
