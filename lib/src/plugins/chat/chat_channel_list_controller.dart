import '../../foundation/frame_safe_notifier.dart';
import '../../models/chat_channel_list_preferences.dart';
import '../../models/discourse_user.dart';
import '../../models/user_preferences.dart';
import '../../plugin_api/core_plugin_host.dart';
import 'chat_plugin_data.dart';

typedef _Account = ({String siteUrl, int? id, String username});

/// Account-scoped, optimistic user options. Writes to different fields may
/// overlap; each completion can commit or roll back only its own field.
final class ChatChannelListController extends FrameSafeNotifier {
  ChatChannelListController({
    required this.requests,
    required this.currentUserFor,
    this.host,
  });

  final PluginRequestHost requests;
  final DiscourseUser? Function(String) currentUserFor;
  final PluginUserOptionsHost? host;
  final Map<_Account, _PreferencesState> _states = {};

  _Account? _account(String siteUrl) {
    final user = currentUserFor(siteUrl);
    return user == null
        ? null
        : (siteUrl: siteUrl, id: user.id, username: user.username);
  }

  _PreferencesState? _state(String siteUrl) {
    final account = _account(siteUrl);
    _states.removeWhere(
      (held, _) => held.siteUrl == siteUrl && held != account,
    );
    return account == null
        ? null
        : _states.putIfAbsent(account, _PreferencesState.new);
  }

  ChatChannelListPreferences preferencesFor(String siteUrl) {
    final source =
        currentUserFor(siteUrl)?.chatCurrentUser?.channelListPreferences ??
        const ChatChannelListPreferences();
    return ChatChannelListPreferences.read({
      for (final entry
          in (_state(siteUrl)?.overrides ?? <String, String>{}).entries)
        if (source.supports(entry.key)) entry.key: entry.value,
    }, fallback: source);
  }

  bool saving(String siteUrl, String field) =>
      _state(siteUrl)?.writes.containsKey(field) ?? false;

  String? errorFor(String siteUrl, ChatChannelListSection section) =>
      _state(siteUrl)?.errors[section.filterField] ??
      _state(siteUrl)?.errors[section.sortField];

  bool bypassed(String siteUrl, ChatChannelListSection section) =>
      _state(siteUrl)?.bypassed.contains(section) ?? false;

  void toggleFilter(String siteUrl, ChatChannelListSection section) {
    final state = _state(siteUrl);
    final preferences = preferencesFor(siteUrl);
    if (isDisposed ||
        state == null ||
        !preferences.supports(section.filterField) ||
        preferences.filterFor(section) == ChatChannelListFilter.all ||
        saving(siteUrl, section.filterField)) {
      return;
    }
    if (!state.bypassed.remove(section)) state.bypassed.add(section);
    notifySafely();
  }

  Future<bool> setFilter(
    String siteUrl,
    ChatChannelListSection section,
    ChatChannelListFilter filter,
  ) => _save(siteUrl, section, section.filterField, filter.wireValue);

  Future<bool> setSort(
    String siteUrl,
    ChatChannelListSection section,
    ChatChannelListSort sort,
  ) => _save(siteUrl, section, section.sortField, sort.wireValue);

  Future<bool> _save(
    String siteUrl,
    ChatChannelListSection section,
    String field,
    String value,
  ) async {
    final account = _account(siteUrl);
    final state = _state(siteUrl);
    final preferences = preferencesFor(siteUrl);
    if (isDisposed ||
        host == null ||
        account == null ||
        state == null ||
        !preferences.supports(field) ||
        state.writes.containsKey(field)) {
      return false;
    }
    final lease = requests.capture(siteUrl);
    final token = Object();
    final previous = preferences.wireValues[field]!;
    final wasBypassed = state.bypassed.contains(section);
    final isFilter = field == section.filterField;
    if (isFilter) state.bypassed.remove(section);
    state.errors.remove(field);
    if (previous == value) {
      notifySafely();
      return true;
    }
    state.writes[field] = token;
    state.overrides[field] = value;
    bool current() =>
        !isDisposed &&
        lease.isCurrent &&
        _account(siteUrl) == account &&
        identical(_states[account], state) &&
        identical(state.writes[field], token);
    notifySafely();
    try {
      final credentials = await requests.credentialsFor(siteUrl);
      if (!current()) return false;
      if (credentials.apiKey == null) throw StateError('Account disconnected');
      final result = await host!.api.updateUserPreferences(
        siteUrl: siteUrl,
        apiKey: credentials.apiKey!,
        clientId: credentials.clientId,
        username: account.username,
        values: {field: value},
        fallback: UserPreferences(
          username: account.username,
          channelListPreferences: preferences.withValue(field, value),
        ),
      );
      if (!current()) return false;
      final confirmed =
          result.channelListPreferences.wireValues[field] ?? value;
      host!.updateData(siteUrl, field, (data) {
        final held = data.chatCurrentUser;
        return held == null
            ? data
            : data.withValue(
                chatCurrentUserDataKey,
                held.withChannelListPreferences(
                  held.channelListPreferences.withValue(field, confirmed),
                ),
              );
      });
      state.overrides.remove(field);
      return true;
    } catch (_) {
      if (!current()) return false;
      state.overrides.remove(field);
      if (isFilter && wasBypassed) state.bypassed.add(section);
      state.errors[field] = 'Could not save channel preferences. Try again.';
      return false;
    } finally {
      if (current()) {
        state.writes.remove(field);
        notifySafely();
      }
    }
  }

  void refresh(String siteUrl) {
    _state(siteUrl);
    notifySafely();
  }

  void forget(String siteUrl) {
    _states.removeWhere((account, _) => account.siteUrl == siteUrl);
  }
}

final class _PreferencesState {
  final Map<String, String> overrides = {};
  final Map<String, Object> writes = {};
  final Map<String, String> errors = {};
  final Set<ChatChannelListSection> bypassed = {};
}
