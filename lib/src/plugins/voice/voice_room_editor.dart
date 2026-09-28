import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'voice_controller.dart';
import 'voice_models.dart';
import 'voice_services.dart';

Future<void> showVoiceRoomEditor(
  BuildContext context, {
  required String siteUrl,
  VoiceRoom? room,
  VoiceController? controller,
  VoiceController Function()? controllerResolver,
}) async {
  final result = await showDDialog<VoiceRoomDraft>(
    context: context,
    builder: (context, dialog) =>
        _VoiceRoomEditorDialog(room: room, dialog: dialog),
  );
  if (result == null || !context.mounted) return;
  await (controllerResolver?.call() ??
          controller ??
          PluginUiScope.require(context, voiceControllerService))
      .saveRoom(siteUrl: siteUrl, draft: result, roomId: room?.id);
}

/// A `showDialog` future completes when the route is popped, before its exit
/// animation has removed the form. Disposing these controllers in the caller
/// at that point leaves the outgoing text fields listening to dead objects.
class _VoiceRoomEditorDialog extends StatefulWidget {
  const _VoiceRoomEditorDialog({required this.room, required this.dialog});

  final VoiceRoom? room;
  final DDialogController<VoiceRoomDraft> dialog;

  @override
  State<_VoiceRoomEditorDialog> createState() => _VoiceRoomEditorDialogState();
}

class _VoiceRoomEditorDialogState extends State<_VoiceRoomEditorDialog> {
  final _form = GlobalKey<FormState>();
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
      DDialogFooter(
        children: [
          DDialogClose<VoiceRoomDraft>(
            builder: (context, close) => DButton(
              onPressed: close,
              label: Text(context.l10n.cancel),
              variant: DButtonVariant.outline,
            ),
          ),
          DButton(
            onPressed: _name.text.trim().isEmpty ? null : _save,
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
        description: _description.text.trim(),
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
