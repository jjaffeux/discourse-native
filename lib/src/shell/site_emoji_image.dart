import 'package:flutter/material.dart';

import 'emoji.dart';
import 'shell_scope.dart';

/// An emoji whose artwork address comes from one site's live configuration.
///
/// Site settings and uploaded emoji arrive after a topic can already be on
/// screen. Selecting just the resolved URL lets that artwork correct itself
/// without making the post or message containing it a shell-wide listener.
class SiteEmojiImage extends StatelessWidget {
  const SiteEmojiImage({
    super.key,
    required this.siteUrl,
    required this.name,
    required this.size,
    required this.alt,
    this.style,
  });

  final String siteUrl;
  final String name;
  final double size;
  final String alt;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => ShellSelector<String>(
    select: (controller) => controller.emojiUrlFor(siteUrl, name),
    builder: (context, url, child) =>
        EmojiImage(url: url, size: size, alt: alt, style: style),
  );
}
