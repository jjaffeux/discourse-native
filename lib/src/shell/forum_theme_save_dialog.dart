import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

class ForumThemeSaveDialog extends StatefulWidget {
  const ForumThemeSaveDialog({
    super.key,
    required this.controller,
    required this.onSave,
  });

  final DDialogController<void> controller;
  final Future<void> Function(String) onSave;

  @override
  State<ForumThemeSaveDialog> createState() => _ForumThemeSaveDialogState();
}

class _ForumThemeSaveDialogState extends State<ForumThemeSaveDialog> {
  final _name = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _name.text.trim().isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_name.text.trim());
      if (mounted) widget.controller.close();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save theme. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => DDialogContent(
    semanticLabel: 'Save theme',
    maxWidth: 420,
    children: [
      const DDialogHeader(children: [DDialogTitle(child: Text('Save theme'))]),
      DInput(
        key: const ValueKey('theme-name'),
        controller: _name,
        labelText: 'Name',
        autofocus: true,
        maxLength: 48,
        readOnly: _saving,
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _save(),
      ),
      if (_error != null) Text(_error!),
      DDialogFooter(
        children: [
          DButton(
            label: const Text('Cancel'),
            variant: DButtonVariant.outline,
            onPressed: _saving ? null : widget.controller.close,
          ),
          DButton(
            label: const Text('Save'),
            loading: _saving,
            onPressed: _name.text.trim().isEmpty ? null : _save,
          ),
        ],
      ),
    ],
  );
}
