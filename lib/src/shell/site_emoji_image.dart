import 'package:flutter/material.dart';

import 'emoji.dart';
import 'site_presentation_scope.dart';

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
  Widget build(BuildContext context) {
    final presentation = SitePresentationScope.of(context);
    return ListenableBuilder(
      listenable: presentation.emojiChangesFor(siteUrl),
      builder: (context, _) => EmojiImage(
        url: presentation.emojiUrlFor(siteUrl, name),
        size: size,
        alt: alt,
        style: style,
      ),
    );
  }
}
