import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../../models/composer_draft.dart';

class ComposerDraftPreview extends StatelessWidget {
  const ComposerDraftPreview({
    super.key,
    required this.from,
    required this.target,
    required this.restoration,
    required this.child,
    this.title = false,
    this.constrainToChild = true,
    this.padding = EdgeInsets.zero,
    this.style,
  });
  final ComposerDraft from;
  final ComposerDraft? target;
  final Animation<double>? restoration;
  final Widget child;
  final bool title;
  final bool constrainToChild;
  final EdgeInsetsGeometry padding;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => DTextRevisionPreview(
    current: title ? from.title ?? '' : from.reply,
    saved: title ? target?.title ?? '' : target?.reply ?? '',
    active: target != null,
    restoration: restoration,
    singleLine: title,
    constrainToChild: constrainToChild,
    style: style,
    padding: padding,
    child: child,
  );
}
