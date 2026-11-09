import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/media_pipeline.dart';
import '../../../theme/discourse_typography.dart';
import '../../emoji.dart';
import '../source_projection.dart';

/// Owns pending emoji artwork for one editor without changing its document.
final class ComposerEmojiArtwork {
  ComposerEmojiArtwork({required this.onChanged});

  final VoidCallback onChanged;
  final Set<String> _loading = {};
  bool _disposed = false;

  List<InlineSpan>? build({
    required String source,
    required TextRange range,
    required String name,
    required String? Function(String) resolve,
    required TextStyle baseStyle,
  }) {
    final url = resolve(name);
    if (url == null) return null;
    final cache = MediaPipeline.instance.emoji;
    if (!cache.isCached(url)) {
      if (_loading.add(url)) {
        unawaited(
          cache.load(url).then((_) {
            _loading.remove(url);
            if (!_disposed) onChanged();
          }),
        );
      }
      return null;
    }
    if (cache.cached(url) == null) return null;
    return [
      TextSpan(
        text: source.substring(range.start, range.end - 1),
        style: hiddenComposerSourceStyle,
      ),
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        style: baseStyle,
        child: EmojiImage(
          url: url,
          size: (baseStyle.fontSize ?? DiscourseTypography.sm) * emojiScale,
          alt: '',
        ),
      ),
    ];
  }

  void dispose() => _disposed = true;
}
