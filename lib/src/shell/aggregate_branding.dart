import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class _DiscourseMarkColorMapper extends ColorMapper {
  const _DiscourseMarkColorMapper(this.foreground);
  final Color foreground;

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) => color == const Color(0xFFFFFFFF) ? foreground : color;
}

class AggregateBranding extends StatelessWidget {
  const AggregateBranding({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('aggregate-hero'),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(
          'assets/logo_mark.svg',
          key: const ValueKey('aggregate-discourse-logo'),
          width: 20,
          height: 20,
          excludeFromSemantics: true,
          colorMapper: _DiscourseMarkColorMapper(
            Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            'Discourse',
            style: Theme.of(context).textTheme.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        const DBadge(variant: DBadgeVariant.outline, child: Text('alpha')),
      ],
    ),
  );
}
