import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../foundation/icons/d_native_icons.dart';
import 'avatar_image.dart';
import 'profile_avatar_transactions.dart';
import 'shell_scope.dart';

/// The reader's picture with the actions that change it at once, outside the
/// section drafts the rest of Preferences saves.
class PreferencesAvatarRow extends StatelessWidget {
  const PreferencesAvatarRow({
    super.key,
    required this.siteUrl,
    required this.canUpload,
    required this.hasUploadedPicture,
    required this.enabled,
    required this.pickerError,
    required this.onChange,
    required this.onUseDefault,
  });

  static const double avatarSize = 64;

  final String siteUrl;
  final bool canUpload;

  /// Whether there is a picture to give up for the site's letter avatar.
  final bool hasUploadedPicture;
  final bool enabled;

  /// Why the device could not offer an image, which no request to the site
  /// would explain.
  final String? pickerError;
  final VoidCallback onChange;
  final VoidCallback onUseDefault;

  @override
  Widget build(BuildContext context) {
    final avatar = ShellScope.identityOf(context).profileAvatar;
    return ListenableBuilder(
      listenable: avatar,
      builder: (context, _) {
        final state = avatar.stateFor(siteUrl);
        final ready = enabled && !state.busy;
        final busyLabel = switch (state) {
          ProfileAvatarUploading() => context.l10n.uploadingPicture,
          _ => context.l10n.saving,
        };
        final error = switch (state) {
          ProfileAvatarFailed(:final message) => message,
          _ => pickerError,
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DFieldTitle(child: Text(context.l10n.profilePicture)),
            const SizedBox(height: 8),
            Row(
              children: [
                ShellSelector<({String? url, String username})>(
                  select: (shell) {
                    final user = shell.instanceFor(siteUrl)?.user;
                    return (
                      url: user?.avatarUrl,
                      username: user?.username ?? '',
                    );
                  },
                  builder: (context, user, _) {
                    final fallback = DAvatarFallback(
                      child: Text(
                        user.username.characters.firstOrNull?.toUpperCase() ??
                            '?',
                      ),
                    );
                    return DAvatar(
                      key: const ValueKey('preferences-avatar'),
                      border: false,
                      decorative: true,
                      dimension: avatarSize,
                      fallback: fallback,
                      child: AvatarImage(
                        url: user.url,
                        size: avatarSize,
                        fallback: fallback,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (canUpload)
                        DButton(
                          key: const ValueKey('preferences-avatar-change'),
                          label: Text(context.l10n.changePicture),
                          onPressed: ready ? onChange : null,
                          loading: state.busy,
                          loadingLabel: Text(busyLabel),
                          icon: const DIcon(DNativeIcons.image),
                          variant: DButtonVariant.outline,
                          size: DButtonSize.small,
                        ),
                      if (hasUploadedPicture)
                        DButton(
                          key: const ValueKey('preferences-avatar-default'),
                          label: Text(context.l10n.useDefaultPicture),
                          semanticLabel: context.l10n.useTheDefaultPicture,
                          onPressed: ready ? onUseDefault : null,
                          loading: state.busy && !canUpload,
                          loadingLabel: Text(busyLabel),
                          variant: DButtonVariant.ghost,
                          size: DButtonSize.small,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              DFieldError(
                key: const ValueKey('preferences-avatar-error'),
                errors: [error],
              ),
            ],
          ],
        );
      },
    );
  }
}
