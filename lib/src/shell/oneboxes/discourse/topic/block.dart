import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import '../../../../foundation/diagnostic_errors.dart';
import '../../../../theme/d_icon.dart';
import '../../../../theme/d_icons.dart';
import '../../../cooked_dom.dart';
import '../../../image_decode.dart';
import '../../../site_url.dart';
import '../../markup.dart';
import '../../onebox.dart';

/// A Discourse topic on some site, oneboxed from another:
/// `aside.onebox.discoursetopic`.
///
/// The local equivalent — a topic on the site the post was written on — is
/// rendered by Discourse as a quote (see `discourse_topic_onebox.mustache`),
/// which lands in `quote.dart`. This is the cross-site shape: title, category
/// and tags, and the excerpt the remote site advertised.
class DiscourseTopicOnebox extends StatelessWidget {
  const DiscourseTopicOnebox({super.key, required this.data, this.siteUrl});

  final DiscourseTopicData data;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    final text = _text(context);

    final thumbnail = data.thumbnail;
    if (thumbnail == null) return text;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Thumbnail(thumbnail: thumbnail, siteUrl: siteUrl),
        const SizedBox(width: 12),
        Expanded(child: text),
      ],
    );
  }

  Widget _text(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          data.title,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        if (data.categories.isNotEmpty || data.tags.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final category in data.categories)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: category.color ?? muted,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      category.name,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              if (data.tags.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DIcon(
                      DIcons.tag,
                      size: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      data.tags.join(', '),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
        if (data.description != null) ...[
          const SizedBox(height: 6),
          Text(
            data.description!,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
        ],
      ],
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.thumbnail, required this.siteUrl});

  final OneboxThumbnail thumbnail;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: AspectRatio(
          aspectRatio: thumbnail.aspectRatio ?? 1,
          child: Image.network(
            resolveSiteUrl(thumbnail.src, siteUrl),
            fit: BoxFit.cover,
            cacheWidth: imagePhysicalPixels(context, 88),
            errorBuilder: (context, error, stackTrace) {
              reportImageError(
                error,
                stackTrace,
                operation: 'onebox.topicThumbnail',
              );
              return const SizedBox();
            },
          ),
        ),
      ),
    );
  }
}

class DiscourseTopicCategory {
  const DiscourseTopicCategory({required this.name, required this.color});

  final String name;
  final Color? color;
}

/// Everything the cross-site topic onebox carries, read out of the aside.
class DiscourseTopicData {
  const DiscourseTopicData({
    required this.title,
    required this.categories,
    required this.tags,
    required this.description,
    required this.thumbnail,
  });

  final String title;
  final List<DiscourseTopicCategory> categories;
  final List<String> tags;
  final String? description;
  final OneboxThumbnail? thumbnail;

  static DiscourseTopicData from(dom.Element aside, OneboxData envelope) {
    final article =
        descendantWhere(aside, (e) => e.classes.contains('onebox-body')) ??
        aside;

    final categories = <DiscourseTopicCategory>[];
    for (final badge in descendantsWhere(
      article,
      (e) => e.classes.contains('badge-wrapper'),
    )) {
      final bg = descendantWhere(
        badge,
        (e) => e.classes.contains('badge-category-bg'),
      );
      final name = descendantWhere(
        badge,
        (e) => e.classes.contains('category-name'),
      )?.text.trim();
      if (name == null || name.isEmpty) continue;
      categories.add(DiscourseTopicCategory(name: name, color: hexColorOf(bg)));
    }

    final tags =
        descendantWhere(article, (e) => e.classes.contains('discourse-tags'))
            ?.children
            .where((e) => e.classes.contains('discourse-tag'))
            .map((e) => e.text.trim())
            .where((tag) => tag.isNotEmpty)
            .toList() ??
        const [];

    // The first bare paragraph is the excerpt; labels further down belong to
    // the generic metadata row and are left to the envelope's fallback.
    final description = article.children
        .where(
          (e) =>
              e.localName == 'p' &&
              descendantWhere(e, (c) => c.classes.contains('label1')) == null,
        )
        .map(oneLineText)
        .nonNulls
        .firstOrNull;

    return DiscourseTopicData(
      title: envelope.title ?? '',
      categories: categories,
      tags: tags,
      description: description,
      thumbnail: envelope.thumbnail,
    );
  }
}

/// Claims `aside.onebox.discoursetopic`, for the dispatch in `onebox.dart`.
final OneboxEngine discourseTopicBlock = OneboxEngine(
  matches: (aside) => aside.classes.contains('discoursetopic'),
  build: (aside, envelope, siteUrl) => OneboxCard(
    data: envelope,
    siteUrl: siteUrl,
    child: DiscourseTopicOnebox(
      data: DiscourseTopicData.from(aside, envelope),
      siteUrl: siteUrl,
    ),
  ),
);
