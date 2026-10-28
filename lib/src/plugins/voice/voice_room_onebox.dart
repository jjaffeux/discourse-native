import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;

import 'voice_models.dart';
import 'voice_services.dart';

/// Baked room metadata. Presence always comes from the viewer's live directory.
final class VoiceRoomOneboxData {
  const VoiceRoomOneboxData({
    required this.url,
    required this.name,
    required this.type,
    required this.descriptionHtml,
    required this.localSlug,
    required this.stage,
  });

  final String url;
  final String name;
  final String type;
  final String descriptionHtml;
  final String? localSlug;
  final bool stage;

  static VoiceRoomOneboxData? read(dom.Element element, String? siteUrl) {
    if (element.localName != 'aside' ||
        !element.classes.contains('onebox') ||
        !element.classes.contains('live-room-onebox')) {
      return null;
    }
    final title = element.querySelector('.live-room-onebox__title a');
    final url = title?.attributes['href'];
    if (title == null || url == null || title.text.trim().isEmpty) return null;
    final site = Uri.tryParse(siteUrl ?? '');
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final resolved = site?.resolveUri(uri) ?? uri;
    if (!const {'http', 'https'}.contains(resolved.scheme) ||
        resolved.host.isEmpty ||
        resolved.userInfo.isNotEmpty) {
      return null;
    }
    String? slug;
    if (site != null && site.hasAuthority && site.origin == resolved.origin) {
      try {
        final sitePath = site.pathSegments
            .where((part) => part.isNotEmpty)
            .toList();
        final path = resolved.pathSegments
            .where((part) => part.isNotEmpty)
            .toList();
        if (path.length == sitePath.length + 3 &&
            List.generate(
              sitePath.length,
              (i) => path[i] == sitePath[i],
            ).every((same) => same) &&
            const {'live', 'voice'}.contains(path[sitePath.length]) &&
            path[sitePath.length + 1] == 'r') {
          slug = path.last;
        }
      } on FormatException {
        return null;
      }
    }
    return VoiceRoomOneboxData(
      url: resolved.toString(),
      name: title.text.trim(),
      type: element.querySelector('.live-room-onebox__type')?.text.trim() ?? '',
      descriptionHtml:
          element.querySelector('.live-room-onebox__description')?.innerHtml ??
          '',
      localSlug: slug,
      stage: title.querySelector('.d-icon-ear-listen') != null,
    );
  }
}

final class VoiceRoomOnebox extends StatelessWidget {
  const VoiceRoomOnebox({super.key, required this.data, this.siteUrl});

  final VoiceRoomOneboxData data;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    final controller = PluginUiScope.maybe(context, voiceControllerService);
    final site = siteUrl;
    if (controller == null || site == null || data.localSlug == null) {
      return VoiceRoomOneboxCard(data: data, siteUrl: siteUrl);
    }
    return ListenableBuilder(
      listenable: controller.roomListenable,
      builder: (context, _) {
        final room = controller
            .directory(site)
            ?.rooms
            .where((room) => room.slug == data.localSlug && !room.ephemeral)
            .firstOrNull;
        return VoiceRoomOneboxCard(
          data: data,
          siteUrl: siteUrl,
          participants: room?.participants ?? const [],
        );
      },
    );
  }
}

/// The native card composition shared by cooked content and the styleguide.
final class VoiceRoomOneboxCard extends StatelessWidget {
  const VoiceRoomOneboxCard({
    super.key,
    required this.data,
    this.siteUrl,
    this.participants = const [],
  });

  final VoiceRoomOneboxData data;
  final String? siteUrl;
  final List<VoiceParticipant> participants;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: DSpacing.sm),
    child: DCard(
      size: DCardSize.small,
      children: [
        DCardHeader(
          title: DButton(
            isLink: true,
            variant: DButtonVariant.link,
            alignment: AlignmentDirectional.centerStart,
            icon: DIcon(data.stage ? DIcons.earListen : DIcons.microphoneLines),
            label: Text(data.name),
            onPressed: () =>
                unawaited(openLink(context, data.url, siteUrl: siteUrl)),
          ),
          description: data.type.isEmpty
              ? null
              : DCardDescription(child: Text(data.type)),
        ),
        if (data.descriptionHtml.isNotEmpty)
          DCardContent(
            child: CookedHtml(html: data.descriptionHtml, siteUrl: siteUrl),
          ),
        if (participants.isNotEmpty)
          DCardContent(
            child: Wrap(
              spacing: DSpacing.sm,
              runSpacing: DSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DAvatarGroup(
                  size: DAvatarSize.sm,
                  children: [
                    for (final participant in participants.take(5))
                      DAvatar(
                        size: DAvatarSize.sm,
                        decorative: true,
                        child: AvatarImage(
                          url: siteUrl == null
                              ? null
                              : participant.avatarUrl(siteUrl!, size: 48),
                          size: DAvatarSize.sm.dimension,
                          fallback: DAvatarFallback(
                            child: Text(
                              participant.username.isEmpty
                                  ? '?'
                                  : participant.username.characters.first,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                Text(context.l10n.voiceRoomHereNow(participants.length)),
              ],
            ),
          ),
      ],
    ),
  );
}
