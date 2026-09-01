import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../../data/serial_operation_queue.dart';
import '../../data/store_diagnostics.dart';

enum ChatPreferredDisplayMode { drawer, fullPage }

typedef ChatDrawerSize = ({double width, double height});

abstract interface class ChatDrawerPreferencesPersistence {
  Future<String?> readPreferredDisplayMode();

  Future<({double? width, double? height})> readDrawerSize();

  Future<bool> writePreferredDisplayMode(String value);

  Future<bool> writeDrawerSize({required double width, required double height});
}

final class SharedPreferencesChatDrawerPreferencesPersistence
    implements ChatDrawerPreferencesPersistence {
  const SharedPreferencesChatDrawerPreferencesPersistence();

  @override
  Future<String?> readPreferredDisplayMode() async =>
      (await SharedPreferences.getInstance()).getString(
        ChatDrawerPreferencesStore.preferredDisplayModeStorageKey,
      );

  @override
  Future<({double? width, double? height})> readDrawerSize() async {
    final preferences = await SharedPreferences.getInstance();
    return (
      width: preferences.getDouble(
        ChatDrawerPreferencesStore.drawerWidthStorageKey,
      ),
      height: preferences.getDouble(
        ChatDrawerPreferencesStore.drawerHeightStorageKey,
      ),
    );
  }

  @override
  Future<bool> writePreferredDisplayMode(String value) async =>
      (await SharedPreferences.getInstance()).setString(
        ChatDrawerPreferencesStore.preferredDisplayModeStorageKey,
        value,
      );

  @override
  Future<bool> writeDrawerSize({
    required double width,
    required double height,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await Future.wait<bool>([
      preferences.setDouble(
        ChatDrawerPreferencesStore.drawerWidthStorageKey,
        width,
      ),
      preferences.setDouble(
        ChatDrawerPreferencesStore.drawerHeightStorageKey,
        height,
      ),
    ]);
    return saved.every((result) => result);
  }
}

final class ChatDrawerPreferencesStore {
  const ChatDrawerPreferencesStore({
    ChatDrawerPreferencesPersistence? persistence,
  }) : _persistence =
           persistence ??
           const SharedPreferencesChatDrawerPreferencesPersistence();

  static const double defaultWidth = 400;
  static const double defaultHeight = 530;
  static const double minimumWidth = 250;
  static const double minimumHeight = 300;

  static const String preferredDisplayModeStorageKey =
      'discourse_chat_preferred_mode';
  static const String drawerWidthStorageKey =
      'discourse_chat_drawer_size_width';
  static const String drawerHeightStorageKey =
      'discourse_chat_drawer_size_height';

  static const String _drawerSizeOperationKey = 'discourse_chat_drawer_size';
  static final SerialOperationQueue _operations = SerialOperationQueue();

  final ChatDrawerPreferencesPersistence _persistence;

  Future<ChatPreferredDisplayMode?> readPreferredDisplayMode() =>
      _operations.run(
        owner: _persistence,
        key: preferredDisplayModeStorageKey,
        operation: () async {
          try {
            return _decodeDisplayMode(
              await _persistence.readPreferredDisplayMode(),
            );
          } catch (error, stackTrace) {
            reportStorageFailure(
              error,
              stackTrace,
              'chatDrawerPreferences.readPreferredDisplayMode',
            );
            return null;
          }
        },
      );

  Future<void> writePreferredDisplayMode(ChatPreferredDisplayMode mode) =>
      _operations.run<void>(
        owner: _persistence,
        key: preferredDisplayModeStorageKey,
        operation: () async {
          try {
            if (!await _persistence.writePreferredDisplayMode(
              _encodeDisplayMode(mode),
            )) {
              throw StateError(
                'Could not persist the preferred Chat display mode.',
              );
            }
          } catch (error, stackTrace) {
            reportStorageFailure(
              error,
              stackTrace,
              'chatDrawerPreferences.writePreferredDisplayMode',
            );
          }
        },
      );

  Future<ChatDrawerSize> readDrawerSize() => _operations.run(
    owner: _persistence,
    key: _drawerSizeOperationKey,
    operation: () async {
      try {
        final size = await _persistence.readDrawerSize();
        return (
          width: _restoreDimension(
            size.width,
            defaultValue: defaultWidth,
            minimumValue: minimumWidth,
          ),
          height: _restoreDimension(
            size.height,
            defaultValue: defaultHeight,
            minimumValue: minimumHeight,
          ),
        );
      } catch (error, stackTrace) {
        reportStorageFailure(
          error,
          stackTrace,
          'chatDrawerPreferences.readDrawerSize',
        );
        return (width: defaultWidth, height: defaultHeight);
      }
    },
  );

  Future<void> writeDrawerSize({
    required double width,
    required double height,
  }) {
    if (!width.isFinite || !height.isFinite) return Future.value();
    final clampedWidth = math.max(width, minimumWidth);
    final clampedHeight = math.max(height, minimumHeight);
    return _operations.run<void>(
      owner: _persistence,
      key: _drawerSizeOperationKey,
      operation: () async {
        try {
          if (!await _persistence.writeDrawerSize(
            width: clampedWidth,
            height: clampedHeight,
          )) {
            throw StateError('Could not persist the Chat drawer size.');
          }
        } catch (error, stackTrace) {
          reportStorageFailure(
            error,
            stackTrace,
            'chatDrawerPreferences.writeDrawerSize',
          );
        }
      },
    );
  }

  static ChatPreferredDisplayMode? _decodeDisplayMode(String? value) =>
      switch (value) {
        'DRAWER_CHAT' => ChatPreferredDisplayMode.drawer,
        'FULL_PAGE_CHAT' => ChatPreferredDisplayMode.fullPage,
        _ => null,
      };

  static String _encodeDisplayMode(ChatPreferredDisplayMode mode) =>
      switch (mode) {
        ChatPreferredDisplayMode.drawer => 'DRAWER_CHAT',
        ChatPreferredDisplayMode.fullPage => 'FULL_PAGE_CHAT',
      };

  static double _restoreDimension(
    double? value, {
    required double defaultValue,
    required double minimumValue,
  }) => value == null || !value.isFinite
      ? defaultValue
      : math.max(value, minimumValue);
}
