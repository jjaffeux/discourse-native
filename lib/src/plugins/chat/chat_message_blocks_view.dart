import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import 'chat_controller.dart';
import 'chat_message.dart';
import 'chat_message_blocks.dart';
import 'chat_services.dart';

class ChatMessageBlocks extends StatelessWidget {
  const ChatMessageBlocks({
    super.key,
    required this.siteUrl,
    required this.message,
  });
  final String siteUrl;
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final chat = PluginUiScope.require(context, chatControllerService);
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: DSpacing.sm,
        children: [for (final block in message.blocks) _block(context, block)],
      ),
    );
  }

  Widget _cooked(String html) => CookedHtml(
    html: html,
    siteUrl: siteUrl,
    compactParagraphs: true,
    mentionedUserStatuses: message.mentionedUserStatuses,
  );

  Widget _block(BuildContext context, ChatBlock block) => switch (block) {
    ChatActionsBlock() => _elements(context, block.elements, actions: true),
    ChatInformativeBlock() => _elements(
      context,
      block.elements,
      actions: false,
    ),
    ChatConfirmationBlock() => ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth:
            40 *
            MediaQuery.textScalerOf(context).scale(
              Theme.of(context).textTheme.bodyMedium?.fontSize ??
                  DiscourseTypography.base,
            ),
      ),
      child: DCard(
        size: DCardSize.small,
        children: [
          DCardHeader(
            title: DCardTitle(
              child: switch (block.cookedTitle) {
                final html? => _cooked(html),
                null => Text(block.title),
              },
            ),
          ),
          DCardContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: DSpacing.sm,
              children: [
                if (block.changes.isNotEmpty)
                  for (final change in block.changes)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: DSpacing.xs,
                      children: [
                        Text(change.label),
                        Wrap(
                          spacing: DSpacing.xs,
                          runSpacing: DSpacing.xs,
                          children: [
                            _value(
                              context,
                              change.before,
                              change.beforeColor,
                              before: true,
                            ),
                            const DIcon(DIcons.chevronRight, size: 14),
                            _value(context, change.after, change.afterColor),
                          ],
                        ),
                      ],
                    )
                else if (block.showDescription) ...[
                  if (block.descriptionLabel case final label?) Text(label),
                  if (message.cooked.isNotEmpty) _cooked(message.cooked),
                ],
                if (block.cookedError case final error?) _cooked(error),
                for (final parameter in block.parameters)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: DSpacing.xxs,
                    children: [
                      Text(
                        parameter.label,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.merge(monospaceTextStyle),
                      ),
                      _value(context, parameter.value, parameter.color),
                    ],
                  ),
              ],
            ),
          ),
          DCardContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: DSpacing.sm,
              children: [
                if (block.cookedStatus case final status?)
                  _cooked(status)
                else ...[
                  if (block.cookedQuestion case final question?)
                    _cooked(question),
                  _elements(context, block.elements, actions: true),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  };

  Widget _value(
    BuildContext context,
    String value,
    String? color, {
    bool before = false,
  }) {
    final parsed = _color(color);
    final text = Text(
      value,
      style: before
          ? const TextStyle(decoration: TextDecoration.lineThrough)
          : null,
    );
    if (parsed == null) return text;
    return DBadge(
      variant: DBadgeVariant.outline,
      borderColor: parsed,
      semanticLabel: '$value ${color ?? ''}',
      child: text,
    );
  }

  Widget _elements(
    BuildContext context,
    List<ChatBlockElement> elements, {
    required bool actions,
  }) {
    final chat = PluginUiScope.require(context, chatControllerService);
    final session = chat.captureSession(siteUrl);
    return Wrap(
      spacing: DSpacing.xs,
      runSpacing: DSpacing.xs,
      children: [
        for (final element in elements)
          switch (element) {
            ChatBlockButton() => DButton(
              variant: switch (element.style) {
                'danger' => DButtonVariant.destructive,
                'primary' => DButtonVariant.primary,
                _ => DButtonVariant.outline,
              },
              label: Text(element.label),
              icon: switch (element.icon) {
                final name? => switch (pluginIconNamed(context, name)) {
                  final icon? => DIcon(icon),
                  null => null,
                },
                _ => null,
              },
              loading:
                  actions &&
                  chat.messageInteractionPending(siteUrl, message.id),
              onPressed:
                  !actions ||
                      !chat.canInteractWithBlock(
                        siteUrl,
                        message,
                        element.actionId,
                      )
                  ? null
                  : () {
                      if (session.isCurrent &&
                          chat.canInteractWithBlock(
                            siteUrl,
                            message,
                            element.actionId,
                          )) {
                        unawaited(_interact(context, chat, element.actionId));
                      }
                    },
            ),
            ChatBlockCategory() => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: DSpacing.xxs,
              children: [
                if (element.parentName case final parent?)
                  _value(context, parent, element.parentColor),
                if (_url(element.url) case final url?)
                  DBadge.link(
                    variant: DBadgeVariant.outline,
                    borderColor: _color(element.color),
                    onPressed: () => openLink(context, url, siteUrl: siteUrl),
                    child: Text(element.title),
                  )
                else
                  _value(context, element.title, element.color),
                if (element.description case final description?)
                  Text(description),
              ],
            ),
          },
      ],
    );
  }

  Future<void> _interact(
    BuildContext context,
    ChatController chat,
    String actionId,
  ) async {
    final session = chat.captureSession(siteUrl);
    final error = await chat.interactWithMessage(siteUrl, message.id, actionId);
    if (error != null &&
        context.mounted &&
        session.isCurrent &&
        chat.canInteractWithBlock(siteUrl, message, actionId)) {
      DToast.show(context, error, type: DToastType.error);
    }
  }

  String? _url(String? value) {
    final parsed = value == null ? null : Uri.tryParse(value);
    if (parsed == null) return null;
    if (!parsed.hasScheme &&
        value!.startsWith('/') &&
        !value.startsWith('//')) {
      return value;
    }
    return (parsed.scheme == 'https' || parsed.scheme == 'http') &&
            parsed.host.isNotEmpty &&
            parsed.userInfo.isEmpty
        ? value
        : null;
  }

  Color? _color(String? value) {
    var hex = value?.replaceFirst('#', '');
    if (hex == null ||
        !RegExp(r'^(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$').hasMatch(hex)) {
      return null;
    }
    if (hex.length == 3) hex = hex.split('').map((part) => '$part$part').join();
    return Color(0xff000000 | int.parse(hex, radix: 16));
  }
}
