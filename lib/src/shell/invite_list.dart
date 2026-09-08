import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../discourse_ui.dart';
import '../data/invites_api.dart';
import '../models/discourse_instance.dart';
import '../models/invite.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'external_link.dart';
import 'invite_editor.dart';
import 'invites_controller.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'user_menu_message.dart';

class InviteSection extends StatelessWidget {
  const InviteSection({
    super.key,
    required this.siteUrl,
    required this.onOpened,
  });

  final String siteUrl;
  final VoidCallback onOpened;

  @override
  Widget build(BuildContext context) =>
      ShellSelector<
        ({ShellController shell, DiscourseInstance? instance, Object session})
      >(
        select: (shell) => (
          shell: shell,
          instance: shell.instances
              .where((site) => site.url == siteUrl)
              .firstOrNull,
          session: shell.lifecycle.capture(siteUrl).session,
        ),
        builder: (context, owner, _) {
          final instance = owner.instance;
          if (instance == null || instance.user?.canInviteToForum != true) {
            return const UserMenuMessage(
              text: 'Invites are unavailable for this account.',
            );
          }
          return _InviteSession(
            key: ValueKey((
              owner.shell,
              owner.session,
              instance.user!.id,
              instance.user!.username,
              instance.user!.staff,
              instance.config.invites,
            )),
            shell: owner.shell,
            instance: instance,
            onOpened: onOpened,
          );
        },
      );
}

class _InviteSession extends StatefulWidget {
  const _InviteSession({
    super.key,
    required this.shell,
    required this.instance,
    required this.onOpened,
  });

  final ShellController shell;
  final DiscourseInstance instance;
  final VoidCallback onOpened;

  @override
  State<_InviteSession> createState() => _InviteSessionState();
}

class _InviteSessionState extends State<_InviteSession> {
  late final InvitesController _controller = InvitesController(
    api: InvitesApi(widget.shell.api.pluginTransport),
    credentials: widget.shell.authenticator,
    instance: widget.instance,
    lifecycle: widget.shell.lifecycle,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openPage() async {
    if (!_controller.isCurrent) return;
    final user = Uri.encodeComponent(
      widget.instance.user!.username.toLowerCase(),
    );
    final url = widget.shell.absoluteUrl(
      '/u/$user/invited/${_controller.filter.name}',
      siteUrl: widget.instance.url,
    );
    if (await openExternalLink(url) && mounted && _controller.isCurrent) {
      widget.onOpened();
    }
  }

  @override
  Widget build(BuildContext context) => InviteList(
    controller: _controller,
    onManage: () => unawaited(_openPage()),
  );
}

class InviteList extends StatefulWidget {
  const InviteList({
    super.key,
    required this.controller,
    required this.onManage,
  });

  final InvitesController controller;
  final VoidCallback onManage;

  @override
  State<InviteList> createState() => _InviteListState();
}

class _InviteListState extends State<InviteList> {
  final _search = TextEditingController();
  Timer? _searchTimer;
  bool _creating = false;
  DiscourseInvite? _removing;
  DiscourseInvite? _copied;
  String? _copyError;

  @override
  void dispose() {
    _searchTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _searchChanged(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      unawaited(widget.controller.load(search: value));
    });
  }

  Future<void> _copy(DiscourseInvite invite) async {
    if (!widget.controller.isCurrent || invite.link == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: invite.link!));
      if (mounted && widget.controller.isCurrent) {
        setState(() {
          _copied = invite;
          _copyError = null;
        });
      }
    } catch (_) {
      if (mounted && widget.controller.isCurrent) {
        setState(() => _copyError = "Couldn't copy the invite link.");
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      if (_creating) {
        return InviteEditor(
          controller: controller,
          onClose: () => setState(() => _creating = false),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DButton(
                  label: const Text('Create invite'),
                  variant: DButtonVariant.primary,
                  onPressed: controller.canInvite && !controller.writing
                      ? () {
                          _searchTimer?.cancel();
                          setState(() => _creating = true);
                        }
                      : null,
                ),
                DButton(
                  label: const Text('Refresh'),
                  variant: DButtonVariant.transparent,
                  onPressed: controller.loading || controller.writing
                      ? null
                      : () => unawaited(controller.load(search: _search.text)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<InviteFilter>(
              key: ValueKey(('invite-filter', controller.filter)),
              initialValue: controller.filter,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Status',
                isDense: true,
              ),
              items: [
                for (final filter in InviteFilter.values)
                  if (!controller.loaded ||
                      controller.canSeeDetails ||
                      filter == InviteFilter.redeemed)
                    DropdownMenuItem(
                      value: filter,
                      child: Text(
                        controller.counts.containsKey(filter)
                            ? '${filter.label} (${controller.counts[filter]})'
                            : filter.label,
                      ),
                    ),
              ],
              onChanged: (filter) {
                if (filter == null) return;
                _searchTimer?.cancel();
                setState(() {
                  _removing = null;
                  _copied = null;
                });
                unawaited(
                  controller.load(filter: filter, search: _search.text),
                );
              },
            ),
            const SizedBox(height: 8),
            TextField(
              style: Theme.of(context).textTheme.bodyMedium,
              controller: _search,
              maxLength: 255,
              decoration: const InputDecoration(
                labelText: 'Search invites',
                hintText: 'Email or username',
                isDense: true,
                counterText: '',
              ),
              onChanged: _searchChanged,
            ),
            if (controller.actionError ?? _copyError case final error?)
              _Notice(error, error: true),
            if (controller.message case final message?) _Notice(message),
            if (controller.loading && !controller.loaded)
              const UserMenuMessage(text: null)
            else if (controller.error case final error?
                when !controller.loaded || controller.invites.isEmpty)
              UserMenuMessage(
                text: error,
                onRetry: () => unawaited(controller.load(search: _search.text)),
              )
            else if (controller.invites.isEmpty)
              UserMenuMessage(
                text: controller.search.isEmpty
                    ? controller.filter.emptyMessage
                    : 'No matching invites.',
              )
            else ...[
              for (final invite in controller.invites)
                _InviteRow(
                  key: ValueKey((invite.id, invite.userId)),
                  invite: invite,
                  filter: controller.filter,
                  busy: controller.writing,
                  allowEmail: controller.instance.config.invites.allowEmail,
                  copied: identical(_copied, invite),
                  confirmingRemoval: identical(_removing, invite),
                  onCopy: () => unawaited(_copy(invite)),
                  onResend: () => unawaited(controller.resend(invite)),
                  onRemove: () => setState(() => _removing = invite),
                  onCancelRemoval: () => setState(() => _removing = null),
                  onConfirmRemoval: () => unawaited(controller.remove(invite)),
                ),
              if (controller.error case final error?)
                UserMenuMessage(
                  text: error,
                  onRetry: () => unawaited(controller.load(more: true)),
                ),
              if (controller.hasMore && controller.error == null)
                DButton(
                  label: Text(controller.loading ? 'Loading…' : 'Load more'),
                  variant: DButtonVariant.transparent,
                  onPressed: controller.loading || controller.writing
                      ? null
                      : () => unawaited(controller.load(more: true)),
                ),
            ],
            const DSeparator(),
            DButton(
              label: const Text('Manage invites in browser'),
              variant: DButtonVariant.link,
              onPressed: widget.onManage,
            ),
          ],
        ),
      );
    },
  );
}

