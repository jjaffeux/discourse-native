import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../foundation/uri_path.dart';
import '../models/discourse_instance.dart';
import '../models/user_card.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/app_theme.dart';
import 'avatar_image.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'skeleton_fill.dart';

typedef UserCardOpener =
    Future<void> Function({
      required BuildContext context,
      required String username,
      String? siteUrl,
    });

/// Installs how a named user's full card opens.
///
/// The card draws a cooked bio and the user's activity, and those draw names
/// and links that open cards, so anything that can name a user reaches the
/// card through this scope. The application mounts it above its navigator.
class UserCardOpenerScope extends InheritedWidget {
  const UserCardOpenerScope({
    super.key,
    required this.open,
    required super.child,
  });

  final UserCardOpener open;

  static UserCardOpener? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<UserCardOpenerScope>()?.open;

  @override
  bool updateShouldNotify(UserCardOpenerScope oldWidget) =>
      open != oldWidget.open;
}

class UserCardTarget extends StatelessWidget {
  const UserCardTarget({
    super.key,
    required this.username,
    required this.child,
    this.siteUrl,
    this.semanticLabel,
  });

  const UserCardTarget.avatar({
    super.key,
    required this.username,
    required this.child,
    this.siteUrl,
    this.semanticLabel,
  });

  final String username;
  final Widget child;
  final String? siteUrl;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (username.isEmpty) return child;

    void open() => unawaited(
      UserCardOpenerScope.maybeOf(
            context,
          )?.call(context: context, username: username, siteUrl: siteUrl) ??
          Future<void>.value(),
    );

    void loadPreview() {
      final controller = ShellScope.maybeRead(context);
      final targetSite = siteUrl ?? controller?.currentInstance?.url;
      if (controller == null || targetSite == null) return;
      unawaited(
        controller.loadUserCard(
          username,
          siteUrl: targetSite,
          force:
              controller.userCardError(username, siteUrl: targetSite) != null,
        ),
      );
    }

    return DHoverCard(
      onOpenChange: (isOpen, reason) {
        if (isOpen) loadPreview();
      },
      trigger: DHoverCardTrigger(
        builder: (context, state) => DButton(
          focusNode: state.focusNode,
          onPressed: open,
          variant: DButtonVariant.inline,
          density: DButtonDensity.inlineMetadata,
          semanticLabel:
              semanticLabel ??
              context.l10n.viewProfileForUsercard((username).toString()),
          // The button speaks its semantic label and excludes the label's own.
          label: DefaultTextStyle(
            style: DefaultTextStyle.of(context).style,
            child: child,
          ),
        ),
      ),
      content: DHoverCardContent(
        align: DPopoverAlign.start,
        child: _UserCardHoverPreview(username: username, siteUrl: siteUrl),
      ),
    );
  }
}

class _UserCardHoverPreview extends StatelessWidget {
  const _UserCardHoverPreview({required this.username, required this.siteUrl});

  final String username;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    if (ShellScope.maybeIdentityOf(context) == null) {
      return Text(context.l10n.profilePreviewUnavailable);
    }
    return ShellSelector<_PreviewTarget>(
      select: (controller) {
        final targetSite = siteUrl ?? controller.currentInstance?.url;
        return (
          controller: controller,
          siteUrl: targetSite,
          // Only a connected forum can load a card. A new account session
          // forgets the store's refs, so the preview resubscribes with it.
          session: targetSite != null && controller.contains(targetSite)
              ? controller.lifecycle.capture(targetSite).session
              : null,
        );
      },
      builder: (context, target, _) {
        final (:controller, siteUrl: targetSite, :session) = target;
        if (targetSite == null || session == null) {
          return Text(context.l10n.profilePreviewUnavailable);
        }
        // A card's fetch and result are announced here, not on the shell.
        return ListenableBuilder(
          listenable: Listenable.merge([
            controller.userCardRequests,
            controller.store.ref<UserCard>(targetSite, username.toLowerCase()),
          ]),
          builder: (context, _) {
            final card = controller.userCard(username, siteUrl: targetSite);
            if (card != null) {
              return _UserCardHoverContent(card: card, siteUrl: targetSite);
            }
            final error = controller.userCardError(
              username,
              siteUrl: targetSite,
            );
            if (error != null) return Text(error);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted ||
                  controller.userCard(username, siteUrl: targetSite) != null ||
                  controller.userCardError(username, siteUrl: targetSite) !=
                      null) {
                return;
              }
              unawaited(controller.loadUserCard(username, siteUrl: targetSite));
            });
            return const UserCardSkeleton(preview: true);
          },
        );
      },
    );
  }
}

