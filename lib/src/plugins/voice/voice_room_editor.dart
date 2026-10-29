import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'voice_controller.dart';
import 'voice_models.dart';
import 'voice_services.dart';
import 'voice_shell_service.dart';

Future<void> showVoiceRoomEditor(
  BuildContext context, {
  required String siteUrl,
  VoiceRoom? room,
  VoiceController? controller,
  VoiceController Function()? controllerResolver,
}) async {
  final originController =
      controllerResolver?.call() ??
      controller ??
      PluginUiScope.require(context, voiceControllerService);
  final ownsAccount = originController.captureSiteSession(siteUrl);
  final shell = PluginUiScope.maybe(context, voiceShellService);
  final result = await showDDialog<VoiceRoomDraft>(
    context: context,
    builder: (context, dialog) => _VoiceRoomEditorDialog(
      room: room,
      dialog: dialog,
      nameTaken: (name) =>
          originController
              .directory(siteUrl)
              ?.rooms
              .any(
                (existing) =>
                    existing.id != room?.id && existing.name.trim() == name,
              ) ??
          false,
      onDelete: room == null || !room.canDelete || room.ephemeral
          ? null
          : () async {
              if (!ownsAccount()) return false;
              final current =
                  controllerResolver?.call() ?? controller ?? originController;
              final deleted = await current.deleteRoom(
                siteUrl: siteUrl,
                roomId: room.id,
              );
              if (deleted && ownsAccount()) {
                shell?.roomDeleted(siteUrl, room.id);
              }
              return deleted && ownsAccount();
            },
    ),
  );
  if (result == null || !context.mounted || !ownsAccount()) return;
  final current = controllerResolver?.call() ?? controller ?? originController;
  if (room == null && current.directory(siteUrl)?.canCreateRoom != true) return;
  final saved = await current.saveRoom(
    siteUrl: siteUrl,
    draft: result,
    roomId: room?.id,
  );
  if (saved == null && context.mounted && ownsAccount()) {
    DToast.maybeOf(context)?.add(
      DToastOptions(
        description: context.l10n.couldnTSaveTheVoiceRoom,
        type: DToastType.error,
      ),
    );
  }
}

/// A `showDialog` future completes when the route is popped, before its exit
/// animation has removed the form. Disposing these controllers in the caller
/// at that point leaves the outgoing text fields listening to dead objects.
class _VoiceRoomEditorDialog extends StatefulWidget {
  const _VoiceRoomEditorDialog({
    required this.room,
    required this.dialog,
    required this.nameTaken,
    this.onDelete,
  });

  final VoiceRoom? room;
  final DDialogController<VoiceRoomDraft> dialog;
  final bool Function(String) nameTaken;
  final Future<bool> Function()? onDelete;

  @override
  State<_VoiceRoomEditorDialog> createState() => _VoiceRoomEditorDialogState();
}

class _VoiceRoomEditorDialogState extends State<_VoiceRoomEditorDialog> {
  final _form = GlobalKey<FormState>();
  bool _deleting = false;
  bool _deleteFailed = false;
  final _advanced = DAccordionController<String>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _maximum;
  late final TextEditingController _chatChannel;
  late final TextEditingController _chatIdle;
  late bool _isPublic;
  late bool _stage;
  late bool _video;
  late bool _livekit;
  late VoiceQualityProfile _quality;

  VoiceRoom? get _room => widget.room;

  @override
  void initState() {
    super.initState();
    final room = _room;
    _name = TextEditingController(text: room?.name);
    _description = TextEditingController(text: room?.description);
    _maximum = TextEditingController(text: room?.maxParticipants?.toString());
    _chatChannel = TextEditingController(text: room?.chatChannelId?.toString());
    _chatIdle = TextEditingController(text: room?.chatIdleMinutes?.toString());
    _isPublic = room?.isPublic ?? true;
    _stage = room?.type == VoiceRoomType.stage;
    _video = room?.videoEnabled ?? true;
    _livekit = room?.livekitEnabled ?? false;
    _quality = room?.maxQualityProfile ?? VoiceQualityProfile.maximum;
  }

