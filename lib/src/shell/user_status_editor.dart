import 'dart:async';

import 'package:flutter/material.dart';

import '../data/emoji_picker_store.dart';
import '../models/user_status.dart';
import 'emoji_picker.dart';
import 'shell_scope.dart';
import 'site_emoji_image.dart';

Future<void> showUserStatusEditor(
  BuildContext context, {
  required String siteUrl,
}) {
  final controller = ShellScope.read(context);
  final instance = controller.instanceFor(siteUrl);
  final user = instance?.user;
  if (instance == null || user == null || !instance.config.userStatusEnabled) {
    return Future.value();
  }
  return showDialog<void>(
    context: context,
    builder: (context) => _UserStatusDialog(
      siteUrl: siteUrl,
      initialStatus: controller.userStatusFor(siteUrl, user.id, user.status),
    ),
  );
}

enum _StatusExpiry { never, oneHour, twoHours, tomorrow, custom }

class _UserStatusDialog extends StatefulWidget {
  const _UserStatusDialog({required this.siteUrl, required this.initialStatus});

  final String siteUrl;
  final UserStatus? initialStatus;

  @override
  State<_UserStatusDialog> createState() => _UserStatusDialogState();
}

class _UserStatusDialogState extends State<_UserStatusDialog> {
  late final TextEditingController _description;
  late String _emoji;
  late _StatusExpiry _expiry;
  DateTime? _customEndsAt;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialStatus;
    _description = TextEditingController(text: initial?.description ?? '');
    _emoji = initial?.emoji ?? 'speech_balloon';
    _customEndsAt = initial?.endsAt?.toLocal();
    _expiry = _customEndsAt == null
        ? _StatusExpiry.never
        : _StatusExpiry.custom;
  }

  Future<void> _pickEmoji() async {
    final shell = ShellScope.read(context);
    final picked = await showEmojiPicker(
      context: context,
      siteUrl: widget.siteUrl,
      pickerContext: EmojiPickerContext.userStatus,
      store: shell.emojiPickerStore,
      loadCatalog: ({bool refresh = false}) =>
          shell.ensureEmojiCatalog(widget.siteUrl),
      loadSearchAliases: ({bool refresh = false}) =>
          shell.ensureEmojiSearchAliases(widget.siteUrl),
      anchorContext: context,
    );
    if (mounted && picked != null) setState(() => _emoji = picked);
  }

  Future<void> _chooseExpiry(_StatusExpiry value) async {
    if (value != _StatusExpiry.custom) {
      setState(() {
        _expiry = value;
        _customEndsAt = null;
      });
      return;
    }

    final now = DateTime.now();
    final initial = _customEndsAt?.isAfter(now) == true
        ? _customEndsAt!
        : now.add(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final endsAt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!endsAt.isAfter(DateTime.now())) {
      setState(() => _error = 'Choose a time in the future.');
      return;
    }
    setState(() {
      _expiry = value;
      _customEndsAt = endsAt;
      _error = null;
    });
  }

  DateTime? _endsAt() {
    final now = DateTime.now();
    return switch (_expiry) {
      _StatusExpiry.never => null,
      _StatusExpiry.oneHour => now.add(const Duration(hours: 1)),
      _StatusExpiry.twoHours => now.add(const Duration(hours: 2)),
      _StatusExpiry.tomorrow => DateTime(
        now.year,
        now.month,
        now.day + 1,
        8,
        30,
      ),
      _StatusExpiry.custom => _customEndsAt,
    };
  }

  Future<void> _save() async {
    final description = _description.text.trim();
    if (description.isEmpty) {
      setState(() => _error = 'Enter a status description.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await ShellScope.read(context).setUserStatus(
      widget.siteUrl,
      description: description,
      emoji: _emoji,
      endsAt: _endsAt(),
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  Future<void> _clear() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await ShellScope.read(
      context,
    ).clearUserStatus(widget.siteUrl);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = _description.text.trim();
    final preview = description.isEmpty ? null : description;
    return AlertDialog(
      title: const Text('Set custom status'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Tooltip(
                    message: 'Choose status emoji',
                    child: IconButton.outlined(
                      onPressed: _busy ? null : _pickEmoji,
                      icon: SiteEmojiImage(
                        siteUrl: widget.siteUrl,
                        name: _emoji,
                        size: 24,
                        alt: 'Status emoji',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _description,
                      autofocus: true,
                      enabled: !_busy,
                      maxLength: 100,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'What’s your status?',
                        hintText: 'What are you up to?',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() => _error = null),
                      onSubmitted: (_) {
                        if (!_busy) unawaited(_save());
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<_StatusExpiry>(
                initialValue: _expiry,
                decoration: const InputDecoration(
                  labelText: 'Clear after',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: _StatusExpiry.never,
                    child: Text('Never'),
                  ),
                  DropdownMenuItem(
                    value: _StatusExpiry.oneHour,
                    child: Text('1 hour'),
                  ),
                  DropdownMenuItem(
                    value: _StatusExpiry.twoHours,
                    child: Text('2 hours'),
                  ),
                  DropdownMenuItem(
                    value: _StatusExpiry.tomorrow,
                    child: Text('Tomorrow'),
                  ),
                  DropdownMenuItem(
                    value: _StatusExpiry.custom,
                    child: Text('Custom date and time'),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value != null) unawaited(_chooseExpiry(value));
                      },
              ),
              if (_expiry == _StatusExpiry.custom && _customEndsAt != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Until ${MaterialLocalizations.of(context).formatMediumDate(_customEndsAt!)} '
                  '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(_customEndsAt!))}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (preview != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Preview: '),
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SiteEmojiImage(
                            siteUrl: widget.siteUrl,
                            name: _emoji,
                            size: 17,
                            alt: preview,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
              if (_error case final error?) ...[
                const SizedBox(height: 10),
                Text(error, style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (widget.initialStatus != null)
          TextButton(
            onPressed: _busy ? null : _clear,
            child: const Text('Clear status'),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }
}
