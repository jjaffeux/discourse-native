import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

/// Fill for the topic reader's loading placeholders.
///
/// The UI kit skeleton paints with `muted`, which a forum palette maps to its
/// `--primary-very-low`: a tint a few percent off the page, halved again by
/// the pulse. Light pages use the border neutral instead. On dark pages that
/// neutral is a hairline colour, still faint on the app's own dark theme, so
/// they mix the text colour into the page.
Color topicSkeletonColor(BuildContext context) {
  final tokens = DTokens.of(context);
  return Theme.of(context).brightness == Brightness.light
      ? tokens.border
      : Color.lerp(tokens.background, tokens.foreground, .18)!;
}
