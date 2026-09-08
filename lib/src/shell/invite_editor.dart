import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/invite.dart';
import '../theme/d_button.dart';
import 'invites_controller.dart';

class InviteEditor extends StatefulWidget {
  const InviteEditor({
    super.key,
    required this.controller,
    required this.onClose,
  });

  final InvitesController controller;
  final VoidCallback onClose;

  @override
  State<InviteEditor> createState() => _InviteEditorState();
}

class _InviteEditorState extends State<InviteEditor> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _description = TextEditingController();
  final _message = TextEditingController();
  late final _uses = TextEditingController(
    text: '${_settings.defaultRedemptions(staff: _staff)}',
  );
  late final _days = TextEditingController(text: '${_settings.expiryDays}');
  bool _sendEmail = false;
  bool _saving = false;
  bool _copied = false;
  String? _error;
  DiscourseInvite? _created;

  InviteSettings get _settings => widget.controller.instance.config.invites;
  bool get _staff => widget.controller.instance.user?.staff == true;
  bool get _hasEmail => _email.text.trim().isNotEmpty;

  @override
  void dispose() {
    for (final input in [_email, _description, _message, _uses, _days]) {
      input.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving ||
        !widget.controller.canInvite ||
        !_form.currentState!.validate()) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await widget.controller.create(
      InviteDraft(
        email: _email.text,
        description: _description.text,
        customMessage: _message.text,
        maxRedemptions: _hasEmail ? 1 : int.parse(_uses.text),
        expiresAt: DateTime.now().add(Duration(days: int.parse(_days.text))),
        sendEmail: _settings.allowEmail && _hasEmail && _sendEmail,
      ),
    );
    if (!mounted || !widget.controller.isCurrent) return;
    setState(() {
      _saving = false;
      _created = result;
      _error = result == null ? widget.controller.actionError : null;
    });
  }

  Future<void> _copy() async {
    final link = _created?.link;
    if (link == null || !widget.controller.isCurrent) return;
    try {
      await Clipboard.setData(ClipboardData(text: link));
      if (mounted && widget.controller.isCurrent) {
        setState(() => _copied = true);
      }
    } catch (_) {
      if (mounted && widget.controller.isCurrent) {
        setState(() => _error = "Couldn't copy the invite link.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final limit = _settings.redemptionLimit(staff: _staff);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error case final error?)
              Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_created case final created?) ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  _hasEmail && _sendEmail
                      ? 'Invitation email sent.'
                      : 'Invite link created.',
                ),
              ),
              if (created.link case final link?) ...[
                const SizedBox(height: 12),
                SelectableText(link),
                const SizedBox(height: 12),
                DButton(
                  label: Text(_copied ? 'Copied!' : 'Copy link'),
                  variant: DButtonVariant.primary,
                  onPressed: () => unawaited(_copy()),
                ),
              ],
              DButton(
                label: const Text('Back to invites'),
                onPressed: widget.onClose,
              ),
            ] else ...[
              Text(
                'Create invite',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              TextFormField(
                style: Theme.of(context).textTheme.bodyMedium,
                controller: _email,
                enabled: !_saving,
                keyboardType: TextInputType.emailAddress,
                maxLength: 254,
                decoration: const InputDecoration(
                  labelText: 'Email (optional)',
                  counterText: '',
                  helperText: 'Leave blank for a shareable link.',
                  helperMaxLines: 2,
                ),
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  final email = value?.trim() ?? '';
                  return email.isEmpty ||
                          RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
                      ? null
                      : 'Enter a valid email address.';
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                style: Theme.of(context).textTheme.bodyMedium,
                controller: _description,
                enabled: !_saving,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                ),
              ),
              if (!_hasEmail) ...[
                const SizedBox(height: 12),
                TextFormField(
                  style: Theme.of(context).textTheme.bodyMedium,
                  controller: _uses,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(7),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Maximum uses',
                    helperText: 'Up to $limit',
                  ),
                  validator: (value) {
                    final count = int.tryParse(value ?? '');
                    return count == null || count < 1 || count > limit
                        ? 'Enter a number from 1 to $limit.'
                        : null;
                  },
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                style: Theme.of(context).textTheme.bodyMedium,
                controller: _days,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(5),
                ],
                decoration: const InputDecoration(
                  labelText: 'Expires after (days)',
                ),
                validator: (value) {
                  final days = int.tryParse(value ?? '');
                  return days == null || days < 1 || days > 36500
                      ? 'Enter a number from 1 to 36500.'
                      : null;
                },
              ),
              if (_hasEmail && _settings.allowEmail) ...[
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Send invitation email'),
                  value: _sendEmail,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _sendEmail = value ?? false),
                ),
                if (_sendEmail)
                  TextFormField(
                    style: Theme.of(context).textTheme.bodyMedium,
                    controller: _message,
                    enabled: !_saving,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Custom message (optional)',
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              DButton(
                label: Text(
                  _saving
                      ? 'Creating…'
                      : _hasEmail && _sendEmail
                      ? 'Create and send email'
                      : 'Create invite link',
                ),
                variant: DButtonVariant.primary,
                onPressed: _saving ? null : () => unawaited(_save()),
              ),
              DButton(
                label: const Text('Cancel'),
                onPressed: _saving ? null : widget.onClose,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
