import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../../../plugin_api/composer_syntax.dart';
import '../../platform.dart';
import '../../shell_sheet.dart';
import 'link.dart';
import 'link_source.dart';

Future<void> showComposerLinkDialog({
  required BuildContext context,
  required ComposerEditorHost composer,
  ComposerLinkBlock? link,
}) async {
  if (!composer.isCurrent || !composer.isEditing) return;
  final expectedValue = composer.value;
  final capturedSelection = link == null
      ? expectedValue.selection
      : TextSelection(baseOffset: link.start, extentOffset: link.end);
  final selectionIsInBounds =
      capturedSelection.isValid &&
      capturedSelection.end <= expectedValue.text.length;
  final selectedAnchor =
      selectionIsInBounds && !capturedSelection.isCollapsed && link == null
      ? expectedValue.text.substring(
          capturedSelection.start,
          capturedSelection.end,
        )
      : '';
  Widget editor({Widget? sheet}) => _ComposerLinkDialog(
    initialAnchor: link?.anchor ?? selectedAnchor,
    initialUrl: link?.url ?? '',
    sheet: sheet,
  );
  final draft = context.isTouch
      ? await showShellSheet<_ComposerLinkDraft>(
          context: context,
          title: appL10n.insertLink,
          surfaceBuilder: (_, sheet) => editor(sheet: sheet),
          builder: (context) => ShellSheetForm.of<_ComposerLinkDialogState>(
            context,
          )._fields(context),
          footerBuilder: (context) => ShellSheetActions(
            children: ShellSheetForm.of<_ComposerLinkDialogState>(
              context,
            )._actions(context),
          ),
        )
      : await showDDialog<_ComposerLinkDraft>(
          context: context,
          builder: (_, _) => editor(),
        );
  if (draft == null ||
      !selectionIsInBounds ||
      !context.mounted ||
      !composer.isCurrent ||
      !composer.isEditing) {
    return;
  }

  final current = composer.value;
  final next = composerLinkValue(
    current: current,
    expectedText: expectedValue.text,
    selection: capturedSelection,
    url: draft.url,
    anchor: draft.anchor,
    existingLink: link,
  );
  if (next == null ||
      !composer.commitText(expectedText: expectedValue.text, value: next)) {
    return;
  }
  composer.requestFocus();
}

@immutable
class _ComposerLinkDraft {
  const _ComposerLinkDraft({required this.url, required this.anchor});

  final String url;
  final String anchor;
}

class _ComposerLinkDialog extends StatefulWidget {
  const _ComposerLinkDialog({
    required this.initialAnchor,
    required this.initialUrl,
    this.sheet,
  });

  final String initialAnchor;
  final String initialUrl;

  /// The phone sheet's surface, whose fields and actions read this form.
  final Widget? sheet;

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
    _url = TextEditingController(text: widget.initialUrl);
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
    DDialogClose.close<_ComposerLinkDraft>(
      context,
      _ComposerLinkDraft(url: _url.text.trim(), anchor: _anchor.text),
    );
  }

  List<Widget> _inputs(BuildContext context) => [
    DInput(
      key: const ValueKey('composer-link-url'),
      controller: _url,
      autofocus: true,
      keyboardType: TextInputType.url,
      textInputAction: TextInputAction.next,
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _insert(),
      labelText: context.l10n.urlLabel,
    ),
    DInput(
      key: const ValueKey('composer-link-anchor'),
      controller: _anchor,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _insert(),
      labelText: context.l10n.text,
    ),
  ];

  Widget _fields(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: DSpacing.lg,
    children: _inputs(context),
  );

  List<Widget> _actions(BuildContext context) => [
    DButton(
      label: Text(context.l10n.cancel),
      variant: DButtonVariant.outline,
      onPressed: () => DDialogClose.close<_ComposerLinkDraft>(context),
    ),
    DButton(
      key: const ValueKey('composer-link-insert'),
      label: Text(context.l10n.insertLink),
      onPressed: _canInsert ? _insert : null,
      variant: DButtonVariant.primary,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (widget.sheet case final sheet?) {
      return ShellSheetForm<_ComposerLinkDialogState>(
        state: this,
        child: sheet,
      );
    }
    return DDialogContent(
      key: const ValueKey('composer-link-dialog'),
      semanticLabel: context.l10n.insertLink,
      maxWidth: 460,
      children: [
        DDialogHeader(
          children: [DDialogTitle(child: Text(context.l10n.insertLink))],
        ),
        ..._inputs(context),
        DDialogFooter(children: _actions(context)),
      ],
    );
  }
}
