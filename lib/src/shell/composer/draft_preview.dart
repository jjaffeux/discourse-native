import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import 'controller.dart';

class ComposerDraftPreview extends StatelessWidget {
  const ComposerDraftPreview({
    super.key,
    required this.composer,
    required this.child,
    this.title = false,
    this.constrainToChild = true,
    this.padding = EdgeInsets.zero,
    this.style,
  });
  final ComposerController composer;
  final Widget child;
  final bool title;
  final bool constrainToChild;
  final EdgeInsetsGeometry padding;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final target = composer.discardPreviewTarget;
    final from = composer.discardPreviewFrom;
    return DTextRevisionPreview(
      current: title ? from.title ?? '' : from.reply,
      saved: title ? target?.title ?? '' : target?.reply ?? '',
      active: target != null,
      restoration: composer.rollbackAnimation,
      singleLine: title,
      constrainToChild: constrainToChild,
      style: style,
      padding: padding,
      child: child,
    );
  }
}
