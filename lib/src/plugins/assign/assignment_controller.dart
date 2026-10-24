// ignore_for_file: prefer_initializing_formals

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

import 'assign_api.dart';
import 'assignment.dart';
import 'assignment_write_result.dart';

export 'assignment_write_result.dart';

typedef AssignmentPermissionReader =
    bool Function(String siteUrl, AssignmentTarget target);
typedef AssignmentPermissionSnapshot = ({
  bool valid,
  bool? recordPermission,
  bool freshAccountCanAssign,
});
typedef AssignmentPermissionSnapshotReader =
    AssignmentPermissionSnapshot Function(
      String siteUrl,
      AssignmentTarget target,
    );
typedef AssignmentTopicReloader =
    Future<void> Function(String siteUrl, int topicId);
typedef AssignmentFallbackInvalidator = void Function(String siteUrl);
typedef AssignmentStatusOptions = ({bool enabled, List<String> values});
typedef AssignmentStatusOptionsReader =
    AssignmentStatusOptions Function(String siteUrl);

/// Binds an editor to its opening target and account without exposing the lease.
final class AssignmentPickerSession {
  const AssignmentPickerSession._({
    required this.siteUrl,
    required this.target,
    required this._owner,
    required this._lease,
  });

  final String siteUrl;
  final AssignmentTarget target;
  final AssignmentController _owner;
  final PluginSiteLease _lease;
}

final class AssignmentRestorePermit {
  AssignmentRestorePermit._({
    required this._owner,
    required this.siteUrl,
    required this.target,
    required Assignment assignment,
    required PluginSiteLease lease,
    required Object session,
    required this.expiresAt,
  }) : _assignment = assignment,
       _lease = lease,
       _session = session;

  final AssignmentController _owner;
  final String siteUrl;
  final AssignmentTarget target;
  final Assignment _assignment;
  final PluginSiteLease _lease;
  final Object _session;
  final DateTime expiresAt;

  bool _take(AssignmentController owner) {
    final key = (siteUrl: siteUrl, type: target.type, id: target.id);
    if (!identical(owner._restorePermits[key], this) ||
        !identical(_owner, owner) ||
        !_lease.isCurrent ||
        !identical(owner._restoreSessions[siteUrl], _session) ||
        !DateTime.now().isBefore(expiresAt)) {
      return false;
    }
    owner._restorePermits.remove(key);
    return true;
  }
}