class _InviteRow extends StatelessWidget {
  const _InviteRow({
    super.key,
    required this.invite,
    required this.filter,
    required this.busy,
    required this.allowEmail,
    required this.copied,
    required this.confirmingRemoval,
    required this.onCopy,
    required this.onResend,
    required this.onRemove,
    required this.onCancelRemoval,
    required this.onConfirmRemoval,
  });

  final DiscourseInvite invite;
  final InviteFilter filter;
  final bool busy;
  final bool allowEmail;
  final bool copied;
  final bool confirmingRemoval;
  final VoidCallback onCopy;
  final VoidCallback onResend;
  final VoidCallback onRemove;
  final VoidCallback onCancelRemoval;
  final VoidCallback onConfirmRemoval;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final redeemed = filter == InviteFilter.redeemed;
    final date = redeemed ? invite.redeemedAt : invite.expiresAt;
    final expired = filter == InviteFilter.expired || invite.expired;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DIcon(
                redeemed
                    ? DIcons.user
                    : invite.email == null
                    ? DIcons.link
                    : DIcons.envelope,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  invite.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (invite.description != null && invite.description != invite.label)
            Text(invite.description!, style: theme.textTheme.bodySmall),
          if (!redeemed && invite.email == null)
            Text(
              '${invite.redemptionCount} of ${invite.maxRedemptions} uses',
              style: theme.textTheme.bodySmall,
            ),
          if (invite.domain != null)
            Text(
              'Restricted to ${invite.domain}',
              style: theme.textTheme.bodySmall,
            ),
          if (date != null)
            Text(
              '${redeemed
                  ? 'Joined'
                  : expired
                  ? 'Expired'
                  : 'Expires'} '
              '${MaterialLocalizations.of(context).formatMediumDate(date.toLocal())}',
              style: theme.textTheme.bodySmall,
            ),
          if (redeemed && invite.inviteSource != null)
            Text(
              'Invited via ${invite.inviteSource}',
              style: theme.textTheme.bodySmall,
            ),
          if (confirmingRemoval) ...[
            const Text('Remove this invite? It will no longer be usable.'),
            Wrap(
              spacing: 6,
              children: [
                DButton(
                  label: const Text('Confirm removal'),
                  variant: DButtonVariant.danger,
                  onPressed: busy ? null : onConfirmRemoval,
                ),
                DButton(
                  label: const Text('Cancel'),
                  onPressed: busy ? null : onCancelRemoval,
                ),
              ],
            ),
          ] else if (!redeemed)
            Wrap(
              spacing: 6,
              children: [
                if (invite.link != null)
                  DButton(
                    label: Text(copied ? 'Copied!' : 'Copy link'),
                    variant: DButtonVariant.transparent,
                    onPressed: busy ? null : onCopy,
                  ),
                if (invite.canDelete && invite.email != null && allowEmail)
                  DButton(
                    label: const Text('Resend'),
                    variant: DButtonVariant.transparent,
                    onPressed: busy ? null : onResend,
                  ),
                if (invite.canDelete)
                  DButton(
                    label: const Text('Remove'),
                    variant: DButtonVariant.transparentDanger,
                    onPressed: busy ? null : onRemove,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text, {this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: error ? Theme.of(context).colorScheme.error : null,
        ),
      ),
    ),
  );
}
