import 'package:flutter/material.dart';

import '../../shell/select.dart';
import '../plugin_scope.dart';
import '../plugin_services.dart';
import 'resenha_controller.dart';
import 'resenha_models.dart';

Future<void> showResenhaRoomEditor(
  BuildContext context, {
  required String siteUrl,
  ResenhaRoom? room,
  ResenhaController? controller,
  ResenhaController Function()? controllerResolver,
}) async {
  final result = await showDialog<ResenhaRoomDraft>(
    context: context,
    builder: (context) => _ResenhaRoomEditorDialog(room: room),
  );
  if (result == null || !context.mounted) return;
  await (controllerResolver?.call() ??
          controller ??
          PluginScope.require(context, resenhaControllerService))
      .saveRoom(siteUrl: siteUrl, draft: result, roomId: room?.id);
}

/// Owns the form controllers for the full lifetime of the dialog route.
///
/// A `showDialog` future completes when the route is popped, before its exit
/// animation has removed the form. Disposing these controllers in the caller
/// at that point leaves the outgoing text fields listening to dead objects.
class _ResenhaRoomEditorDialog extends StatefulWidget {
  const _ResenhaRoomEditorDialog({required this.room});

  final ResenhaRoom? room;

  @override
  State<_ResenhaRoomEditorDialog> createState() =>
      _ResenhaRoomEditorDialogState();
}

class _ResenhaRoomEditorDialogState extends State<_ResenhaRoomEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _maximum;
  late final TextEditingController _chatChannel;
  late final TextEditingController _chatIdle;
  late final TextEditingController _chatTitle;
  late bool _isPublic;
  late bool _stage;
  late bool _video;
  late bool _livekit;
  late ResenhaQualityProfile _quality;

  ResenhaRoom? get _room => widget.room;

  @override
  void initState() {
    super.initState();
    final room = _room;
    _name = TextEditingController(text: room?.name);
    _description = TextEditingController(text: room?.description);
    _maximum = TextEditingController(text: room?.maxParticipants?.toString());
    _chatChannel = TextEditingController(text: room?.chatChannelId?.toString());
    _chatIdle = TextEditingController(text: room?.chatIdleMinutes?.toString());
    _chatTitle = TextEditingController(text: room?.chatThreadTitleTemplate);
    _isPublic = room?.isPublic ?? true;
    _stage = room?.type == ResenhaRoomType.stage;
    _video = room?.videoEnabled ?? true;
    _livekit = room?.livekitEnabled ?? false;
    _quality = room?.maxQualityProfile ?? ResenhaQualityProfile.maximum;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_room == null ? 'Create voice room' : 'Edit voice room'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              isRequired: true,
              child: TextField(
                controller: _name,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Name',
                  helperText: 'Required',
                ),
              ),
            ),
            TextField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Description'),
              minLines: 2,
              maxLines: 5,
            ),
            SwitchListTile.adaptive(
              value: _isPublic,
              onChanged: (value) => setState(() => _isPublic = value),
              title: const Text('Public room'),
            ),
            SwitchListTile.adaptive(
              value: _stage,
              onChanged: (value) => setState(() => _stage = value),
              title: const Text('Stage room'),
            ),
            SwitchListTile.adaptive(
              value: _video,
              onChanged: (value) => setState(() => _video = value),
              title: const Text('Allow video'),
            ),
            TextField(
              controller: _maximum,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Maximum participants',
              ),
            ),
            DSelectField<ResenhaQualityProfile>(
              initialValue: _quality,
              decoration: const InputDecoration(
                labelText: 'Maximum media quality',
              ),
              onChanged: (value) =>
                  setState(() => _quality = value ?? _quality),
              items: [
                for (final value in ResenhaQualityProfile.values)
                  DropdownMenuItem(value: value, child: Text(value.name)),
              ],
            ),
            TextField(
              controller: _chatChannel,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Chat channel ID (optional)',
              ),
            ),
            TextField(
              controller: _chatIdle,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Chat idle minutes'),
            ),
            TextField(
              controller: _chatTitle,
              decoration: const InputDecoration(
                labelText: 'Chat thread title template',
              ),
            ),
            if (_room?.livekitEnabled != null)
              SwitchListTile.adaptive(
                value: _livekit,
                onChanged: (value) => setState(() => _livekit = value),
                title: const Text('Use LiveKit'),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _name.text.trim().isEmpty ? null : _save,
        child: const Text('Save'),
      ),
    ],
  );

  void _save() => Navigator.pop(
    context,
    ResenhaRoomDraft(
      name: _name.text.trim(),
      description: _description.text.trim(),
      isPublic: _isPublic,
      type: _stage ? ResenhaRoomType.stage : ResenhaRoomType.open,
      videoEnabled: _video,
      maxParticipants: int.tryParse(_maximum.text),
      chatChannelId: int.tryParse(_chatChannel.text),
      chatIdleMinutes: int.tryParse(_chatIdle.text),
      chatThreadTitleTemplate: _chatTitle.text.trim(),
      livekitEnabled: _room?.livekitEnabled == null ? null : _livekit,
      maxQualityProfile: _quality,
    ),
  );

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _maximum.dispose();
    _chatChannel.dispose();
    _chatIdle.dispose();
    _chatTitle.dispose();
    super.dispose();
  }
}
