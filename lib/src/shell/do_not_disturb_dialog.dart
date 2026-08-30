import 'dart:async';

import 'package:flutter/material.dart';

import '../models/do_not_disturb.dart';
import '../theme/d_button.dart';
import 'external_link.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';

Future<void> showDoNotDisturbDialog(
  BuildContext context, {
  required String siteUrl,
  ShellController? controller,
}) {
  final shell = controller ?? ShellScope.read(context);
  final instance = shell.instanceFor(siteUrl);
  if (instance?.user == null) return Future.value();
  return showDialog<void>(
    context: context,
    builder: (context) =>
        _DoNotDisturbDialog(siteUrl: siteUrl, controller: shell),
  );
}

class _DoNotDisturbDialog extends StatefulWidget {
  const _DoNotDisturbDialog({required this.siteUrl, required this.controller});

  final String siteUrl;
  final ShellController controller;

  @override
  State<_DoNotDisturbDialog> createState() => _DoNotDisturbDialogState();
}

class _DoNotDisturbDialogState extends State<_DoNotDisturbDialog> {
  DoNotDisturbOption? _saving;
  String? _error;

  Future<void> _save(DoNotDisturbOption option) async {
    setState(() {
      _saving = option;
      _error = null;
    });
    final error = await widget.controller.doNotDisturb.pause(
      widget.siteUrl,
      option.duration,
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = null;
        _error = error;
      });
    }
  }

  Future<void> _openSchedule() async {
    final user = widget.controller.instanceFor(widget.siteUrl)?.user;
    if (user == null) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    final username = Uri.encodeComponent(user.username);
    final opened = await openExternalLink(
      '${widget.siteUrl}/u/$username/preferences/notifications',
    );
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not open notification preferences.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Pause notifications for…'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final option in DoNotDisturbOption.values)
                  SizedBox(
                    width: 190,
                    child: OutlinedButton(
                      key: ValueKey('do-not-disturb-${option.name}'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(44, 44),
                      ),
                      onPressed: _saving == null
                          ? () => unawaited(_save(option))
                          : null,
                      child: _saving == option
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator.adaptive(
                                strokeWidth: 2,
                              ),
                            )
                          : Text(option.label),
                    ),
                  ),
              ],
            ),
            if (_error case final error?) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        DButton(
          label: const Text('Set a notification schedule'),
          onPressed: _saving == null ? _openSchedule : null,
        ),
        DButton(
          label: const Text('Cancel'),
          onPressed: _saving == null ? () => Navigator.of(context).pop() : null,
        ),
      ],
    );
  }
}
