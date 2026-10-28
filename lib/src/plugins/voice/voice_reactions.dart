// Public callbacks describe the call boundary, rather than expose storage.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/foundation.dart';

final class VoiceReactionSettings {
  const VoiceReactionSettings({
    required this.emojis,
    this.allowAnyEmoji = false,
  });

  factory VoiceReactionSettings.fromJson(Map<String, dynamic> site) {
    final raw = site['live_reaction_emojis'] ?? site['voice_reaction_emojis'];
    return VoiceReactionSettings(
      emojis: List.unmodifiable({
        if (raw is List)
          for (final value in raw)
            if (value is String && isVoiceReactionCode(value)) value,
      }),
      allowAnyEmoji:
          site['live_reactions_allow_any_emoji'] == true ||
          site['voice_reactions_allow_any_emoji'] == true,
    );
  }

  final List<String> emojis;
  final bool allowAnyEmoji;
  bool get supported => emojis.isNotEmpty || allowAnyEmoji;
  bool allows(String emoji) =>
      emojis.contains(emoji) || (allowAnyEmoji && isVoiceReactionCode(emoji));
}

bool isVoiceReactionCode(String value) =>
    RegExp(r'^[a-z0-9_+\-]{1,100}(?::t[1-6])?$').hasMatch(value);

@immutable
final class VoiceReaction {
  const VoiceReaction({
    required this.id,
    required this.userId,
    required this.username,
    required this.emoji,
  });

  final int id;
  final int userId;
  final String username;
  final String emoji;
}

/// Ephemeral reactions owned by one joined call. Expiry uses timers so hidden
/// views cannot replay an animation backlog when they become visible again.
final class VoiceReactionSession extends ChangeNotifier {
  VoiceReactionSession({
    required this.siteUrl,
    required this.roomId,
    required this.userId,
    required this.username,
    required bool Function() isCurrent,
    required Future<VoiceReactionSettings?> Function() load,
    required Future<void> Function(String emoji) send,
    void Function(Object error)? onError,
    Timer Function(Duration, void Function())? timerFactory,
  }) : _isCurrent = isCurrent,
       _load = load,
       _send = send,
       _onError = onError,
       _timerFactory = timerFactory ?? Timer.new;

  static const lifetime = Duration(seconds: 4);
  static const maximumVisible = 40;
  final String siteUrl;
  final int roomId;
  final int userId;
  final String username;
  final bool Function() _isCurrent;
  final Future<VoiceReactionSettings?> Function() _load;
  final Future<void> Function(String emoji) _send;
  final void Function(Object error)? _onError;
  final Timer Function(Duration, void Function()) _timerFactory;
  final Map<int, Timer> _timers = {};
  final List<VoiceReaction> _reactions = [];
  VoiceReactionSettings? _settings;
  Future<void>? _loading;
  Timer? _cooldown;
  Timer? _settingsRetry;
  int _loadAttempts = 0;
  bool _disposed = false;
  int _nextId = 0;

  bool get isCurrent => !_disposed && _isCurrent();
  VoiceReactionSettings? get settings => _settings;
  bool get rateLimited => _cooldown != null;
  bool get canSend => isCurrent && !rateLimited && _settings?.supported == true;
  List<VoiceReaction> get reactions => List.unmodifiable(_reactions);

  Future<void> load() => _loading ??= _loadSettings();

  Future<void> _loadSettings() async {
    _loadAttempts++;
    try {
      final settings = await _load();
      if (!isCurrent) return;
      _settings = settings;
      notifyListeners();
    } catch (_) {
      // Older servers have no reaction capability. Loading it must never
      // interrupt a call; reopening the picker may retry a failed read.
      _loading = null;
    } finally {
      if (_settings == null) {
        _loading = null;
        if (isCurrent && _loadAttempts < 3) {
          _settingsRetry?.cancel();
          _settingsRetry = _timerFactory(
            Duration(seconds: _loadAttempts * 2),
            () {
              _settingsRetry = null;
              if (isCurrent) unawaited(load());
            },
          );
        }
      }
    }
  }

  Future<void> send(String emoji) async {
    if (!canSend || !_settings!.allows(emoji)) return;
    final optimistic = _add(userId, username, emoji);
    try {
      await _send(emoji);
    } catch (error) {
      if (!isCurrent) return;
      _remove(optimistic.id);
      if (error is WriteException && error.statusCode == 429) {
        _cooldown?.cancel();
        final wait = error.retryAfter ?? const Duration(seconds: 1);
        _cooldown = _timerFactory(
          wait < const Duration(seconds: 1) ? const Duration(seconds: 1) : wait,
          () {
            _cooldown = null;
            if (isCurrent) notifyListeners();
          },
        );
        notifyListeners();
      } else {
        _onError?.call(error);
      }
    }
  }

  void receive(Map<String, dynamic> payload) {
    if (!isCurrent) return;
    final sender = jsonIntOrNull(payload['user_id']);
    final name = jsonText(payload['username']);
    final emoji = jsonText(payload['emoji']);
    if (sender == null ||
        sender == userId ||
        name == null ||
        emoji == null ||
        !isVoiceReactionCode(emoji)) {
      return;
    }
    _add(sender, name, emoji);
  }

  VoiceReaction _add(int sender, String name, String emoji) {
    final reaction = VoiceReaction(
      id: ++_nextId,
      userId: sender,
      username: name,
      emoji: emoji,
    );
    while (_reactions.length >= maximumVisible) {
      final dropped = _reactions.removeAt(0);
      _timers.remove(dropped.id)?.cancel();
    }
    _reactions.add(reaction);
    _timers[reaction.id] = _timerFactory(lifetime, () => _remove(reaction.id));
    notifyListeners();
    return reaction;
  }

  void _remove(int id) {
    _timers.remove(id)?.cancel();
    _reactions.removeWhere((reaction) => reaction.id == id);
    if (isCurrent) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cooldown?.cancel();
    _settingsRetry?.cancel();
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _reactions.clear();
    super.dispose();
  }
}
