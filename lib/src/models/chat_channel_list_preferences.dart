import 'package:flutter/foundation.dart';

enum ChatChannelListSection {
  channels(''),
  starred('_starred'),
  directMessages('_dms');

  const ChatChannelListSection(this.suffix);
  final String suffix;
  String get filterField => 'chat_channel_list_filter$suffix';
  String get sortField => 'chat_channel_list_sort$suffix';
}

enum ChatChannelListFilter {
  all('all', 'All'),
  active('active', 'Active in the last 30 days'),
  unread('unread', 'Unread'),
  mentions('mentions', 'Mentions');

  const ChatChannelListFilter(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static ChatChannelListFilter read(Object? value) =>
      values.where((filter) => filter.wireValue == value).firstOrNull ?? all;
}

enum ChatChannelListSort {
  alphabetical('alphabetical', 'Alphabetical'),
  recentActivity('recent_activity', 'Recent activity'),
  priority('priority', 'Priority');

  const ChatChannelListSort(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static ChatChannelListSort read(Object? value) =>
      values.where((sort) => sort.wireValue == value).firstOrNull ??
      alphabetical;
}

/// Only advertised fields are retained. Absence is an older-server capability
/// boundary, distinct from an advertised unknown value (core's default).
@immutable
final class ChatChannelListPreferences {
  const ChatChannelListPreferences() : _values = const {};

  ChatChannelListPreferences.read(
    Map<String, dynamic> options, {
    ChatChannelListPreferences fallback = const ChatChannelListPreferences(),
  }) : _values = Map.unmodifiable({
         ...fallback._values,
         for (final section in ChatChannelListSection.values) ...{
           if (options.containsKey(section.filterField))
             section.filterField: ChatChannelListFilter.read(
               options[section.filterField],
             ).wireValue,
           if (options.containsKey(section.sortField))
             section.sortField: ChatChannelListSort.read(
               options[section.sortField],
             ).wireValue,
         },
       });

  final Map<String, String> _values;
  Map<String, String> get wireValues => _values;
  bool supports(String field) => _values.containsKey(field);
  bool supportsSection(ChatChannelListSection section) =>
      supports(section.filterField) || supports(section.sortField);
  ChatChannelListFilter filterFor(ChatChannelListSection section) =>
      ChatChannelListFilter.read(_values[section.filterField]);
  ChatChannelListSort sortFor(ChatChannelListSection section) =>
      ChatChannelListSort.read(_values[section.sortField]);

  ChatChannelListPreferences withValue(String field, String value) =>
      ChatChannelListPreferences.read({field: value}, fallback: this);

  @override
  bool operator ==(Object other) =>
      other is ChatChannelListPreferences && mapEquals(_values, other._values);

  @override
  int get hashCode => Object.hashAll([
    for (final section in ChatChannelListSection.values) ...[
      _values[section.filterField],
      _values[section.sortField],
    ],
  ]);
}
