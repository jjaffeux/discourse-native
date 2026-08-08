import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

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
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.tertiary,
                ),
              ),
              if (data.description != null) ...[
                const SizedBox(height: 4),
                Text(
                  data.description!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
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
        _descendant(aside, (e) => e.classes.contains('onebox-body')) ?? aside;

    final name =
        _descendant(
          article,
          (e) => e.classes.contains('badge-category__name'),
        )?.text.trim() ??
        (_descendant(article, (e) => e.localName == 'h3')?.text ?? '').trim();

    final description = _descendant(
      article,
      (e) => e.classes.contains('description'),
    )?.text.replaceAll(RegExp(r'\s+'), ' ').trim().nullIfEmpty;

    final subcategories = <DiscourseSubcategory>[];
    for (final entry in _descendants(
      article,
      (e) => e.classes.contains('subcategory'),
    )) {
      final bg = _descendant(
        entry,
        (e) => e.classes.contains('badge-category-bg'),
      );
      final name = _descendant(
        entry,
        (e) => e.classes.contains('category-name'),
      )?.text.trim();
      if (name == null || name.isEmpty) continue;
      subcategories.add(
        DiscourseSubcategory(name: name, color: _colorFromStyle(bg)),
      );
    }

    return DiscourseCategoryData(
      name: name,
      color: _colorFromBoxShadow(aside.attributes['style']),
      description: description,
      subcategories: subcategories,
    );
  }

  /// `box-shadow: -5px 0px #hex`, the form the template writes the color in.
  static Color? _colorFromBoxShadow(String? style) {
    if (style == null) return null;
    final match = RegExp(r'#([0-9a-fA-F]{6})').firstMatch(style);
    if (match == null) return null;
    final value = int.tryParse(match.group(1)!, radix: 16);
    return value == null ? null : Color(0xFF000000 | value);
  }

  /// `style="background-color: #hex"`, the form subcategory dots use.
  static Color? _colorFromStyle(dom.Element? element) {
    final style = element?.attributes['style'];
    if (style == null) return null;
    final match = RegExp(r'#([0-9a-fA-F]{6})').firstMatch(style);
    if (match == null) return null;
    final value = int.tryParse(match.group(1)!, radix: 16);
    return value == null ? null : Color(0xFF000000 | value);
  }

  static dom.Element? _descendant(
    dom.Element root,
    bool Function(dom.Element) test,
  ) {
    for (final child in root.children) {
      if (test(child)) return child;
      final found = _descendant(child, test);
      if (found != null) return found;
    }
    return null;
  }

  static List<dom.Element> _descendants(
    dom.Element root,
    bool Function(dom.Element) test,
  ) {
    final found = <dom.Element>[];
    void walk(dom.Element element) {
      for (final child in element.children) {
        if (test(child)) found.add(child);
        walk(child);
      }
    }

    walk(root);
    return found;
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

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
