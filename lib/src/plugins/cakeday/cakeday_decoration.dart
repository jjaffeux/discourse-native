import 'package:discourse_native/discourse_plugin_sdk.dart' show DIcons;
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import 'cakeday_controller.dart';
import 'cakeday_data.dart';

class CakedayDecoration extends StatefulWidget {
  const CakedayDecoration({
    super.key,
    required this.controller,
    required this.site,
    required this.dates,
    required this.userId,
  });
  final CakedayController controller;
  final String site;
  final CakedayDates dates;
  final int? userId;
  @override
  State<CakedayDecoration> createState() => _CakedayDecorationState();
}

class _CakedayDecorationState extends State<CakedayDecoration> {
  @override
  void initState() {
    super.initState();
    widget.controller.observeDecorations(widget.site);
  }

  @override
  void didUpdateWidget(CakedayDecoration oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.site != widget.site) {
      widget.controller.observeDecorations(widget.site);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller, site = widget.site;
      if (!controller.enabled(site)) return const SizedBox.shrink();
      final settings = controller.settings(site), now = controller.now;
      final own =
          widget.userId != null &&
          controller.siteState.currentUserFor(site)?.id == widget.userId;
      final l10n = context.l10n;
      Widget mark(bool birthday) {
        final label = birthday
            ? (own ? l10n.cakedayOwnBirthday : l10n.cakedayOtherBirthday)
            : (own ? l10n.cakedayOwnAnniversary : l10n.cakedayOtherAnniversary);
        final names = birthday
            ? settings.birthdayEmoji
            : settings.anniversaryEmoji;
        return DTooltip(
          message: label,
          focusable: true,
          child: Semantics(
            label: label,
            excludeSemantics: true,
            child: controller.siteState.siteConfigFor(site).emojiEnabled
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final name in names)
                        EmojiImage(
                          url: controller.emoji.resolveUrl(site, name),
                          size: 18,
                          alt: label,
                        ),
                    ],
                  )
                : const DIcon(DIcons.cakeCandles, size: 18),
          ),
        );
      }

      return Wrap(
        spacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (settings.birthdays && widget.dates.celebratesBirthday(now))
            mark(true),
          if (widget.dates.celebratesAnniversary(now)) mark(false),
        ],
      );
    },
  );
}