/// Checks target-scoped permission again at the command boundary. A missing
/// legacy answer may fall back only to a freshly fetched session capability.
class AssignmentController extends FrameSafeNotifier
    implements PluginCurrentUserObserver {
  AssignmentController({
    required this.api,
    required PluginRequestHost requests,
    AssignmentPermissionReader? canAssign,
    AssignmentPermissionSnapshotReader? permissionSnapshot,
    AssignmentStatusOptionsReader? statusOptionsReader,
    required AssignmentTopicReloader reloadTopic,

    AssignmentFallbackInvalidator? invalidateLegacyFallback,
  }) : assert(canAssign != null || permissionSnapshot != null),
       _requests = requests,
       _legacyCanAssign = canAssign,
       _permissionSnapshot = permissionSnapshot,
       _statusOptionsReader = statusOptionsReader,
       _reloadTopic = reloadTopic,
       _legacyInvalidator = invalidateLegacyFallback;

  final AssignApi api;
  final PluginRequestHost _requests;
  final AssignmentPermissionReader? _legacyCanAssign;
  final AssignmentPermissionSnapshotReader? _permissionSnapshot;

  final AssignmentStatusOptionsReader? _statusOptionsReader;
  final AssignmentTopicReloader _reloadTopic;
  final AssignmentFallbackInvalidator? _legacyInvalidator;

  final Map<({String siteUrl, AssignmentTarget target}), Object> _writes = {};
  final Map<String, Object> _restoreSessions = {};
  final Map<({String siteUrl, AssignmentTargetType type, int id}), Object>
  _restorePermits = {};
  final Set<String> _legacyFallbackUnavailable = {};
  final Map<String, _PermissionChanges> _permissionChanges = {};

  static String get _targetUnavailable =>
      appL10n.thisAssignmentTargetIsNoLongerAvailable;
  static const _restorePermitDuration = Duration(seconds: 10);

  bool isWriting(String siteUrl, AssignmentTarget target) =>
      _writes.containsKey((siteUrl: siteUrl, target: target));

  /// Notifies when what [canAssign] answers for this site may have moved
  /// through state held here rather than in the host's records: its legacy
  /// fallback was withdrawn or restored. A post's menu and assignment row read
  /// nothing else from this controller, so they listen here rather than to the
  /// controller, which also notifies at the start and end of every write; a
  /// topic draws one of each per post.
  ///
  /// One per site for the controller's lifetime: sites are few, and a
  /// retained row may still hold it after its site is forgotten.
  Listenable permissionChanges(String siteUrl) =>
      _permissionChanges[siteUrl] ??= _PermissionChanges();

  /// The controller itself still notifies, for consumers that also follow
  /// writes: the topic's assignment properties.
  void _permissionChanged(String siteUrl) {
    _permissionChanges[siteUrl]?.changed();
    notifySafely();
  }

  bool canAssign(String siteUrl, AssignmentTarget target) {
    final snapshot = _permissionSnapshot?.call(siteUrl, target);
    if (snapshot != null) {
      if (!snapshot.valid) return false;
      return snapshot.recordPermission ??
          (!_legacyFallbackUnavailable.contains(siteUrl) &&
              snapshot.freshAccountCanAssign);
    }
    return _legacyCanAssign?.call(siteUrl, target) ?? false;
  }

  AssignmentStatusOptions statusOptions(String siteUrl) =>
      _statusOptionsReader?.call(siteUrl) ?? (enabled: false, values: const []);

  AssignmentPickerSession beginPicker(
    String siteUrl,
    AssignmentTarget target,
  ) => AssignmentPickerSession._(
    siteUrl: siteUrl,
    target: target,
    owner: this,
    lease: _requests.capture(siteUrl),
  );

  bool isPickerCurrent(AssignmentPickerSession session) =>
      identical(session._owner, this) && _isCurrent(session._lease);

  void _invalidateLegacyFallback(String siteUrl) {
    final changed = _legacyFallbackUnavailable.add(siteUrl);
    _legacyInvalidator?.call(siteUrl);
    if (changed) _permissionChanged(siteUrl);
  }

  @override
  void pluginCurrentUserRefreshed(String siteUrl) {
    if (_legacyFallbackUnavailable.remove(siteUrl)) _permissionChanged(siteUrl);
  }

  void forget(String siteUrl) {
    final before = _writes.length;
    _writes.removeWhere((key, _) => key.siteUrl == siteUrl);
    _restoreSessions.remove(siteUrl);
    _restorePermits.removeWhere((key, _) => key.siteUrl == siteUrl);
    if (_legacyFallbackUnavailable.remove(siteUrl)) {
      _permissionChanged(siteUrl);
    } else if (_writes.length != before) {
      notifySafely();
    }
  }

  Future<AssignmentSuggestions> suggestions(
    String siteUrl,
    AssignmentTarget target,
  ) => _lookup(
    siteUrl,
    target,
    (session) => api.suggestions(
      siteUrl: siteUrl,
      apiKey: session.apiKey!,
      clientId: session.clientId,
      target: target,
    ),
  );

  Future<List<AssignmentAssignee>> search(
    String siteUrl,
    AssignmentTarget target,
    AssignmentSuggestions suggestions,
    String term,
  ) => _lookup(
    siteUrl,
    target,
    (session) => api.searchAssignees(
      siteUrl: siteUrl,
      apiKey: session.apiKey!,
      clientId: session.clientId,
      term: term.trim(),
      suggestions: suggestions,
    ),
  );

  Future<AssignmentWriteResult> assign(
    String siteUrl,
    AssignmentTarget target,
    AssignmentAssignee assignee, {
    String? note,
    String? status,
  }) => _mutate(siteUrl, target, (session) {
    return api.assign(
      siteUrl: siteUrl,
      apiKey: session.apiKey!,
      clientId: session.clientId,
      target: target,
      assignee: assignee,
      note: note,
      status: status,
    );
  });

  Future<AssignmentWriteResult> unassign(
    String siteUrl,
    AssignmentTarget target,
  ) => _mutate(siteUrl, target, (session) {
    return api.unassign(
      siteUrl: siteUrl,
      apiKey: session.apiKey!,
      clientId: session.clientId,
      target: target,
    );
  });

  Future<({AssignmentWriteResult outcome, AssignmentRestorePermit? permit})>
  unassignForUndo(
    String siteUrl,
    AssignmentTarget target,
    Assignment assignment,
  ) async {
    final lease = _requests.capture(siteUrl);
    final session = _restoreSessions.putIfAbsent(siteUrl, Object.new);
    final key = (siteUrl: siteUrl, type: target.type, id: target.id);
    final candidate = Object();
    final outcome = await _mutate(
      siteUrl,
      target,
      (session) => api.unassign(
        siteUrl: siteUrl,
        apiKey: session.apiKey!,
        clientId: session.clientId,
        target: target,
      ),
      onAccepted: () => _restorePermits[key] = candidate,
    );
    if (!outcome.accepted ||
        !_isCurrent(lease) ||
        !identical(_restoreSessions[siteUrl], session) ||
        !identical(_restorePermits[key], candidate)) {
      if (identical(_restorePermits[key], candidate)) {
        _restorePermits.remove(key);
      }
      return (outcome: outcome, permit: null);
    }
    final now = DateTime.now();
    _restorePermits.removeWhere(
      (_, value) =>
          value is AssignmentRestorePermit &&
          (!value._lease.isCurrent || !now.isBefore(value.expiresAt)),
    );
    final permit = AssignmentRestorePermit._(
      owner: this,
      siteUrl: siteUrl,
      target: target,
      assignment: assignment,
      lease: lease,
      session: session,
      expiresAt: now.add(_restorePermitDuration),
    );
    _restorePermits[key] = permit;
    return (outcome: outcome, permit: permit);
  }

  Future<AssignmentWriteResult> restoreAssignment(
    AssignmentRestorePermit permit,
  ) {
    if (!permit._take(this)) {
      return Future.value(const AssignmentWriteResult.inactive());
    }
    return _mutate(
      permit.siteUrl,
      permit.target,
      (session) => api.assign(
        siteUrl: permit.siteUrl,
        apiKey: session.apiKey!,
        clientId: session.clientId,
        target: permit.target,
        assignee: permit._assignment.assignee,
        note: permit._assignment.note,
        status: permit._assignment.status,
        shouldNotify: false,
      ),
      permissionAlreadyEstablished: true,
    );
  }

  Future<AssignmentWriteResult> _mutate(
    String siteUrl,
    AssignmentTarget target,
    Future<void> Function(PluginRequestCredentials session) write, {
    bool permissionAlreadyEstablished = false,
    VoidCallback? onAccepted,
  }) async {
    if (isDisposed) return const AssignmentWriteResult.inactive();
    if (!permissionAlreadyEstablished && !canAssign(siteUrl, target)) {
      return const AssignmentWriteResult.refused(
        WriteException(WriteFailure.forbidden),
      );
    }

    final key = (siteUrl: siteUrl, target: target);
    if (_writes.containsKey(key)) return const AssignmentWriteResult.busy();
    final token = Object();
    final lease = _requests.capture(siteUrl);
    _writes[key] = token;
    notifySafely();

    bool current() => _isCurrent(lease) && identical(_writes[key], token);

    try {
      final PluginRequestCredentials session;
      try {
        session = await _session(siteUrl, lease: lease);
      } on WriteException catch (error) {
        if (!current()) return const AssignmentWriteResult.inactive();
        return error.failure == WriteFailure.unreachable
            ? AssignmentWriteResult.notSent(error)
            : AssignmentWriteResult.refused(error);
      }
      if (!current()) return const AssignmentWriteResult.inactive();
      var dispatched = false;
      try {
        await session.run(() {
          dispatched = true;
          return write(session);
        });
      } on WriteException catch (error) {
        if (!dispatched || error.notSent) {
          return AssignmentWriteResult.notSent(error);
        }
        if (error.statusCode == 404) {
          if (current()) {
            _invalidateLegacyFallback(siteUrl);
            await _reconcileUnavailable(siteUrl, target.topicId);
          }
          return const AssignmentWriteResult.targetUnavailable();
        }
        return error.failure == WriteFailure.unreachable
            ? AssignmentWriteResult.uncertain(error)
            : AssignmentWriteResult.refused(error);
      } catch (error, stackTrace) {
        final failure = WriteException(
          WriteFailure.unreachable,
          notSent: !dispatched,
          cause: error,
          causeStackTrace: stackTrace,
        );
        return dispatched
            ? AssignmentWriteResult.uncertain(failure)
            : AssignmentWriteResult.notSent(failure);
      }
      if (!current()) return const AssignmentWriteResult.acceptedRetired();
      _restorePermits.remove((
        siteUrl: siteUrl,
        type: target.type,
        id: target.id,
      ));
      onAccepted?.call();

      try {
        // Assign returns no assignment snapshot and can also change tracking.
        await _reloadTopic(siteUrl, target.topicId);
      } catch (error, stackTrace) {
        if (!current()) return const AssignmentWriteResult.acceptedRetired();
        return AssignmentWriteResult.acceptedRefreshFailed(
          error is WriteException
              ? error
              : WriteException(
                  WriteFailure.unreachable,
                  cause: error,
                  causeStackTrace: stackTrace,
                ),
        );
      }
      return current()
          ? const AssignmentWriteResult.applied()
          : const AssignmentWriteResult.acceptedRetired();
    } finally {
      if (identical(_writes[key], token)) {
        _writes.remove(key);
        notifySafely();
      }
    }
  }

  void _requirePermission(String siteUrl, AssignmentTarget target) {
    if (isDisposed || !canAssign(siteUrl, target)) {
      throw const WriteException(WriteFailure.forbidden);
    }
  }

  Future<T> _lookup<T>(
    String siteUrl,
    AssignmentTarget target,
    Future<T> Function(PluginRequestCredentials session) read,
  ) async {
    _requirePermission(siteUrl, target);
    final lease = _requests.capture(siteUrl);
    try {
      final session = await _session(siteUrl, lease: lease);
      if (!_isCurrent(lease)) {
        throw const WriteException(WriteFailure.forbidden);
      }
      final result = await session.run(() => read(session));
      if (!_isCurrent(lease)) {
        throw const WriteException(WriteFailure.forbidden);
      }
      return result;
    } on SiteLookupException catch (error, stackTrace) {
      if (!_isCurrent(lease) || error.statusCode != 404) rethrow;
      _invalidateLegacyFallback(siteUrl);
      await _reconcileUnavailable(siteUrl, target.topicId);
      throw WriteException(
        WriteFailure.unreachable,
        errors: [_targetUnavailable],
        statusCode: 404,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  Future<void> _reconcileUnavailable(String siteUrl, int topicId) async {
    try {
      await _reloadTopic(siteUrl, topicId);
    } catch (_) {}
  }

  Future<PluginRequestCredentials> _session(
    String siteUrl, {
    PluginSiteLease? lease,
  }) async {
    try {
      final credentials = await _requests.credentialsFor(siteUrl);
      if (lease != null && !_isCurrent(lease)) {
        throw const WriteException(WriteFailure.forbidden);
      }
      final apiKey = credentials.apiKey;
      if (apiKey == null) {
        throw const WriteException(WriteFailure.forbidden);
      }
      return credentials;
    } on WriteException {
      rethrow;
    } catch (error, stackTrace) {
      throw WriteException(
        WriteFailure.unreachable,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  bool _isCurrent(PluginSiteLease lease) => !isDisposed && lease.isCurrent;

  @override
  void dispose() {
    _writes.clear();
    _restoreSessions.clear();
    _restorePermits.clear();
    _legacyFallbackUnavailable.clear();
    for (final changes in _permissionChanges.values) {
      changes.dispose();
    }
    _permissionChanges.clear();
    super.dispose();
  }
}

/// FrameSafe for the same reason the controller is, which keeps it headless.
final class _PermissionChanges extends FrameSafeNotifier {
  void changed() => notifySafely();
}
