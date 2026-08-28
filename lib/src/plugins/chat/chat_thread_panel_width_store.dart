import 'package:shared_preferences/shared_preferences.dart';

import '../../data/serial_operation_queue.dart';
import '../../data/store_diagnostics.dart';

abstract interface class ChatThreadPanelWidthPersistence {
  Future<double?> readWidth();

  Future<bool> writeWidth(double width);
}

final class SharedPreferencesChatThreadPanelWidthPersistence
    implements ChatThreadPanelWidthPersistence {
  const SharedPreferencesChatThreadPanelWidthPersistence();

  @override
  Future<double?> readWidth() async => (await SharedPreferences.getInstance())
      .getDouble(ChatThreadPanelWidthStore.storageKey);

  @override
  Future<bool> writeWidth(double width) async =>
      (await SharedPreferences.getInstance()).setDouble(
        ChatThreadPanelWidthStore.storageKey,
        width,
      );
}

/// Optional global presentation preference for the expanded thread pane.
final class ChatThreadPanelWidthStore {
  const ChatThreadPanelWidthStore({
    ChatThreadPanelWidthPersistence? persistence,
  }) : _persistence =
           persistence ??
           const SharedPreferencesChatThreadPanelWidthPersistence();

  static const String storageKey = 'discourse_native.chat_thread_panel_width';
  static final SerialOperationQueue _operations = SerialOperationQueue();

  final ChatThreadPanelWidthPersistence _persistence;

  Future<double?> read() => _operations.run(
    owner: _persistence,
    key: storageKey,
    operation: () async {
      try {
        final width = await _persistence.readWidth();
        return width != null && width.isFinite && width > 0 ? width : null;
      } catch (error, stackTrace) {
        reportStorageFailure(error, stackTrace, 'chatThreadPanel.readWidth');
        return null;
      }
    },
  );

  Future<void> write(double width) {
    if (!width.isFinite || width <= 0) return Future.value();
    return _operations.run<void>(
      owner: _persistence,
      key: storageKey,
      operation: () async {
        try {
          if (!await _persistence.writeWidth(width)) {
            throw StateError('Could not persist the thread panel width.');
          }
        } catch (error, stackTrace) {
          reportStorageFailure(error, stackTrace, 'chatThreadPanel.writeWidth');
        }
      },
    );
  }
}
