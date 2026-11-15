import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../foundation/icons/d_icons.dart';
import '../models/user_auth_token.dart';
import '../models/user_preferences.dart';
import 'account_writes.dart';
import 'adaptive_dialog_action.dart';
import 'auth_token_transactions.dart';
import 'preference_fields.dart';
import 'relative_time.dart';

/// The web preferences pages for what core does only in a browser session:
/// anything that takes a password, a second-factor code or a passkey.
enum AccountSecurityPage {
  /// Password and passkeys.
  security('security'),
  secondFactor('second-factor');

  const AccountSecurityPage(this.path);
  final String path;
}

String accountSecurityUrl(
  String siteUrl,
  String username,
  AccountSecurityPage page,
) =>
    '$siteUrl/u/${Uri.encodeComponent(username.toLowerCase())}'
    '/preferences/${page.path}';

/// The account's browser sessions, and the way to the web for the rest.
///
/// The app never asks for a password, a code or a passkey, so those rows open
/// the site's own page. A browser session is ended here, at once, after the
/// reader confirms.
class PreferencesSecuritySection extends StatefulWidget {
  const PreferencesSecuritySection({
    super.key,
    required this.siteUrl,
    required this.preferences,
    required this.enabled,
    required this.transactions,
    required this.openLink,
    required this.onRevoke,
  });

  final String siteUrl;
  final UserPreferences preferences;
  final bool enabled;
  final AuthTokenTransactions transactions;

  /// Opens a web page outside the app and answers whether it could.
  final Future<bool> Function(String url) openLink;
  final ValueChanged<UserAuthToken> onRevoke;

  @override
  State<PreferencesSecuritySection> createState() =>
      _PreferencesSecuritySectionState();
}

class _PreferencesSecuritySectionState
    extends State<PreferencesSecuritySection> {
  bool _linkFailed = false;

  Future<void> _open(AccountSecurityPage page) async {
    setState(() => _linkFailed = false);
    final opened = await widget.openLink(
      accountSecurityUrl(widget.siteUrl, widget.preferences.username, page),
    );
    if (mounted && !opened) setState(() => _linkFailed = true);
  }

  Future<void> _confirmRevoke(UserAuthToken token) async {
    final name = _tokenName(context, token);
    final confirmed = await showDiscourseAlertDialog<bool>(
      context: context,
      title: Text(context.l10n.signOutThisBrowser),
      description: Text(context.l10n.signOutThisBrowserDescription(name)),
      cancelLabel: Text(context.l10n.cancel),
      actionLabel: Text(context.l10n.signOutBrowser),
      cancelResult: false,
      actionResult: true,
      actionVariant: DButtonVariant.destructive,
      actionKey: const ValueKey('preferences-auth-token-confirm'),
    );
    if (confirmed == true && mounted) widget.onRevoke(token);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PreferenceCard(
      children: [
        _WebsiteRow(
          keyName: 'password',
          title: l10n.securityPassword,
          description: l10n.securityPasswordDescription,
          onOpen: () => unawaited(_open(AccountSecurityPage.security)),
        ),
        const SizedBox(height: 18),
        _WebsiteRow(
          keyName: 'second-factor',
          title: l10n.twoFactorAuthentication,
          description: l10n.twoFactorAuthenticationDescription,
          onOpen: () => unawaited(_open(AccountSecurityPage.secondFactor)),
        ),
        const SizedBox(height: 18),
        _WebsiteRow(
          keyName: 'passkeys',
          title: l10n.passkeys,
          description: l10n.passkeysDescription,
          onOpen: () => unawaited(_open(AccountSecurityPage.security)),
        ),
        if (_linkFailed) ...[
          const SizedBox(height: 8),
          DFieldError(
            key: const ValueKey('preferences-security-link-error'),
            errors: [l10n.couldnTOpenTheWebsite],
          ),
        ],
        const SizedBox(height: 18),
        ListenableBuilder(
          listenable: widget.transactions,
          builder: (context, _) => _browsers(context),
        ),
      ],
    );
  }

  Widget _browsers(BuildContext context) {
    final state = widget.transactions.stateFor(widget.siteUrl);
    final ready = widget.enabled && !state.busy;
    final busyWith = switch (state) {
      AccountWriteBusy(:final subject) => subject,
      _ => null,
    };
    final tokens = widget.preferences.authTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DFieldTitle(child: Text(context.l10n.signedInBrowsers)),
        DFieldDescription(
          child: Text(context.l10n.signedInBrowsersDescription),
        ),
        const SizedBox(height: 8),
        if (tokens.isEmpty)
          DFieldDescription(
            key: const ValueKey('preferences-auth-tokens-empty'),
            child: Text(context.l10n.noBrowsersAreSignedIn),
          ),
        for (final token in tokens)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              key: ValueKey('preferences-auth-token-${token.id}'),
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_tokenName(context, token)),
                    if (_tokenDetail(context, token) case final detail?)
                      DFieldDescription(child: Text(detail)),
                  ],
                ),
                // Core refuses to end the session a request came from.
                if (!token.isActive)
                  DButton(
                    key: ValueKey('preferences-auth-token-revoke-${token.id}'),
                    label: Text(context.l10n.signOutBrowser),
                    semanticLabel: context.l10n.signOutBrowserNamed(
                      _tokenName(context, token),
                    ),
                    onPressed: ready
                        ? () => unawaited(_confirmRevoke(token))
                        : null,
                    loading: busyWith == token.id,
                    loadingLabel: Text(context.l10n.signingOut),
                    variant: DButtonVariant.outline,
                    size: DButtonSize.small,
                  ),
              ],
            ),
          ),
        if (state case AccountWriteFailed(:final message)) ...[
          const SizedBox(height: 4),
          DFieldError(
            key: const ValueKey('preferences-auth-tokens-error'),
            errors: [message],
          ),
        ],
      ],
    );
  }
}

String _tokenName(BuildContext context, UserAuthToken token) {
  final browser = token.browser.isEmpty
      ? context.l10n.unknownBrowser
      : token.browser;
  final system = token.os.isEmpty ? token.device : token.os;
  return system.isEmpty
      ? browser
      : context.l10n.browserOnSystem(browser, system);
}

String? _tokenDetail(BuildContext context, UserAuthToken token) {
  final parts = [
    if (token.location.isNotEmpty) token.location,
    if (token.seenAt case final seen?)
      context.l10n.lastSeenAgo(relativeTime(seen)),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

class _WebsiteRow extends StatelessWidget {
  const _WebsiteRow({
    required this.keyName,
    required this.title,
    required this.description,
    required this.onOpen,
  });

  final String keyName;
  final String title;
  final String description;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DFieldTitle(child: Text(title)),
      DFieldDescription(child: Text(description)),
      const SizedBox(height: 8),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: DButton(
          key: ValueKey('preferences-security-open-$keyName'),
          label: Text(context.l10n.openOnTheWebsite),
          semanticLabel: context.l10n.openOnTheWebsiteFor(title),
          onPressed: onOpen,
          icon: const DIcon(DIcons.upRightFromSquare),
          variant: DButtonVariant.outline,
          size: DButtonSize.small,
        ),
      ),
    ],
  );
}
