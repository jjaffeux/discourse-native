import '../../data/api_credentials.dart';
import '../../data/discourse_api_contracts.dart';
import '../../data/site_lifecycle.dart';
import '../../diagnostics/diagnostics_controller.dart';
import '../../foundation/frame_safe_notifier.dart';
import '../../plugin_api/shell_extensions.dart';
import 'assign_api.dart';
import 'assignment.dart';

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

/// Target-scoped reads and serialized writes for Assign.
///
/// Permission is checked again at the command boundary by [canAssign]. Modern
/// sites answer for the exact topic or post, so category-scoped denial wins;
/// the shell permits a missing legacy answer to fall back only to a freshly
/// fetched session capability. Site settings and persisted session state are
/// never authority.
class AssignmentController extends FrameSafeNotifier
    implements PluginCurrentUserObserver {
  AssignmentController({
    required this.api,
    required this.credentials,
    required this.lifecycle,
    AssignmentPermissionReader? canAssign,
    AssignmentPermissionSnapshotReader? permissionSnapshot,
    this.statusOptionsReader,
    required this.reloadTopic,
    AssignmentFallbackInvalidator? invalidateLegacyFallback,
  }) : assert(canAssign != null || permissionSnapshot != null),
       _legacyCanAssign = canAssign,
       _permissionSnapshot = permissionSnapshot,
       _legacyInvalidator = invalidateLegacyFallback;

  final AssignApi api;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final AssignmentPermissionReader? _legacyCanAssign;
  final AssignmentPermissionSnapshotReader? _permissionSnapshot;
  final AssignmentStatusOptionsReader? statusOptionsReader;
  final AssignmentTopicReloader reloadTopic;
  final AssignmentFallbackInvalidator? _legacyInvalidator;

  final Set<({String siteUrl, AssignmentTarget target})> _writes = {};
  final Set<String> _legacyFallbackUnavailable = {};

  static const _targetUnavailable =
      'This assignment target is no longer available.';
  static const _writeAlreadyInProgress =
      'An assignment update is already in progress.';

  bool isWriting(String siteUrl, AssignmentTarget target) =>
      _writes.contains((siteUrl: siteUrl, target: target));

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
      statusOptionsReader?.call(siteUrl) ?? (enabled: false, values: const []);

  void _invalidateLegacyFallback(String siteUrl) {
    final changed = _legacyFallbackUnavailable.add(siteUrl);
    _legacyInvalidator?.call(siteUrl);
    if (changed) notifySafely();
  }

  @override
  void pluginCurrentUserRefreshed(String siteUrl) {
    if (_legacyFallbackUnavailable.remove(siteUrl)) notifySafely();
  }

  void forget(String siteUrl) {
    final before = _writes.length;
    _writes.removeWhere((key) => key.siteUrl == siteUrl);
    final fallbackChanged = _legacyFallbackUnavailable.remove(siteUrl);
    if (_writes.length != before || fallbackChanged) notifySafely();
  }

  Future<AssignmentSuggestions> suggestions(
    String siteUrl,
    AssignmentTarget target,
  ) => _lookup(
    siteUrl,
    target,
    (session) => api.suggestions(
      siteUrl: siteUrl,
      apiKey: session.apiKey,
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
      apiKey: session.apiKey,
      clientId: session.clientId,
      term: term.trim(),
      suggestions: suggestions,
    ),
  );

  Future<String?> assign(
    String siteUrl,
    AssignmentTarget target,
    AssignmentAssignee assignee, {
    String? note,
    String? status,
  }) => _mutate(siteUrl, target, (session) {
    return api.assign(
      siteUrl: siteUrl,
      apiKey: session.apiKey,
      clientId: session.clientId,
      target: target,
      assignee: assignee,
      note: note,
      status: status,
    );
  });

  Future<String?> unassign(String siteUrl, AssignmentTarget target) =>
      _mutate(siteUrl, target, (session) {
        return api.unassign(
          siteUrl: siteUrl,
          apiKey: session.apiKey,
          clientId: session.clientId,
          target: target,
        );
      });

  Future<String?> _mutate(
    String siteUrl,
    AssignmentTarget target,
    Future<void> Function(_AssignmentSession session) write,
  ) async {
    if (isDisposed || !canAssign(siteUrl, target)) {
      return const WriteException(WriteFailure.forbidden).message;
    }

    final key = (siteUrl: siteUrl, target: target);
    if (!_writes.add(key)) return _writeAlreadyInProgress;
    notifySafely();
    final lease = lifecycle.capture(siteUrl);

    try {
      final session = await _session(siteUrl, lease: lease);
      if (!_isCurrent(lease)) return null;
      await write(session);
      if (!_isCurrent(lease)) return null;

      // The write response has no assignment record, and the tracking action
      // it creates may also change the post stream. Reconcile the full topic.
      await reloadTopic(siteUrl, target.topicId);
      return null;
    } on WriteException catch (error) {
      if (_isCurrent(lease) && error.statusCode == 404) {
        // A missing plugin route and a deleted target are intentionally
        // indistinguishable. A scoped topic read settles both without
        // disabling Assign for unrelated records.
        _invalidateLegacyFallback(siteUrl);
        await _reconcileUnavailable(siteUrl, target.topicId);
        return _targetUnavailable;
      }
      return error.message;
    } catch (error, stackTrace) {
      if (_isCurrent(lease)) {
        DiagnosticsSink.current.reportError(
          error,
          stackTrace,
          operation: 'assign.write',
          source: 'assign',
          handled: true,
          degraded: true,
        );
      }
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      _writes.remove(key);
      notifySafely();
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
    Future<T> Function(_AssignmentSession session) read,
  ) async {
    _requirePermission(siteUrl, target);
    final lease = lifecycle.capture(siteUrl);
    try {
      final session = await _session(siteUrl, lease: lease);
      if (!_isCurrent(lease)) {
        throw const WriteException(WriteFailure.forbidden);
      }
      final result = await read(session);
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
        errors: const [_targetUnavailable],
        statusCode: 404,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  Future<void> _reconcileUnavailable(String siteUrl, int topicId) async {
    try {
      await reloadTopic(siteUrl, topicId);
    } catch (error, stackTrace) {
      DiagnosticsSink.current.reportError(
        error,
        stackTrace,
        operation: 'assign.reconcileUnavailable',
        source: 'assign',
        handled: true,
        degraded: true,
      );
    }
  }

  Future<_AssignmentSession> _session(
    String siteUrl, {
    SiteLease? lease,
  }) async {
    try {
      final apiKey = await credentials.apiKeyFor(siteUrl);
      if (lease != null && !_isCurrent(lease)) {
        throw const WriteException(WriteFailure.forbidden);
      }
      if (apiKey == null) {
        throw const WriteException(WriteFailure.forbidden);
      }
      final clientId = await credentials.clientId();
      if (lease != null && !_isCurrent(lease)) {
        throw const WriteException(WriteFailure.forbidden);
      }
      return (apiKey: apiKey, clientId: clientId);
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

  bool _isCurrent(SiteLease lease) => !isDisposed && lease.isCurrent;

  @override
  void dispose() {
    _writes.clear();
    _legacyFallbackUnavailable.clear();
    super.dispose();
  }
}

typedef _AssignmentSession = ({String apiKey, String clientId});
