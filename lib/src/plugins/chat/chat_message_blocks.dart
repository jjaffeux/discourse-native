import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/foundation.dart';

sealed class ChatBlock {
  const ChatBlock(this.elements);
  final List<ChatBlockElement> elements;

  static List<ChatBlock> parse(Object? value) => List.unmodifiable([
    for (final entry in jsonObjects(value).take(20))
      ?_parse(entry),
  ]);

  static ChatBlock? _parse(Map<String, dynamic> json) {
    final elements = ChatBlockElement.parse(json['elements']);
    return switch (json['type']) {
      'actions' => ChatActionsBlock(elements),
      'informative' => ChatInformativeBlock(elements),
      'confirmation' => ChatConfirmationBlock(
        elements: elements,
        title: jsonString(json['title']),
        cookedTitle: jsonText(json['cooked_title']),
        cookedQuestion: jsonText(json['cooked_question']),
        cookedStatus: jsonText(json['cooked_status']),
        cookedError: jsonText(json['cooked_error']),
        showDescription: json['show_description'] != false,
        descriptionLabel: jsonText(json['description_label']),
        changes: List.unmodifiable([
          for (final change in jsonObjects(json['changes']).take(50))
            (
              label: jsonString(change['label']),
              before: jsonString(change['before']),
              after: jsonString(change['after']),
              beforeColor: jsonText(change['before_color']),
              afterColor: jsonText(change['after_color']),
            ),
        ]),
        parameters: List.unmodifiable([
          for (final parameter in jsonObjects(json['parameters']).take(50))
            (
              label: jsonString(parameter['label']),
              value: jsonString(parameter['value']),
              color: jsonText(parameter['color']),
            ),
        ]),
      ),
      _ => null,
    };
  }
}

final class ChatActionsBlock extends ChatBlock {
  const ChatActionsBlock(super.elements);
  @override
  bool operator ==(Object other) =>
      other is ChatActionsBlock && listEquals(elements, other.elements);
  @override
  int get hashCode => Object.hash(ChatActionsBlock, Object.hashAll(elements));
}

final class ChatInformativeBlock extends ChatBlock {
  const ChatInformativeBlock(super.elements);
  @override
  bool operator ==(Object other) =>
      other is ChatInformativeBlock && listEquals(elements, other.elements);
  @override
  int get hashCode =>
      Object.hash(ChatInformativeBlock, Object.hashAll(elements));
}

final class ChatConfirmationBlock extends ChatBlock {
  const ChatConfirmationBlock({
    required List<ChatBlockElement> elements,
    required this.title,
    this.cookedTitle,
    this.cookedQuestion,
    this.cookedStatus,
    this.cookedError,
    this.showDescription = true,
    this.descriptionLabel,
    this.changes = const [],
    this.parameters = const [],
  }) : super(elements);
  final String title;
  final String? cookedTitle,
      cookedQuestion,
      cookedStatus,
      cookedError,
      descriptionLabel;
  final bool showDescription;
  final List<ChatBlockChange> changes;
  final List<ChatBlockParameter> parameters;
  @override
  bool operator ==(Object other) =>
      other is ChatConfirmationBlock &&
      title == other.title &&
      cookedTitle == other.cookedTitle &&
      cookedQuestion == other.cookedQuestion &&
      cookedStatus == other.cookedStatus &&
      cookedError == other.cookedError &&
      showDescription == other.showDescription &&
      descriptionLabel == other.descriptionLabel &&
      listEquals(changes, other.changes) &&
      listEquals(parameters, other.parameters) &&
      listEquals(elements, other.elements);
  @override
  int get hashCode => Object.hash(
    title,
    cookedTitle,
    cookedQuestion,
    cookedStatus,
    cookedError,
    showDescription,
    descriptionLabel,
    Object.hashAll(changes),
    Object.hashAll(parameters),
    Object.hashAll(elements),
  );
}

typedef ChatBlockChange = ({
  String label,
  String before,
  String after,
  String? beforeColor,
  String? afterColor,
});
typedef ChatBlockParameter = ({String label, String value, String? color});

sealed class ChatBlockElement {
  const ChatBlockElement();
  static List<ChatBlockElement> parse(Object? value) => List.unmodifiable([
    for (final json in jsonObjects(value).take(20))
      ?_parse(json),
  ]);
  static ChatBlockElement? _parse(Map<String, dynamic> json) =>
      switch (json['type']) {
        'button' when jsonText(json['action_id']) != null => ChatBlockButton(
          actionId: jsonString(json['action_id']),
          label: jsonString(jsonObject(json['text'])['text']),
          style: jsonText(json['style']),
          icon: jsonText(json['icon']),
        ),
        'category' => ChatBlockCategory(
          title: jsonString(json['title']),
          description: jsonText(json['description']),
          color: jsonText(json['color']),
          url: jsonText(json['url']),
          parentName: jsonText(json['parent_name']),
          parentColor: jsonText(json['parent_color']),
        ),
        _ => null,
      };
}

final class ChatBlockButton extends ChatBlockElement {
  const ChatBlockButton({
    required this.actionId,
    required this.label,
    this.style,
    this.icon,
  });
  final String actionId, label;
  final String? style, icon;
  @override
  bool operator ==(Object other) =>
      other is ChatBlockButton &&
      actionId == other.actionId &&
      label == other.label &&
      style == other.style &&
      icon == other.icon;
  @override
  int get hashCode => Object.hash(actionId, label, style, icon);
}

final class ChatBlockCategory extends ChatBlockElement {
  const ChatBlockCategory({
    required this.title,
    this.description,
    this.color,
    this.url,
    this.parentName,
    this.parentColor,
  });
  final String title;
  final String? description, color, url, parentName, parentColor;
  @override
  bool operator ==(Object other) =>
      other is ChatBlockCategory &&
      title == other.title &&
      description == other.description &&
      color == other.color &&
      url == other.url &&
      parentName == other.parentName &&
      parentColor == other.parentColor;
  @override
  int get hashCode =>
      Object.hash(title, description, color, url, parentName, parentColor);
}
