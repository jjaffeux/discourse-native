import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'private_file_permissions.dart';

typedef PrivateFileResolver = FutureOr<File> Function();

/// A value produced synchronously while a private-file transaction is active.
///
/// Requiring this wrapper prevents an `async` callback from compiling: such a
/// callback could otherwise resume after the lock was released and silently
/// mutate state which will never be committed.
final class PrivateFileResult<R> {
  factory PrivateFileResult(R value) {
    if (value is Future<dynamic> || value is Stream<dynamic>) {
      throw StateError(
        'Private-file transaction results must be available synchronously.',
      );
    }
    return PrivateFileResult._(value);
  }

  const PrivateFileResult._(this.value);

  static const done = PrivateFileResult<void>._(null);

  final R value;
}

/// An owner-only document changed through complete, atomic replacements.
///
/// Every instance which resolves to the same absolute path shares an
/// in-process queue. An advisory sidecar lock extends that transaction across
/// isolates and app processes. Callers own their document format; this class
/// owns the filesystem protocol which keeps that format private and intact.
///
/// [read] and [update] callbacks are synchronous by design. Network, platform,
/// or interactive work must happen outside the transaction so it never holds
/// the file lock while waiting on another system or a person.
final class PrivateFileDocument<T> {
  factory PrivateFileDocument({
    required PrivateFileResolver target,
    required T Function() empty,
    required T Function(String contents) decode,
    required String Function(T value) encode,
  }) => PrivateFileDocument._(target, empty, decode, encode);

  PrivateFileDocument._(this._target, this._empty, this._decode, this._encode);

  final PrivateFileResolver _target;
  final T Function() _empty;
  final T Function(String contents) _decode;
  final String Function(T value) _encode;

  /// Inspects the current decoded value without replacing the document.
  ///
  /// The decoded value is transaction-local and must not escape through
  /// [inspect].
  Future<R> read<R>(PrivateFileResult<R> Function(T value) inspect) =>
      _transact((target) async => inspect(await _read(target)).value);

  /// Mutates the current value and atomically commits a changed encoding.
  ///
  /// Comparing canonical encodings makes a no-op update free and avoids a
  /// separate `markChanged` capability which a caller could forget to use.
  /// The codec must therefore be deterministic for equivalent values.
  Future<R> update<R>(PrivateFileResult<R> Function(T value) mutate) =>
      _transact((target) async {
        final value = await _read(target);
        final before = _encode(value);
        final result = mutate(value);
        final after = _encode(value);
        if (after != before) await _replace(target, after);
        return result.value;
      });

  Future<T> _read(File target) async {
    if (!await target.exists()) return _empty();
    restrictPrivateFile(target);
    return _decode(await target.readAsString());
  }

  Future<R> _transact<R>(Future<R> Function(File target) operation) async {
    final target = File((await _target()).absolute.path);
    final path = target.path;
    late final _PrivateFileCoordinator coordinator;
    coordinator = _coordinators.putIfAbsent(
      path,
      () => _PrivateFileCoordinator(
        target,
        onIdle: () {
          if (identical(_coordinators[path], coordinator)) {
            _coordinators.remove(path);
          }
        },
      ),
    );
    return coordinator.run(operation);
  }

  static final Map<String, _PrivateFileCoordinator> _coordinators = {};
}

/// Serializes complete-document transactions for one absolute path.
final class _PrivateFileCoordinator {
  _PrivateFileCoordinator(this.target, {required this.onIdle});

  final File target;
  final void Function() onIdle;
  Future<void> _tail = Future<void>.value();
  int _pending = 0;

  Future<T> run<T>(Future<T> Function(File target) operation) {
    _pending++;
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(
          await withPrivateAdvisoryFileLock(
            File('${target.path}.lock'),
            () async {
              await _removeAbandonedStages(target);
              return operation(target);
            },
          ),
        );
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      } finally {
        _pending--;
        if (_pending == 0) onIdle();
      }
    });
    return result.future;
  }
}

Future<void> _replace(File target, String contents) async {
  await ensurePrivateDirectory(target.parent);
  final temporary = File(
    '${target.path}.$pid.${_randomSuffix()}.private-document.tmp',
  );
  var ownsTemporary = false;
  try {
    await temporary.create(exclusive: true);
    ownsTemporary = true;
    // Restrict the empty file before the first sensitive byte is written.
    restrictPrivateFile(temporary);
    await temporary.writeAsString(contents, flush: true);
    await temporary.rename(target.path);
    restrictPrivateFile(target);
  } finally {
    if (ownsTemporary) {
      try {
        if (await temporary.exists()) await temporary.delete();
      } on FileSystemException {
        // Preserve the transaction failure. A private orphan is safer and
        // more diagnosable than replacing the error which prevented commit.
      }
    }
  }
}

Future<void> _removeAbandonedStages(File target) async {
  final ownedStage = RegExp(
    '^${RegExp.escape(target.path)}\\.\\d+\\.[0-9a-f]{32}'
    r'\.private-document\.tmp$',
  );
  await for (final entity in target.parent.list(followLinks: false)) {
    if (entity is! File || !ownedStage.hasMatch(entity.path)) continue;
    try {
      await entity.delete();
    } on FileSystemException {
      // The orphan is already owner-only. A cleanup failure must not make an
      // otherwise readable document unavailable.
    }
  }
}

String _randomSuffix() => List<int>.generate(
  16,
  (_) => _random.nextInt(256),
).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

final Random _random = Random.secure();
