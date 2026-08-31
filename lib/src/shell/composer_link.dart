import 'package:flutter/material.dart';

import '../theme/d_button.dart';
import 'composer_controller.dart';

@immutable
class _ComposerLinkDraft {
  const _ComposerLinkDraft({required this.url, required this.anchor});

  final String url;
  final String anchor;
}

Future<void> showComposerLinkDialog({
  required BuildContext context,
  required ComposerController composer,
}) async {
  if (composer.isDisposed) return;

  final expectedValue = composer.text.value;
  final selection = expectedValue.selection;
  final selectionIsInBounds =
      selection.isValid && selection.end <= expectedValue.text.length;
  final anchor = selectionIsInBounds && !selection.isCollapsed
      ? expectedValue.text.substring(selection.start, selection.end)
      : '';
  final draft = await showDialog<_ComposerLinkDraft>(
    context: context,
    builder: (context) => _ComposerLinkDialog(initialAnchor: anchor),
  );
  if (draft == null || composer.isDisposed) return;

  composer.insertLink(
    expectedValue: expectedValue,
    url: draft.url,
    anchor: draft.anchor,
  );
  composer.focus.requestFocus();
}

class _ComposerLinkDialog extends StatefulWidget {
  const _ComposerLinkDialog({required this.initialAnchor});

  final String initialAnchor;

  @override
  State<_ComposerLinkDialog> createState() => _ComposerLinkDialogState();
}

class _ComposerLinkDialogState extends State<_ComposerLinkDialog> {
  late final TextEditingController _url;
  late final TextEditingController _anchor;

  bool get _canInsert => _url.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController();
    _anchor = TextEditingController(text: widget.initialAnchor);
  }

  @override
  void dispose() {
    _url.dispose();
    _anchor.dispose();
    super.dispose();
  }

  void _insert() {
    if (!_canInsert) return;
    Navigator.of(
      context,
    ).pop(_ComposerLinkDraft(url: _url.text.trim(), anchor: _anchor.text));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('composer-link-dialog'),
    title: const Text('Insert link'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('composer-link-url'),
            controller: _url,
            autofocus: true,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _insert(),
            decoration: const InputDecoration(labelText: 'URL'),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('composer-link-anchor'),
            controller: _anchor,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _insert(),
            decoration: const InputDecoration(labelText: 'Text'),
          ),
        ],
      ),
    ),
    actions: [
      DButton(
        label: const Text('Cancel'),
        onPressed: () => Navigator.of(context).pop(),
      ),
      DButton(
        key: const ValueKey('composer-link-insert'),
        label: const Text('Insert link'),
        onPressed: _canInsert ? _insert : null,
        variant: DButtonVariant.primary,
      ),
    ],
  );
}
