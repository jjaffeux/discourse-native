import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../foundation/icons/d_icons.dart';
import '../models/user_preferences.dart';
import 'account_email_transactions.dart';
import 'account_writes.dart';
import 'preference_fields.dart';

/// The account's addresses, and a request to change the primary one.
///
/// The addresses shown are what the site holds. A request changes none of
/// them: the new address waits unconfirmed until its link is followed.
class PreferencesEmailSection extends StatefulWidget {
  const PreferencesEmailSection({
    super.key,
    required this.siteUrl,
    required this.preferences,
    required this.enabled,
    required this.transactions,
    required this.onRequestChange,
  });

  final String siteUrl;
  final UserPreferences preferences;
  final bool enabled;
  final AccountEmailTransactions transactions;

  /// Answers whether the site accepted the request.
  final Future<bool> Function(String email) onRequestChange;

  @override
  State<PreferencesEmailSection> createState() =>
      _PreferencesEmailSectionState();
}

class _PreferencesEmailSectionState extends State<PreferencesEmailSection> {
  final TextEditingController _address = TextEditingController();

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    if (await widget.onRequestChange(_address.text) && mounted) {
      _address.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferences = widget.preferences;
    return PreferenceCard(
      children: [
        if (preferences.email.isNotEmpty)
          _Addresses(
            key: const ValueKey('preferences-email-primary'),
            title: context.l10n.primaryEmail,
            description: context.l10n.primaryEmailDescription,
            addresses: [preferences.email],
          ),
        if (preferences.secondaryEmails.isNotEmpty) ...[
          const SizedBox(height: 18),
          _Addresses(
            key: const ValueKey('preferences-email-secondary'),
            title: context.l10n.secondaryEmails,
            addresses: preferences.secondaryEmails,
          ),
        ],
        if (preferences.unconfirmedEmails.isNotEmpty) ...[
          const SizedBox(height: 18),
          _Addresses(
            key: const ValueKey('preferences-email-unconfirmed'),
            title: context.l10n.waitingForConfirmation,
            addresses: preferences.unconfirmedEmails,
          ),
        ],
        const SizedBox(height: 18),
        if (preferences.canEditEmail)
          ListenableBuilder(
            listenable: Listenable.merge([widget.transactions, _address]),
            builder: (context, _) => _change(context),
          )
        else
          DFieldDescription(
            key: const ValueKey('preferences-email-managed'),
            child: Text(context.l10n.thisSiteManagesYourEmail),
          ),
      ],
    );
  }

  Widget _change(BuildContext context) {
    final state = widget.transactions.stateFor(widget.siteUrl);
    final ready = widget.enabled && !state.busy;
    final typed = _address.text.trim();
    final error = switch (state) {
      AccountWriteFailed(:final message) => message,
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DField(
          enabled: ready,
          children: [
            DFieldContent(
              children: [
                DFieldLabel(child: Text(context.l10n.newEmail)),
                DFieldDescription(
                  child: Text(context.l10n.newEmailDescription),
                ),
              ],
            ),
            DFieldControl(
              label: context.l10n.newEmail,
              errors: [error],
              child: DInput(
                key: const ValueKey('preferences-email-new'),
                controller: _address,
                enabled: ready,
                invalid: error != null,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) => widget.transactions.settle(widget.siteUrl),
              ),
            ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          DFieldError(
            key: const ValueKey('preferences-email-error'),
            errors: [error],
          ),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: DButton(
            key: const ValueKey('preferences-email-change'),
            label: Text(context.l10n.changeEmail),
            onPressed:
                ready &&
                    typed.isNotEmpty &&
                    typed.toLowerCase() !=
                        widget.preferences.email.toLowerCase()
                ? _request
                : null,
            loading: state.busy,
            loadingLabel: Text(context.l10n.sendingConfirmation),
            variant: DButtonVariant.primary,
            size: DButtonSize.small,
          ),
        ),
        if (state is AccountWriteDone<String>) ...[
          const SizedBox(height: 12),
          DAlert(
            key: const ValueKey('preferences-email-sent'),
            icon: const DIcon(DIcons.envelope, size: 16),
            description: DAlertDescription(
              child: Semantics(
                liveRegion: true,
                child: Text(context.l10n.confirmationEmailSent),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Addresses extends StatelessWidget {
  const _Addresses({
    super.key,
    required this.title,
    required this.addresses,
    this.description,
  });

  final String title;
  final String? description;
  final List<String> addresses;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DFieldTitle(child: Text(title)),
      if (description case final description?)
        DFieldDescription(child: Text(description)),
      const SizedBox(height: 4),
      for (final address in addresses) Text(address),
    ],
  );
}
