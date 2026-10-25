import 'package:discourse_native/discourse_plugin_sdk.dart';

const boardsPluginId = PluginId('boards');
const boardsSettingsKey = PluginDataKey<BoardsSettings>(
  owner: 'boards',
  name: 'settings',
);
const boardsMembershipKey = PluginDataKey<BoardMemberships>(
  owner: 'boards',
  name: 'topic',
);

Map<String, dynamic> boardObject(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};
int? boardInt(Object? value) => value is int && value > 0 ? value : null;
String boardText(Object? value) => value is String ? value : '';
List<int> boardIds(Object? value) => value is List
    ? List.unmodifiable(value.whereType<int>().where((id) => id > 0))
    : const [];
List<String> boardTexts(Object? value) =>
    value is List ? List.unmodifiable(value.whereType<String>()) : const [];

final class BoardsSettings {
  const BoardsSettings({this.enabled = false});
  final bool enabled;
}

final class BoardsSettingsCodec
    extends PluginDataPersistenceCodec<BoardsSettings> {
  const BoardsSettingsCodec();
  @override
  PluginDataKey<BoardsSettings> get key => boardsSettingsKey;
  @override
  BoardsSettings decode(Object? value) =>
      BoardsSettings(enabled: boardObject(value)['enabled'] == true);
  @override
  Object encode(BoardsSettings value) => {'enabled': value.enabled};
}

enum BoardCardKind { topic, standalone, unsupported }

enum BoardColumnOrder { priority, recency, unsupported }

final class BoardCard {
  BoardCard._(
    this.id,
    this.columnId,
    this.kind,
    this.title,
    this.notes,
    this.topicId,
    this.categoryId,
    this.tags,
    this.position,
    this.assignee,
    this.closed,
    this.imageUrl,
  );
  static BoardCard? decode(Object? value) {
    final json = boardObject(value);
    final id = boardInt(json['id']);
    final column = boardInt(json['column_id']);
    if (id == null || column == null) return null;
    final kind = switch (json['card_type']) {
      'topic' => BoardCardKind.topic,
      'floater' => BoardCardKind.standalone,
      _ => BoardCardKind.unsupported,
    };
    final topic = boardObject(json['topic']);
    if (kind == BoardCardKind.topic &&
        (boardInt(topic['id']) == null ||
            boardInt(topic['id']) != boardInt(json['topic_id']))) {
      return null;
    }
    final assignment = boardObject(
      kind == BoardCardKind.topic
          ? topic['assigned_to_user'] ?? topic['assigned_to_group']
          : json['assigned_to'],
    );
    return BoardCard._(
      id,
      column,
      kind,
      boardText(
        kind == BoardCardKind.topic
            ? topic['unicode_title'] ?? topic['title']
            : json['unicode_title'] ?? json['title'],
      ),
      boardText(json['notes']),
      boardInt(json['topic_id']),
      boardInt(topic['category_id']),
      kind == BoardCardKind.topic
          ? boardTexts(topic['tags'])
          : List.unmodifiable(
              (json['tags'] is List ? json['tags'] as List : const <Object?>[])
                  .map((tag) => boardText(boardObject(tag)['name']))
                  .where((tag) => tag.isNotEmpty),
            ),
      json['position'] is int ? json['position'] as int : 0,
      boardText(assignment['username'] ?? assignment['name']),
      topic['closed'] == true,
      boardText(topic['image_url']),
    );
  }

  final int id, columnId;
  final BoardCardKind kind;
  final String title, notes, assignee;
  final int? topicId, categoryId;
  final List<String> tags;
  final int position;
  final bool closed;
  final String imageUrl;
}

final class BoardColumn {
  BoardColumn._(
    this.id,
    this.title,
    this.order,
    this.cards,
    this.tagName,
    this.moveCategoryId,
    this.moveAssigned,
    this.moveStatus,
  );
  static BoardColumn? decode(Object? value) {
    final json = boardObject(value);
    final id = boardInt(json['id']);
    if (id == null) return null;
    return BoardColumn._(
      id,
      boardText(json['unicode_title'] ?? json['title']),
      switch (json['default_sort']) {
        'priority' || null => BoardColumnOrder.priority,
        'recency' => BoardColumnOrder.recency,
        _ => BoardColumnOrder.unsupported,
      },
      List.unmodifiable([
        for (final card
            in json['cards'] is List
                ? json['cards'] as List
                : const <Object?>[])
          if (BoardCard.decode(card) case final value?)
            if (value.columnId == id) value,
      ]),
      boardText(json['tag_name']),
      boardInt(json['move_to_category_id']),
      boardText(json['move_to_assigned']),
      boardText(json['move_to_status']),
    );
  }

  final int id;
  final String title;
  final BoardColumnOrder order;
  final List<BoardCard> cards;
  final String tagName, moveAssigned, moveStatus;
  final int? moveCategoryId;
}