typedef _PreviewTarget = ({
  ShellController controller,
  String? siteUrl,
  Object? session,
});

class _UserCardHoverContent extends StatelessWidget {
  const _UserCardHoverContent({required this.card, required this.siteUrl});

  final UserCard card;
  final String siteUrl;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        DAvatar.frame(
          decorative: true,
          child: SizedBox.square(
            dimension: 40,
            child: AvatarImage(
              url: card.avatarUrl,
              size: 40,
              fallback: ColoredBox(
                color: tokens.muted,
                child: Center(
                  child: Text(
                    card.username.characters.firstOrNull?.toUpperCase() ?? '?',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text(
                card.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                '@${card.username}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: tokens.mutedForeground),
              ),
              if (card.title case final title?)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (card.location case final location?)
                Text(
                  location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.mutedForeground,
                    fontSize: DiscourseTypography.xs,
                    height: DiscourseTypography.lineHeightCaption,
                  ),
                ),
              ...PluginScope.of(
                context,
              ).registry.userCardMetadata(context, siteUrl, card, () {}),
            ],
          ),
        ),
      ],
    );
  }
}

String? usernameFromProfileUrl(Uri url, {String? siteUrl}) {
  final decoded = siteUrl == null
      ? tryUriPathSegments(url)
      : DiscourseInstance.pathSegmentsWithin(siteUrl, url);
  if (decoded == null) return null;
  final segments = [...decoded];
  while (segments.isNotEmpty && segments.last.isEmpty) {
    segments.removeLast();
  }
  if (segments.length != 2 || segments.first != 'u') {
    return null;
  }
  return segments.last;
}

bool showUserCardForUrl(BuildContext context, String url, {String? siteUrl}) {
  final open = UserCardOpenerScope.maybeOf(context);
  if (open == null) return false;
  final controller = ShellScope.maybeRead(context);
  final instance = siteUrl == null
      ? controller?.currentInstance
      : controller?.instances.where((site) => site.url == siteUrl).firstOrNull;
  if (instance == null) return false;

  final uri = Uri.tryParse(url);
  if (uri == null || !instance.serves(uri)) return false;

  final username = usernameFromProfileUrl(uri, siteUrl: instance.url);
  if (username == null) return false;

  unawaited(open(context: context, username: username, siteUrl: instance.url));
  return true;
}

class UserCardSkeleton extends StatelessWidget {
  const UserCardSkeleton({super.key, this.preview = false});

  final bool preview;

  @override
  Widget build(BuildContext context) => DSkeletonRegion(
    semanticsLabel: context.l10n.loadingProfile,
    color: skeletonFill(context, on: SkeletonSurface.floating),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            DSkeleton.circle(diameter: preview ? 40 : 64),
            SizedBox(width: preview ? 10 : 16),
            const Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  DSkeleton(width: 160, height: 16),
                  DSkeleton(width: 104, height: 14),
                ],
              ),
            ),
          ],
        ),
        if (!preview) ...[
          const SizedBox(height: 12),
          const DSkeleton(height: 28),
          const SizedBox(height: 12),
          const DSkeleton(height: 14),
          const SizedBox(height: 8),
          const FractionallySizedBox(
            widthFactor: 0.75,
            child: DSkeleton(height: 14),
          ),
          const SizedBox(height: 12),
          const DSkeleton(width: 160, height: 12),
        ],
      ],
    ),
  );
}
