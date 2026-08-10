import 'package:flutter/material.dart';

import '../data/discourse_api.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'shell_scope.dart';
import 'shell_sheet.dart';

Future<void> showAddInstanceSheet(BuildContext context) {
  const title = 'Add a site';
  const form = _AddInstanceForm();
  final isTouch = switch (Theme.of(context).platform) {
    TargetPlatform.iOS || TargetPlatform.android => true,
    _ => false,
  };

  if (isTouch) {
    return showShellSheet<void>(
      context: context,
      title: title,
      builder: (context) => form,
    );
  }

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Theme.of(dialogContext).shell.floating,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(dialogContext).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const DIcon(DIcons.xmark),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Divider(color: Theme.of(dialogContext).shell.divider, height: 1),
            const Padding(padding: EdgeInsets.all(20), child: form),
          ],
        ),
      ),
    ),
  );
}

/// Takes whatever the user types, resolves it to a real Discourse, and adds it.
class _AddInstanceForm extends StatefulWidget {
  const _AddInstanceForm();

  @override
  State<_AddInstanceForm> createState() => _AddInstanceFormState();
}

class _AddInstanceFormState extends State<_AddInstanceForm> {
  final TextEditingController _field = TextEditingController();
  bool _connecting = false;
  String? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final term = _field.text.trim();
    if (term.isEmpty || _connecting) return;

    setState(() {
      _connecting = true;
      _error = null;
    });

    final controller = ShellScope.read(context);
    String failure;

    try {
      // The duplicate check uses the resolved URL, not what was typed —
      // "meta.discourse.org" and "https://meta.discourse.org/" are one site.
      final instance = await controller.api.lookup(term);
      if (!mounted) return;
      if (!identical(ShellScope.read(context), controller)) {
        setState(() => _connecting = false);
        return;
      }

      if (!controller.contains(instance.url)) {
        final added = await controller.addInstance(instance);
        if (!mounted) return;
        if (!identical(ShellScope.read(context), controller)) {
          setState(() => _connecting = false);
          return;
        }
        if (added) {
          Navigator.of(context).pop();
          return;
        }
        failure = "Couldn't save this site. Try again.";
      } else {
        failure = '${instance.title} is already in your list.';
      }
    } on SiteLookupException catch (e, stackTrace) {
      DiagnosticsSink.current.reportError(
        e,
        stackTrace,
        operation: 'site.add',
        source: 'shell',
        handled: true,
        degraded: false,
      );
      failure = e.message;
    } catch (error, stackTrace) {
      DiagnosticsSink.current.reportError(
        error,
        stackTrace,
        operation: 'site.add',
        source: 'shell',
        handled: true,
        degraded: false,
      );
      failure = "Couldn't reach $term.";
    }

    if (!mounted) return;
    setState(() {
      _connecting = false;
      _error = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter the address of a Discourse forum.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _field,
          autofocus: true,
          enabled: !_connecting,
          keyboardType: TextInputType.url,
          autocorrect: false,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _connect(),
          decoration: InputDecoration(
            hintText: 'meta.discourse.org',
            prefixIcon: const DIcon(DIcons.globe, size: 20),
            border: const OutlineInputBorder(),
            errorText: _error,
            // Keeps the surface from resizing as the message appears.
            errorMaxLines: 3,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _connecting ? null : _connect,
          child: _connecting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                )
              : const Text('Connect'),
        ),
      ],
    );
  }
}
