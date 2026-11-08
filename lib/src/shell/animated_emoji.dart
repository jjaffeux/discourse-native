import 'package:flutter/widgets.dart';

import '../../shell/emoji.dart';

/// Optional animated artwork with static fallback and reduced-motion support.
class DAnimatedEmoji extends StatelessWidget {
  const DAnimatedEmoji({
    super.key,
    required this.url,
    required this.alt,
    this.animatedUrl,
    this.size = 32,
  });

  final String url;
  final String? animatedUrl;
  final String alt;
  final double size;

  @override
  Widget build(BuildContext context) {
    final animate = !MediaQuery.disableAnimationsOf(context);
    return EmojiImage(
      url: animate ? animatedUrl ?? url : url,
      fallbackUrl: url,
      alt: alt,
      size: size,
    );
  }
}