final class BoardSnapshot {
  BoardSnapshot._(
    this.id,
    this.name,
    this.slug,
    this.archived,
    this.canWrite,
    this.canManage,
    this.requireConfirmation,
    this.columns,
    this.categoryIds,
    this.tagNames,
    this.showTags,
    this.showThumbnail,
    this.detailed,
  );
  static BoardSnapshot? decode(Object? value, {Object? columns}) {
    final json = boardObject(value);
    final id = boardInt(json['id']);
    if (id == null) return null;
    final rawColumns = columns ?? json['columns'];
    return BoardSnapshot._(
      id,
      boardText(json['unicode_name'] ?? json['name']),
      boardText(json['slug']),
      json['archived'] == true,
      json['can_write'] == true && json['archived'] != true,
      json['can_manage'] == true && json['archived'] != true,
      json['require_confirmation'] == true,
      List.unmodifiable([
        for (final raw in rawColumns is List ? rawColumns : const [])
          ?BoardColumn.decode(raw),
      ]),
      boardIds(json['category_ids']),
      boardTexts(json['tag_names']),
      json['show_tags'] == true,
      json['show_topic_thumbnail'] == true,
      json['card_style'] != 'simple',
    );
  }

  final int id;
  final String name, slug;
  final bool archived, canWrite, canManage, requireConfirmation;
  final bool showTags, showThumbnail, detailed;
  final List<BoardColumn> columns;
  final List<int> categoryIds;
  final List<String> tagNames;
  BoardCard? card(int id) => columns
      .expand((column) => column.cards)
      .where((card) => card.id == id)
      .firstOrNull;
  BoardColumn? column(int id) =>
      columns.where((column) => column.id == id).firstOrNull;
}

sealed class CardPlacement {
  const CardPlacement();
}

final class PlaceFirst extends CardPlacement {
  const PlaceFirst();
}

final class PlaceLast extends CardPlacement {
  const PlaceLast();
}

final class PlaceAfter extends CardPlacement {
  const PlaceAfter(this.cardId);
  final int cardId;
}

Map<String, Object?> boardPlacement(
  BoardSnapshot board,
  BoardCard card,
  BoardColumn target,
  CardPlacement placement,
) {
  if (target.order != BoardColumnOrder.priority) return const {};
  return switch (placement) {
    PlaceFirst() => {'after_card_id': null},
    PlaceAfter(:final cardId) => {'after_card_id': cardId},
    PlaceLast() when card.columnId == target.id => {
      if (target.cards.where((other) => other.id != card.id).lastOrNull
          case final last?)
        'after_card_id': last.id,
    },
    PlaceLast() => const {},
  };
}

final class BoardConstraintCheck {
  const BoardConstraintCheck({
    this.categoryIds = const [],
    this.tagNames = const [],
  });
  final List<int> categoryIds;
  final List<String> tagNames;
  bool get needsRepair => categoryIds.isNotEmpty || tagNames.isNotEmpty;
}

final class BoardRepair {
  const BoardRepair({this.categoryId, this.tagNames = const []});
  final int? categoryId;
  final List<String> tagNames;
  Map<String, Object?> get json => {
    if (categoryId != null) 'category_id': categoryId,
    if (tagNames.isNotEmpty) 'tag_names': tagNames,
  };
}

enum BoardWriteState { saved, refreshNeeded, cancelled, refused, unknown }

final class BoardWriteResult {
  const BoardWriteResult(this.state, [this.error]);
  final BoardWriteState state;
  final String? error;
  bool get saved =>
      state == BoardWriteState.saved || state == BoardWriteState.refreshNeeded;
}

final class BoardMemberships {
  const BoardMemberships(this.values);
  final List<BoardMembership> values;
  static BoardMemberships decode(Object? value) => BoardMemberships(
    List.unmodifiable([
      for (final raw in value is List ? value : const [])
        for (final card
            in boardObject(raw)['cards'] is List
                ? boardObject(raw)['cards'] as List
                : const <Object?>[])
          ?BoardMembership.decode({
            ...boardObject(raw),
            'cards': [card],
          }),
    ]),
  );
}

final class BoardMembership {
  const BoardMembership(
    this.boardId,
    this.name,
    this.slug,
    this.cardId,
    this.columnTitle,
  );
  final int boardId;
  final String name, slug, columnTitle;
  final int? cardId;
  static BoardMembership? decode(Object? value) {
    final json = boardObject(value);
    final id = boardInt(json['board_id']);
    if (id == null) return null;
    final cards = json['cards'] is List
        ? json['cards'] as List
        : const <Object?>[];
    final first = boardObject(cards.firstOrNull);
    return BoardMembership(
      id,
      boardText(json['unicode_board_name'] ?? json['board_name']),
      boardText(json['board_slug']),
      boardInt(first['card_id']),
      boardText(first['unicode_column_title'] ?? first['column_title']),
    );
  }
}

final class BoardMembershipCodec
    extends PluginDataPersistenceCodec<BoardMemberships> {
  const BoardMembershipCodec();
  @override
  PluginDataKey<BoardMemberships> get key => boardsMembershipKey;
  @override
  BoardMemberships decode(Object? value) => BoardMemberships.decode(value);
  @override
  Object encode(BoardMemberships value) => [
    for (final item in value.values)
      {
        'board_id': item.boardId,
        'board_name': item.name,
        'board_slug': item.slug,
        'cards': [
          {'card_id': item.cardId, 'column_title': item.columnTitle},
        ],
      },
  ];
}