  @override
  Widget build(BuildContext context) => DDialogContent(
    showCloseButton: false,
    maxWidth: 520,
    semanticLabel: _room == null
        ? context.l10n.createVoiceRoom
        : context.l10n.editVoiceRoom,
    children: [
      DDialogHeader(
        children: [
          DDialogTitle(
            child: Text(
              _room == null
                  ? context.l10n.createVoiceRoom
                  : context.l10n.editVoiceRoom,
            ),
          ),
          DDialogDescription(
            child: Text(
              context.l10n.chooseHowPeopleJoinAndParticipateInYourRoom,
            ),
          ),
        ],
      ),
      DDialogScrollArea(
        maxHeightFactor: .65,
        child: Form(
          key: _form,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: DFieldGroup(
            spacing: DSpacing.lg,
            children: [
              DFieldSet(
                semanticLabel: context.l10n.roomDetails,
                children: [
                  DInput(
                    isRequired: true,
                    controller: _name,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    labelText: context.l10n.name,
                    hintText: context.l10n.voiceRoomNameExample,
                    validator: (value) {
                      final name = value?.trim() ?? '';
                      if (name.isEmpty) return context.l10n.enterARoomName;
                      if (widget.nameTaken(name)) {
                        return 'A voice room with this name already exists.';
                      }
                      if (name.runes.length > 80) {
                        return context.l10n.use80CharactersOrFewer;
                      }
                      return null;
                    },
                  ),
                  DTextarea(
                    controller: _description,
                    labelText: context.l10n.description,
                    hintText: context.l10n.whatWillPeopleTalkAboutOptional,
                    minLines: 2,
                    maxLines: 5,
                  ),
                ],
              ),
              const DFieldSeparator(),
              DFieldSet(
                children: [
                  DFieldLegend(child: Text(context.l10n.roomSettings)),
                  DFieldGroup(
                    variant: DFieldGroupVariant.choice,
                    children: [
                      DSwitchTile(
                        value: _isPublic,
                        onChanged: (value) => setState(() => _isPublic = value),
                        title: DFieldLabel(
                          child: Text(context.l10n.publicRoom),
                        ),
                        subtitle: DFieldDescription(
                          child: Text(context.l10n.visibleToEveryoneOnTheForum),
                        ),
                      ),
                      DSwitchTile(
                        value: _stage,
                        onChanged: (value) => setState(() => _stage = value),
                        title: DFieldLabel(child: Text(context.l10n.stageRoom)),
                        subtitle: DFieldDescription(
                          child: Text(
                            context
                                .l10n
                                .peopleJoinAsListenersUntilInvitedToSpeak,
                          ),
                        ),
                      ),
                      DSwitchTile(
                        value: _video,
                        onChanged: (value) => setState(() => _video = value),
                        title: DFieldLabel(
                          child: Text(context.l10n.allowVideo),
                        ),
                        subtitle: DFieldDescription(
                          child: Text(
                            context
                                .l10n
                                .letParticipantsShareTheirCameraAndScreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final horizontal =
                          constraints.maxWidth >= 440 &&
                          MediaQuery.textScalerOf(context).scale(14) <= 21;
                      return Flex(
                        direction: horizontal ? Axis.horizontal : Axis.vertical,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        spacing: DSpacing.lg,
                        children: [
                          Flexible(
                            flex: horizontal ? 1 : 0,
                            child: DInput(
                              controller: _maximum,
                              keyboardType: TextInputType.number,
                              labelText: context.l10n.maximumParticipants,
                              hintText: context.l10n.forumDefault,
                              helperText: _stage
                                  ? context.l10n.optional2200People
                                  : context.l10n.optional250People,
                              validator: (value) => _validateNumber(
                                value,
                                min: 2,
                                max: _stage ? 200 : 50,
                              ),
                            ),
                          ),
                          Flexible(
                            flex: horizontal ? 1 : 0,
                            child: DSelect<VoiceQualityProfile>.controlled(
                              isExpanded: true,
                              value: _quality,
                              label: Text(context.l10n.maximumMediaQuality),
                              onChanged: (value) =>
                                  setState(() => _quality = value ?? _quality),
                              entries: [
                                for (final value in VoiceQualityProfile.values)
                                  DSelectOption(
                                    value: value,
                                    label: _qualityLabel(value),
                                    child: Text(_qualityLabel(value)),
                                  ),
                              ],
                              initialValue: _quality,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
              DAccordion<String>(
                controller: _advanced,
                keepMounted: true,
                children: [
                  DAccordionItem<String>(
                    value: 'advanced',
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DAccordionTrigger(
                          child: Text(context.l10n.advancedSettings),
                        ),
                        DAccordionContent(
                          child: DFieldGroup(
                            children: [
                              DInput(
                                controller: _chatChannel,
                                keyboardType: TextInputType.number,
                                labelText: context.l10n.chatChannelIDOptional,
                                hintText: 'e.g. 42',
                                helperText: context
                                    .l10n
                                    .useAChannelWithThreadingEnabledForRoomConversations,
                                validator: (value) =>
                                    _validateNumber(value, min: 1),
                              ),
                              DInput(
                                controller: _chatIdle,
                                keyboardType: TextInputType.number,
                                labelText:
                                    context.l10n.newChatThreadAfterMinutes,
                                hintText: '15',
                                helperText: context
                                    .l10n
                                    .startAFreshThreadAfter21440MinutesOfInactivity,
                                validator: (value) =>
                                    _validateNumber(value, min: 2, max: 1440),
                              ),
                              if (_room?.livekitEnabled != null)
                                DSwitchTile(
                                  value: _livekit,
                                  onChanged: (value) =>
                                      setState(() => _livekit = value),
                                  title: DFieldLabel(
                                    child: Text(context.l10n.useLiveKit),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      if (_deleteFailed)
        DFieldError(child: Text(context.l10n.voiceRoomDeleteFailed)),
      DDialogFooter(
        children: [
          if (widget.onDelete != null)
            DButton(
              onPressed: _deleting ? null : _delete,
              loading: _deleting,
              label: Text(context.l10n.voiceRoomDelete),
              variant: DButtonVariant.destructive,
            ),
          DDialogClose<VoiceRoomDraft>(
            builder: (context, close) => DButton(
              onPressed: close,
              label: Text(context.l10n.cancel),
              variant: DButtonVariant.outline,
            ),
          ),
          DButton(
            onPressed:
                _deleting ||
                    _name.text.trim().isEmpty ||
                    widget.nameTaken(_name.text.trim()) ||
                    _name.text.trim().runes.length > 80
                ? null
                : _save,
            label: Text(
              _room == null
                  ? context.l10n.createRoom
                  : context.l10n.saveChanges,
            ),
            variant: DButtonVariant.primary,
          ),
        ],
      ),
    ],
  );

  Future<void> _delete() async {
    final confirmed = await showDAlertDialog<bool>(
      context: context,
      builder: (context, dialog) => DAlertDialogContent(
        children: [
          DAlertDialogHeader(
            title: Text(context.l10n.voiceRoomDelete),
            description: Text(context.l10n.voiceRoomDeleteConfirm),
          ),
          DAlertDialogFooter(
            children: [
              DAlertDialogCancel<bool>(label: Text(context.l10n.cancel)),
              DAlertDialogAction<bool>(
                label: Text(context.l10n.voiceRoomDelete),
                result: true,
                variant: DButtonVariant.destructive,
              ),
            ],
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _deleting = true;
      _deleteFailed = false;
    });
    final deleted = await widget.onDelete!();
    if (!mounted) return;
    if (deleted) {
      widget.dialog.close();
    } else {
      setState(() {
        _deleting = false;
        _deleteFailed = true;
      });
    }
  }

  String _qualityLabel(VoiceQualityProfile quality) => switch (quality) {
    VoiceQualityProfile.standard => appL10n.standard,
    VoiceQualityProfile.high => appL10n.high,
    VoiceQualityProfile.maximum => appL10n.maximum,
  };

  String? _validateNumber(String? value, {required int min, int? max}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final number = int.tryParse(text);
    if (number == null || number < min || (max != null && number > max)) {
      return max == null
          ? appL10n.enterAWholeNumberOfOrMore((min).toString())
          : appL10n.enterAWholeNumberFromTo((min).toString(), (max).toString());
    }
    return null;
  }

  void _save() {
    final invalid = _form.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      if (_validateNumber(_chatChannel.text, min: 1) != null ||
          _validateNumber(_chatIdle.text, min: 2, max: 1440) != null) {
        _advanced.open('advanced');
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && invalid.first.mounted) {
          Scrollable.ensureVisible(invalid.first.context);
        }
      });
      return;
    }
    widget.dialog.close(
      VoiceRoomDraft(
        name: _name.text.trim(),
        description: _description.text,
        isPublic: _isPublic,
        type: _stage ? VoiceRoomType.stage : VoiceRoomType.open,
        videoEnabled: _video,
        maxParticipants: int.tryParse(_maximum.text.trim()),
        chatChannelId: int.tryParse(_chatChannel.text.trim()),
        chatIdleMinutes: int.tryParse(_chatIdle.text.trim()) ?? 15,
        livekitEnabled: _room?.livekitEnabled == null ? null : _livekit,
        maxQualityProfile: _quality,
      ),
    );
  }

  @override
  void dispose() {
    _advanced.dispose();
    _name.dispose();
    _description.dispose();
    _maximum.dispose();
    _chatChannel.dispose();
    _chatIdle.dispose();
    super.dispose();
  }
}
