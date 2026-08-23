import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import '../../../cooked_dom.dart';
import '../../markup.dart';
import '../../onebox.dart';

/// A category on the site the post was written on:
/// `aside.onebox.category-onebox`.
///
/// Discourse paints the category's color into the aside's `box-shadow`; here
/// it becomes the accent bar on the left, the same trick a quote uses.
class DiscourseCategoryOnebox extends StatelessWidget {
  const DiscourseCategoryOnebox({super.key, required this.data});

  final DiscourseCategoryData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: 48,
          decoration: BoxDecoration(
            color: data.color ?? muted,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              if (data.description != null) ...[
                const SizedBox(height: 4),
                Text(
                  data.description!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ],
              if (data.subcategories.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final subcategory in data.subcategories)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: subcategory.color ?? muted,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            subcategory.name,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class DiscourseSubcategory {
  const DiscourseSubcategory({required this.name, required this.color});

  final String name;
  final Color? color;
}

/// Everything the category onebox carries, read out of the aside.
class DiscourseCategoryData {
  const DiscourseCategoryData({
    required this.name,
    required this.color,
    required this.description,
    required this.subcategories,
  });

  final String name;
  final Color? color;
  final String? description;
  final List<DiscourseSubcategory> subcategories;

  static DiscourseCategoryData from(dom.Element aside) {
    final article =
        descendantWhere(aside, (e) => e.classes.contains('onebox-body')) ??
        aside;

    final name =
        descendantWhere(
          article,
          (e) => e.classes.contains('badge-category__name'),
        )?.text.trim() ??
        (descendantWhere(article, (e) => e.localName == 'h3')?.text ?? '')
            .trim();

    final description = oneLineText(
      descendantWhere(article, (e) => e.classes.contains('description')),
    );

    final subcategories = <DiscourseSubcategory>[];
    for (final entry in descendantsWhere(
      article,
      (e) => e.classes.contains('subcategory'),
    )) {
      final bg = descendantWhere(
        entry,
        (e) => e.classes.contains('badge-category-bg'),
      );
      final name = descendantWhere(
        entry,
        (e) => e.classes.contains('category-name'),
      )?.text.trim();
      if (name == null || name.isEmpty) continue;
      subcategories.add(
        DiscourseSubcategory(name: name, color: hexColorOf(bg)),
      );
    }

    return DiscourseCategoryData(
      name: name,
      color: hexColorIn(aside.attributes['style']),
      description: description,
      subcategories: subcategories,
    );
  }
}

/// Claims `aside.onebox.category-onebox`, for the dispatch in `onebox.dart`.
final OneboxEngine discourseCategoryBlock = OneboxEngine(
  matches: (aside) => aside.classes.contains('category-onebox'),
  build: (aside, envelope, siteUrl) => OneboxCard(
    data: envelope,
    siteUrl: siteUrl,
    child: DiscourseCategoryOnebox(data: DiscourseCategoryData.from(aside)),
  ),
);
