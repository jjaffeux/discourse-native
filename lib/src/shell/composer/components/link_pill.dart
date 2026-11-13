import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../../../models/pdf_attachment_type.dart';
import '../../pdf_attachment.dart';
import '../../site_emoji_text.dart';

class ComposerLinkPill extends StatelessWidget {
  const ComposerLinkPill({
    super.key,
    required this.anchor,
    required this.url,
    required this.baseStyle,
    required this.highlighted,
    required this.hovered,
    this.siteUrl,
    this.previewUrl,
  });

  final String anchor;
  final String url;
  final TextStyle baseStyle;
  final bool highlighted;
  final bool hovered;
  final String? siteUrl;
  final String? previewUrl;

  @override
  Widget build(BuildContext context) {
    if (isPdfAttachment(anchor, url)) {
      return Semantics(
        link: true,
        label: anchor,
        hint: context.l10n.editLinkTo(url),
        child: PdfAttachment(
          filename: anchor.split('|').first,
          url: previewUrl,
          siteUrl: siteUrl,
          size: DAttachmentSize.small,
          selected: highlighted,
        ),
      );
    }
    final primary = Theme.of(context).colorScheme.primary;
    return Semantics(
      link: true,
      label: anchor,
      hint: context.l10n.editLinkTo((url).toString()),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: highlighted
              ? primary.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
        ),
        child: siteUrl == null
            ? Text(
                anchor,
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: _labelStyle(primary),
              )
            : SiteEmojiText.plain(
                anchor,
                siteUrl: siteUrl!,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: _labelStyle(primary),
              ),
      ),
    );
  }

  TextStyle _labelStyle(Color primary) => baseStyle.copyWith(
    color: primary,
    decoration: hovered ? TextDecoration.underline : null,
    decorationColor: primary,
  );
}
